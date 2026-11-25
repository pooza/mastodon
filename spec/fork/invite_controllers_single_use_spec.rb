# frozen_string_literal: true

require 'rails_helper'

# #1016 — 招待のコントローラは、フォームから作る招待に from_form を立てる（Invite::SingleUse が効く条件）。
# ⚠ 拒まれたときは index を描き直し、レイアウトが Vite のマニフェストを要るので、spec/fork の CI では
# 確かめられない。拒む中身は spec/fork/invite/single_use_spec.rb で見る。ここは作れる側（リダイレクトで終わる）だけ。
RSpec.describe 'Invite controllers create single use invites', type: :request do
  # :admin_user は読み込み時のロールを握ったままなので、ロールを入れ直す spec（fork_customizations_spec）の後だと落ちる
  before { sign_in Fabricate(:user, role: UserRole.find_by(name: 'Admin')) }

  %w(invites_controller.rb admin/invites_controller.rb).each do |file|
    it "#{file} はフォームから作る招待に from_form を立てる" do
      expect(Rails.root.join('app', 'controllers', file).read).to include('@invite.from_form = true')
    end
  end

  %i(invites_path admin_invites_path).each do |path_helper|
    it "#{path_helper}: 1 人・期限付きなら作れる" do
      expect { post public_send(path_helper), params: { invite: { max_uses: '1', expires_in: 1.day.to_i } } }
        .to change(Invite, :count).by(1)
      expect(Invite.last).to have_attributes(max_uses: 1, expires_at: be_present)
    end
  end
end
