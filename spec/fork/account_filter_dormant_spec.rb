# frozen_string_literal: true

require 'rails_helper'

# #1015 — 管理画面のアカウント一覧で、放置アカウント（発言 0 件・1 年以上使っていないローカルアカウント）を既定で隠す。
RSpec.describe AccountFilter do
  def local_account(username, created: 2.years.ago, signed_in: nil)
    user = Fabricate(:user, account: Fabricate(:account, username: username), current_sign_in_at: signed_in)
    user.account.update_column(:created_at, created)
    yield user if block_given?
    user.account
  end

  let(:dormant) { local_account('dormant', signed_in: 2.years.ago) }
  let(:never_used) { local_account('never_used') }
  let(:poster) { local_account('poster', signed_in: 2.years.ago) { |u| Fabricate(:status, account: u.account) } }
  let(:web_user) { local_account('web_user', signed_in: 1.month.ago) }
  let(:app_user) do
    local_account('app_user', signed_in: 2.years.ago) do |u|
      Fabricate(:access_token, resource_owner_id: u.id, last_used_at: 1.month.ago)
    end
  end
  let(:newcomer) { local_account('newcomer', created: 1.month.ago) }
  let(:remote) { Fabricate(:account, username: 'remote', domain: 'example.com') }
  let(:everyone) { [dormant, never_used, poster, web_user, app_user, newcomer, remote] }

  before { everyone }

  it 'exclude は放置アカウントだけを外す（リモート・作って 1 年未満・発言あり・Web かアプリで使った人は残る）' do
    results = described_class.new(dormant: 'exclude').results

    expect(results).to include(poster, web_user, app_user, newcomer, remote)
    expect(results).to_not include(dormant, never_used)
  end

  it 'ほかの絞り込みや、インスタンスアクターを除く既定の条件を消さない' do
    results = described_class.new(origin: 'local', dormant: 'exclude').results

    expect(results).to include(poster)
    expect(results).to_not include(remote, Account.representative)
  end

  it 'only は放置アカウントだけを出す' do
    expect(described_class.new(dormant: 'only').results)
      .to contain_exactly(dormant, never_used)
  end

  it '知らない値は拒む' do
    expect { described_class.new(dormant: 'wrong').results }
      .to raise_error(Mastodon::InvalidParameterError)
  end
end
