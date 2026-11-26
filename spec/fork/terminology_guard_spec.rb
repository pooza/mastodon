# frozen_string_literal: true

require 'rails_helper'

# 用語ポリシーの巻き戻り検知ガード（#972）。
#
# 上流の版上げで Crowdin の ja 翻訳が入れ替わると、置換済みの用語が静かに元へ戻る。
# 手元では .claude/skills/upstream-merge/scripts/terms-grep.sh で直し、最後の砦として
# ここが CI で落とす（fork-ci.yml の fork-spec ジョブ）。
#
# ⚠ 大文字化の禁止（#906）はここではなく stylelint が見る。CSS 側の規則なので
#   scss を直接検査できる stylelint のほうが当たりがよい。
#
# ⚠⚠ このファイルは 3 ブランチで同一に保つ。インスタンスの違いは dist/servers/ にある
#    各ブランチ固有の nginx 設定から判定し、ファイルを分岐させない（bshockdon で直して派生へ流す）。
#    ⚠ 4.7 までは config/themes.yml の登録テーマで見分けていたが、5.0 で独自テーマの登録を
#    外して 3 ブランチとも同じ themes.yml になったため使えなくなった（#1005）。
#
# rubocop:disable RSpec/DescribeClass

module ForkTerminologyGuard
  module_function

  # dist/servers/ にあるブランチ固有の nginx 設定でインスタンスを見分ける。
  SERVER_CONFS = {
    curesta: 'precure.ml.conf',
    delmulin: 'mstdn.delmulin.com.conf',
    bshockdon: 'mstdn.b-shock.org.conf',
  }.freeze

  def instance_name
    SERVER_CONFS.find { |_, conf| Rails.root.join('dist', 'servers', conf).exist? }&.first || :unknown
  end

  # ja の翻訳だけを見る。対象の用語はいずれも日本語なので、他言語を舐める必要が無い。
  def ja_locale_files
    Rails.root.glob('config/locales/ja.yml') +
      Rails.root.glob('config/locales/*.ja.yml') +
      Rails.root.glob('app/javascript/mastodon/locales/ja.json')
  end

  def occurrences(pattern, files)
    files.flat_map do |path|
      path.each_line.with_index(1).filter_map do |line, number|
        "#{path.relative_path_from(Rails.root)}:#{number}: #{line.strip}" if line.match?(pattern)
      end
    end
  end
end

RSpec.describe '用語ポリシーのガード (#972)' do
  include ForkTerminologyGuard

  it 'インスタンスを見分けられている（curesta の検査が黙って飛ばされていない）' do
    expect(ForkTerminologyGuard.instance_name).to_not eq :unknown
  end

  it 'ja の翻訳ファイルを実際に見つけている（検査が空振りしていない）' do
    expect(ja_locale_files).to include(Rails.root.join('config', 'locales', 'ja.yml'),
                                       Rails.root.join('app', 'javascript', 'mastodon', 'locales', 'ja.json'))
  end

  # 廃止用語。3 ブランチとも 0 件が正常。
  it '廃止用語「トゥート」が ja の翻訳に残っていない' do
    expect(occurrences(/トゥート/, ja_locale_files)).to eq []
  end

  # curesta だけの置換（#835 の系譜）。他の 2 ブランチでは「投稿」「ブースト」が正常なので
  # 走らせない。
  if ForkTerminologyGuard.instance_name == :curesta
    it '「投稿」がキュア！へ置換されている（curesta）' do
      expect(occurrences(/投稿/, ja_locale_files)).to eq []
    end

    it '「ブースト」がリキュア！へ置換されている（curesta）' do
      expect(occurrences(/ブースト/, ja_locale_files)).to eq []
    end
  end

  # curesta / delmulin はローカルタイムラインを nginx でデフォルトのハッシュタグ
  # （#precure_fun / #delmulin）の列へ読み替えている（#835）。中身は「このサーバーの投稿」ではないので、
  # ローカルタイムラインを指す呼び名は「このコミュニティ」に上書きする。
  # ⚠ 5.0 で増えた column.this_server（This Server）は上流の ja が未訳のため、上書きから漏れて
  #   英語のまま出ていた（#1004）。訳が付いても「このサーバー」に戻らないことをここで見る。
  if %i(curesta delmulin).include?(ForkTerminologyGuard.instance_name)
    %w(column.this_server firehose.local column.firehose_local).each do |key|
      it "ローカルタイムラインの呼び名 #{key} が「このコミュニティ」になっている（#{ForkTerminologyGuard.instance_name}）" do
        ja = JSON.parse(Rails.root.join('app', 'javascript', 'mastodon', 'locales', 'ja.json').read)
        expect(ja[key]).to include('このコミュニティ')
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
