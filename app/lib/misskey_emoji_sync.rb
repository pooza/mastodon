# frozen_string_literal: true

# 姉妹 Misskey サーバーのカスタム絵文字を正として、こちらの絵文字とカテゴリを揃える。
#
# 新規登録は常に Misskey 側で行う運用なので、同期は一方向で、削除は一切行わない。
# 向こうに無いローカル絵文字は（向こうで削除されたものも含めて）触らずに報告するだけ。
#
# 管理画面の「ローカルにコピー」が呼ぶ CustomEmoji#copy! は shortcode と image しか
# 写さずカテゴリを引き継がないため、その穴を埋めるのが主目的。
class MisskeyEmojiSync
  class Error < StandardError; end

  Plan = Struct.new(
    :copy,
    :recategorize,
    :obsolete_categories,
    :stale_featured_categories,
    :orphans,
    :awaiting_federation,
    :unsyncable,
    keyword_init: true
  )

  attr_reader :domain

  def initialize(origin)
    @domain = origin.to_s.strip.sub(%r{\Ahttps?://}i, '').chomp('/')

    raise Error, "Not a valid origin: #{origin}" if @domain.blank? || @domain.include?('/')
  end

  def plan
    @plan ||= build_plan
  end

  def apply!
    # 画像のアップロードを伴うので、カテゴリの張り替えとは分けてトランザクションの外で行う
    plan.copy.each(&:copy!)

    ApplicationRecord.transaction do
      plan.recategorize.each do |change|
        CustomEmoji.local.find_by!(shortcode: change[:shortcode]).update!(category: category_for(change[:to]))
      end

      CustomEmojiCategory.where(name: plan.stale_featured_categories).update_all(featured_emoji_id: nil) if plan.stale_featured_categories.any?
      CustomEmojiCategory.where(name: plan.obsolete_categories).destroy_all if plan.obsolete_categories.any?
    end
  end

  private

  def build_plan
    desired = fetch_desired_categories
    local   = CustomEmoji.local.includes(:category).index_by(&:shortcode)
    remote  = CustomEmoji.where(domain: domain).index_by(&:shortcode)

    # 向こうの名前がこちらの shortcode 規則を満たさないものは、リモート絵文字としても
    # 連合してこないので永久に持ち込めない
    unsyncable = desired.keys.grep_v(CustomEmoji::SHORTCODE_ONLY_RE)
    missing    = desired.keys - unsyncable - local.keys

    # 向こうに現存するものだけコピーする。リモート絵文字は向こうで削除されても残るため、
    # 絞らないと削除済みの絵文字を蘇らせてしまう
    copy = missing.filter_map { |shortcode| remote[shortcode] }.sort_by(&:shortcode)

    # 最終的なカテゴリの割り当て。空になるカテゴリの判定に使う
    assignments  = {}
    recategorize = []

    local.each_value do |emoji|
      current = emoji.category&.name

      unless desired.key?(emoji.shortcode)
        assignments[emoji.shortcode] = current
        next
      end

      assignments[emoji.shortcode] = desired[emoji.shortcode]
      recategorize << { shortcode: emoji.shortcode, from: current, to: desired[emoji.shortcode] } if desired[emoji.shortcode] != current
    end

    copy.each do |emoji|
      assignments[emoji.shortcode] = desired[emoji.shortcode]
      recategorize << { shortcode: emoji.shortcode, from: nil, to: desired[emoji.shortcode] } unless desired[emoji.shortcode].nil?
    end

    used     = assignments.values.compact.to_set
    obsolete = CustomEmojiCategory.pluck(:name).reject { |name| used.include?(name) }.sort

    Plan.new(
      copy: copy,
      recategorize: recategorize.sort_by { |change| change[:shortcode] },
      obsolete_categories: obsolete,
      stale_featured_categories: stale_featured_categories(assignments, obsolete),
      orphans: (local.keys - desired.keys).sort,
      awaiting_federation: (missing - remote.keys).sort,
      unsyncable: unsyncable.sort
    )
  end

  # 注目絵文字が別のカテゴリへ移ってしまったカテゴリ。ぶら下がった参照を落とす
  def stale_featured_categories(assignments, obsolete)
    CustomEmojiCategory.where.not(featured_emoji_id: nil).includes(:featured_emoji).filter_map do |category|
      next if obsolete.include?(category.name)

      shortcode = category.featured_emoji&.shortcode
      category.name unless shortcode.present? && assignments[shortcode] == category.name
    end.sort
  end

  def fetch_desired_categories
    json = Request.new(:get, "https://#{domain}/api/emojis").perform do |response|
      raise Error, "#{domain} returned HTTP #{response.code}" unless response.code == 200

      JSON.parse(response.body_with_limit)
    end

    raise Error, "Unexpected response from #{domain}" unless json.is_a?(Hash) && json['emojis'].is_a?(Array)
    raise Error, "No custom emoji returned by #{domain}" if json['emojis'].empty?

    json['emojis'].to_h { |emoji| [emoji['name'], emoji['category'].presence] }
  end

  def category_for(name)
    return if name.nil?

    @categories ||= {}
    @categories[name] ||= CustomEmojiCategory.find_or_create_by!(name: name)
  end
end
