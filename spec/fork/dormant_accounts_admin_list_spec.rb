# frozen_string_literal: true

require 'rails_helper'

# #1015 — 管理画面のアカウント一覧は、何かで絞り込んでいないときだけ放置アカウントを既定で隠す。
RSpec.describe 'Admin accounts list hides dormant accounts by default', type: :request do
  before do
    # :admin_user は読み込み時のロールを握ったままなので、ロールを入れ直す spec（fork_customizations_spec）の後だと落ちる
    sign_in Fabricate(:user, role: UserRole.find_by(name: 'Admin'))

    %w(dormant active).each do |username|
      user = Fabricate(:user, account: Fabricate(:account, username: username), current_sign_in_at: username == 'active' ? 1.day.ago : 2.years.ago)
      user.account.update_column(:created_at, 2.years.ago)
    end
  end

  it '何も指定しないと隠す' do
    get admin_accounts_path(origin: 'local')

    expect(response).to have_http_status(200)
    expect(response.body).to include('@active')
    expect(response.body).to_not include('@dormant')
  end

  it '「すべて」（空の値）を選ぶと隠さない' do
    get admin_accounts_path(origin: 'local', dormant: '')

    expect(response.body).to include('@dormant')
  end

  it 'ユーザー名で探すときは隠さない' do
    get admin_accounts_path(origin: 'local', username: 'dormant')

    expect(response.body).to include('@dormant')
  end
end
