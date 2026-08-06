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

  # コピーに失敗した絵文字。apply! を呼ぶまでは空
  def copy_failures
    @copy_failures ||= []
  end

  # 実際に書き込めた件数。コピーが失敗するとカテゴリ張り替えも 1 件落ちるので、
  # 計画値をそのまま報告すると実施していない件数を報告することになる
  def applied
    @applied ||= { copied: 0, recategorized: 0, removed_categories: 0 }
  end

  def apply!
    # 画像のアップロードを伴うので、カテゴリの張り替えとは分けてトランザクションの外で行う。
    # 個々のコピーの失敗で本命のカテゴリ同期まで巻き添えにしないよう、拾って続行する
    plan.copy.each do |emoji|
      emoji.copy!
      applied[:copied] += 1
    rescue ActiveRecord::RecordInvalid => e
      copy_failures << { shortcode: emoji.shortcode, message: e.record.errors.full_messages.join(', ') }
    end

    ApplicationRecord.transaction do
      plan.recategorize.each do |change|
        emoji = CustomEmoji.local.find_by(shortcode: change[:shortcode])
        next if emoji.nil? # コピーに失敗した絵文字

        emoji.update!(category: category_for(change[:to]))
        applied[:recategorized] += 1
      end

      CustomEmojiCategory.where(name: plan.stale_featured_categories).update_all(featured_emoji_id: nil) if plan.stale_featured_categories.any?
      applied[:removed_categories] = CustomEmojiCategory.where(name: plan.obsolete_categories).destroy_all.size if plan.obsolete_categories.any?
    end
  end

  private

  def build_plan
    desired = fetch_desired_categories
    local   = CustomEmoji.local.includes(:category).index_by(&:shortcode)
    remote  = CustomEmoji.where(domain: domain).index_by(&:shortcode)

    # 向こうの名前がこちらの shortcode 規則を満たさないものは持ち込めない。
    # 長さの上限はローカル絵文字とリモート絵文字で違う（128 / 2048）ので、規則を満たすか
    # どうかはローカル側の上限で判断する。Misskey の name は varchar(128) で偶然一致して
    # いるが、その一致に頼らず自分で弾く
    unsyncable = desired.keys.reject { |shortcode| syncable_shortcode?(shortcode) }
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

  def syncable_shortcode?(shortcode)
    shortcode.match?(CustomEmoji::SHORTCODE_ONLY_RE) && shortcode.length <= CustomEmoji::MAX_SHORTCODE_SIZE
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
