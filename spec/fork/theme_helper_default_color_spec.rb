# frozen_string_literal: true

require 'rails_helper'

# #1005 — 利用者がテーマカラーを選んでいなければ、サーバー既定（管理画面の Setting.theme_color）を使う。
#
# 上流は UserSettings の web.theme_color の既定値を 'indigo' に固定しているため、色を選んでいない
# ログイン中の利用者には、サーバー既定が何であっても indigo が出る（効くのはログアウト中の画面だけ）。
# フォークでは theme と同じく、既定値をサーバー既定から引く形に変えている。
# 上流とのマージで 'indigo' 固定へ戻ると、選んでいない全員の色が静かに入れ替わる。
RSpec.describe ThemeHelper, type: :helper do
  subject { helper.page_theme_color('default') }

  before do
    allow(helper).to receive(:current_user).and_return(current_user)
    allow(Themes.instance).to receive(:available_theme_colors).with('default').and_return(%w(indigo lime pink))
    Setting.theme_color = 'pink'
  end

  let(:current_user) { Fabricate(:user) }

  it '色を選んでいない利用者にはサーバー既定が出る' do
    expect(subject).to eq 'pink'
  end

  it '色を選んだ利用者には、その色が出る' do
    current_user.settings.update('web.theme_color': 'lime')
    current_user.save!

    expect(subject).to eq 'lime'
  end

  it '選んだ色が無くなっていれば、サーバー既定へ落ちる' do
    current_user.settings.update('web.theme_color': 'removed')
    current_user.save!

    expect(subject).to eq 'pink'
  end

  it 'UserSettings の既定値がサーバー既定を引いている（上流の indigo 固定へ戻っていない）' do
    expect(UserSettings.new({})['web.theme_color']).to eq 'pink'
  end
end
