# frozen_string_literal: true

# フォーク改変（#1016・旧 #789 / #814）: 招待フォームから作る招待は、1 人だけ・期限付きに限る。
# 招待は申し込みのたびに 1 本ずつ出して DM で送る運用なので、複数人・無期限の招待は要らない。
# 上流の spec（Fabricator は無制限で作る）を壊さないよう、フォームのコントローラーが
# from_form を立てたときだけ効かせる。
module Invite::SingleUse
  extend ActiveSupport::Concern

  MAX_USES = 1
  DEFAULT_EXPIRES_IN = 1.week

  included do
    attribute :from_form, :boolean, default: false

    with_options on: :create, if: :from_form? do
      validates :max_uses, inclusion: { in: [MAX_USES] }
      validates :expires_at, presence: true
    end
  end
end
