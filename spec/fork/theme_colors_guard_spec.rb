# frozen_string_literal: true

require 'rails_helper'

# #1005 — 独自のテーマカラーの巻き戻り検知ガード。
#
# 上流が tokens/index.scss や config/themes.yml を変えたときのマージで、独自色の読み込みや
# 登録が静かに消えると、選んでいた人の色が上流の既定へ戻る。CSS はビルドしないと確かめられないので、
# ここでは配線（読み込み・登録・表示名）を静的に見る。
#
# ⚠⚠ このファイルは 3 ブランチで同一に保つ。インスタンスは dist/servers/ のブランチ固有の
#    nginx 設定で見分ける（spec/fork/terminology_guard_spec.rb と同じ）。
#
RSpec.describe '独自のテーマカラーのガード (#1005)' do # rubocop:disable RSpec/DescribeClass
  let(:instance_colors) do
    {
      'precure.ml.conf' => %w(cure-lime cure-orange),
      'mstdn.delmulin.com.conf' => %w(daidai-orange dai popp maam hyunckel leona),
      'mstdn.b-shock.org.conf' => %w(bshock),
    }
  end
  let(:upstream_colors) { %w(indigo lime pink orange cyan) }
  let(:locales) { %i(ja en) }

  let(:expected) { instance_colors.find { |conf, _| Rails.root.join('dist', 'servers', conf).exist? }&.last }
  let(:colors) { YAML.load_file(Rails.root.join('config', 'themes.yml')).dig('default', 'colors') }
  let(:index_scss) { Rails.root.join('app', 'javascript', 'styles', 'mastodon', 'tokens', 'index.scss').read }
  let(:fork_scss) { Rails.root.join('app', 'javascript', 'styles', 'mastodon', 'tokens', 'theme', '_fork_colors.scss').read }

  it 'インスタンスを見分けられている' do
    expect(expected).to_not be_nil
  end

  it 'このインスタンスの独自色が先頭に登録され、上流の 5 色も残っている' do
    expect(colors.first(expected.size)).to eq expected
    expect(colors).to include(*upstream_colors)
  end

  it 'tokens/index.scss が独自色のパレットとダーク・ライトの定義を読んでいる' do
    expect(index_scss).to include("@use 'theme/fork_colors'", '@include fork_colors.palette;', '@include fork_colors.dark;', '@include fork_colors.light;')
  end

  it '登録した独自色のパレットと定義が _fork_colors.scss にある' do
    (colors - upstream_colors).each do |color|
      expect(fork_scss).to include("--color-#{color}-500:", "&[data-theme-color='#{color}']")
    end
  end

  it '登録した独自色に ja / en の表示名がある' do
    (colors - upstream_colors).each do |color|
      locales.each do |locale|
        expect(I18n.t("color_theme.#{color}", locale: locale, default: nil)).to be_present, "#{locale}: color_theme.#{color}"
      end
    end
  end
end
