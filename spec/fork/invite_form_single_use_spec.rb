# frozen_string_literal: true

require 'rails_helper'

# #1016 — 利用者用（/invites）と管理画面（/admin/invites）の招待フォームは、1 人だけ・期限付きでしか選べない。
# ⚠ request spec でページを描くと、レイアウトが Vite のマニフェストを要り、アセットを作らない spec/fork の CI では落ちる。
# view spec はレイアウトを描かないので、テンプレートだけを描いて確かめる。
RSpec.describe 'invite forms', type: :view do
  before do
    # policy は Pundit がコントローラから渡すヘルパーで、view spec の view には無い
    invite_policy = instance_double(InvitePolicy, create?: true, deactivate_all?: false)
    view.define_singleton_method(:policy) { |_record| invite_policy }
    assign(:invite, Invite.new)
    assign(:invites, Invite.none.page(1))
  end

  %w(invites admin/invites).each do |controller_path|
    it "#{controller_path}/index: 人数は 1 人だけ・期限は空の選択なし（既定は 1 週間）" do
      # describe の文字列からは決まらないので、部分テンプレートの探し先とルーティングを明示する
      controller.controller_path = controller_path
      controller.request.path_parameters.merge!(controller: controller_path, action: 'index')
      view.lookup_context.prefixes = [controller_path]
      render template: "#{controller_path}/index"

      page = Nokogiri::HTML(rendered)
      expect(page.css('select#invite_max_uses option').pluck('value')).to eq ['1']
      expires = page.css('select#invite_expires_in option')
      expect(expires.pluck('value')).to_not include('')
      expect(expires.find { |o| o['selected'] }&.[]('value')).to eq 1.week.to_i.to_s
    end
  end
end
