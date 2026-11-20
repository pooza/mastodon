# frozen_string_literal: true

require 'rails_helper'

# #1007 — 指定したアカウント（お知らせボット）へのフォローを、ローカルの利用者に解除させない。
# 文言とステータスは Misskey（pooza/misskey#467）とそろえている。capsicum#1402 がこれを受けるので、
# 変えるときは 3 か所をそろえること。
RSpec.describe ProtectedFollowAccounts do
  around do |example|
    ClimateControl.modify(PROTECTED_FOLLOW_ACCOUNTS: 'info, @Notice') { example.run }
  end

  let(:bot) { Fabricate(:account, username: 'info') }
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:other) { Fabricate(:account, username: 'bob') }
  let(:remote) { Fabricate(:account, username: 'info', domain: 'example.com') }

  describe '.protected?' do
    it 'ローカルの利用者から指定したアカウントへは true（@ 付き・大文字の指定も読む）' do
      expect(described_class.protected?(account, bot)).to be true
      expect(described_class.protected?(account, Fabricate(:account, username: 'notice'))).to be true
    end

    it '指定していないアカウント・同名のリモート・リモートの利用者・本人どうしは false' do
      expect(described_class.protected?(account, other)).to be false
      expect(described_class.protected?(account, remote)).to be false
      expect(described_class.protected?(Fabricate(:account, domain: 'example.com'), bot)).to be false
      expect(described_class.protected?(bot, bot)).to be false
    end

    it '環境変数が空なら何も守らない' do
      ClimateControl.modify(PROTECTED_FOLLOW_ACCOUNTS: '') do
        expect(described_class.protected?(account, bot)).to be false
      end
    end
  end

  describe 'API', type: :request do
    let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write:follows write:blocks') }
    let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

    before { account.follow!(bot) }

    it 'フォロー解除は 403 と Misskey と同じ文言で拒み、フォローを残す' do
      post "/api/v1/accounts/#{bot.id}/unfollow", headers: headers

      expect(response).to have_http_status(403)
      expect(response.parsed_body[:error]).to eq 'This user is specified by the server and cannot be unfollowed.'
      expect(account.following?(bot)).to be true
    end

    it 'ブロックは 403 と Misskey と同じ文言で拒み、フォローを残す' do
      post "/api/v1/accounts/#{bot.id}/block", headers: headers

      expect(response).to have_http_status(403)
      expect(response.parsed_body[:error]).to eq 'This user is specified by the server and cannot be blocked.'
      expect(account.blocking?(bot)).to be false
      expect(account.following?(bot)).to be true
    end

    it 'ほかのアカウントの解除は従来どおり通る' do
      account.follow!(other)
      post "/api/v1/accounts/#{other.id}/unfollow", headers: headers

      expect(response).to have_http_status(200)
      expect(account.following?(other)).to be false
    end
  end

  describe 'サービス層（一括処理・インポートなどの経路）' do
    before do
      account.follow!(bot)
      account.follow!(other)
    end

    it '一括解除は指定したアカウントだけ飛ばす' do
      Form::AccountBatch.new(action: 'unfollow', current_account: account, account_ids: [bot.id, other.id]).save

      expect(account.following?(bot)).to be true
      expect(account.following?(other)).to be false
    end

    it 'BlockService は指定したアカウントのブロックを黙って飛ばす' do
      BlockService.new.call(account, bot)

      expect(account.blocking?(bot)).to be false
      expect(account.following?(bot)).to be true
    end

    it '指定したアカウント自身が利用者をブロックすると、利用者からのフォローも外れる' do
      BlockService.new.call(bot, account)

      expect(bot.blocking?(account)).to be true
      expect(account.following?(bot)).to be false
    end

    it '指定したアカウント自身がフォロワーから外すのは通す' do
      RemoveFromFollowersService.new.call(bot, [account.id])

      expect(account.following?(bot)).to be false
    end
  end
end
