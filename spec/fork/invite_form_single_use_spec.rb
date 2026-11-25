# frozen_string_literal: true

require 'rails_helper'

# #1016 — 利用者用（/invites）と管理画面（/admin/invites）の招待フォームは、1 人だけ・期限付きでしか作れない。
RSpec.describe 'Invite forms are single use with expiry', type: :request do
  # :admin_user は読み込み時のロールを握ったままなので、ロールを入れ直す spec（fork_customizations_spec）の後だと落ちる
  let(:user) { Fabricate(:user, role: UserRole.find_by(name: 'Admin')) }

  before { sign_in user }

  [
    ['/invites', :invites_path],
    ['/admin/invites', :admin_invites_path],
  ].each do |label, path_helper|
    describe label do
      let(:path) { public_send(path_helper) }

      it '人数は 1 人だけ・期限は空の選択なし（既定は 1 週間）' do
        get path

        page = Nokogiri::HTML(response.body)
        expect(page.css('select#invite_max_uses option').pluck('value')).to eq ['1']
        expires = page.css('select#invite_expires_in option')
        expect(expires.pluck('value')).to_not include('')
        expect(expires.find { |o| o['selected'] }&.[]('value')).to eq 1.week.to_i.to_s
      end

      it '人数を書き換えて送っても作れない' do
        expect { post path, params: { invite: { max_uses: '100', expires_in: 1.week.to_i } } }
          .to_not change(Invite, :count)
      end

      it '期限を空で送っても作れない' do
        expect { post path, params: { invite: { max_uses: '1', expires_in: '' } } }
          .to_not change(Invite, :count)
      end

      it '1 人・期限付きなら作れる' do
        expect { post path, params: { invite: { max_uses: '1', expires_in: 1.day.to_i } } }
          .to change(Invite, :count).by(1)
        expect(Invite.last).to have_attributes(max_uses: 1, expires_at: be_present)
      end
    end
  end
end
