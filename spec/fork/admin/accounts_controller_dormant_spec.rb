# frozen_string_literal: true

require 'rails_helper'

# #1015 — 管理画面のアカウント一覧は、何かで絞り込んでいないときだけ放置アカウントを既定で隠す。
# ⚠ request spec で一覧を描くとレイアウトが Vite のマニフェストを要り、アセットを作らない spec/fork の
# CI では落ちる。ページは描かず、コントローラが組み立てる一覧（filtered_accounts）を直に見る。
RSpec.describe Admin::AccountsController do
  def accounts_for(params)
    controller = described_class.new
    controller.params = ActionController::Parameters.new(params)
    controller.send(:filtered_accounts).map(&:username)
  end

  before do
    { 'dormant' => 2.years.ago, 'active' => 1.day.ago }.each do |username, signed_in|
      user = Fabricate(:user, account: Fabricate(:account, username: username), current_sign_in_at: signed_in)
      user.account.update_column(:created_at, 2.years.ago)
    end
  end

  it '何も指定しないと隠す' do
    expect(accounts_for(origin: 'local')).to include('active').and(not_include('dormant'))
  end

  it '「すべて」（空の値）を選ぶと隠さない' do
    expect(accounts_for(origin: 'local', dormant: '')).to include('dormant', 'active')
  end

  it 'ユーザー名で探すときは隠さない' do
    expect(accounts_for(origin: 'local', username: 'dormant')).to include('dormant')
  end

  it '選択欄の値は、何も指定しないと「除く」・ユーザー名で探すときは空' do
    controller = described_class.new
    controller.params = ActionController::Parameters.new(origin: 'local')
    expect(controller.send(:dormant_filter_value)).to eq 'exclude'

    controller.params = ActionController::Parameters.new(username: 'x')
    expect(controller.send(:dormant_filter_value)).to be_nil
  end
end
