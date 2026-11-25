# frozen_string_literal: true

require 'rails_helper'

# #1016（旧 #789 / #814）— 招待フォームから作る招待は 1 人だけ・期限付き。
# 2023 年の改造は 4.6 のマージで上流の形に戻って消えていた。戻ったらここで気づく。
RSpec.describe Invite::SingleUse do
  let(:user) { Fabricate(:user) }

  def form_invite(**attrs)
    Invite.new(user: user, from_form: true, **attrs)
  end

  describe 'フォームから作る招待' do
    it '1 人・期限付きなら作れる' do
      expect(form_invite(max_uses: 1, expires_in: 1.week.to_i)).to be_valid
    end

    it '人数が無制限・2 人以上なら拒む' do
      expect(form_invite(max_uses: nil, expires_in: 1.week.to_i)).to_not be_valid
      expect(form_invite(max_uses: 5, expires_in: 1.week.to_i)).to_not be_valid
    end

    it '期限が無ければ拒む' do
      expect(form_invite(max_uses: 1, expires_in: '')).to_not be_valid
    end
  end

  describe 'フォーム以外' do
    it '上流の Fabricator（無制限・無期限）は今までどおり作れる' do
      expect { Fabricate(:invite) }.to_not raise_error
    end

    it '昔の無制限の招待も期限切れにできる（作るときだけ効かせる）' do
      invite = Fabricate(:invite, max_uses: nil, expires_at: nil)

      expect { invite.expire! }.to change { invite.reload.valid_for_use? }.from(true).to(false)
    end
  end
end
