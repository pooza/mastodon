# frozen_string_literal: true

# pooza/mastodon#1007 — 指定したアカウント（お知らせボット）へのフォローを、ローカルの利用者に解除させない。
#
# 指定は環境変数 PROTECTED_FOLLOW_ACCOUNTS（このサーバーのユーザー名をカンマ区切り。例: `info`）。
# 登録時のフォローは招待リンクの自動フォロー（invites.autofollow）でまかなう。
#
# - フォロー解除の API とブロックの API は 403 で拒む（文言は Misskey の pooza/misskey#467 とそろえる。
#   capsicum#1402 がこの文言を受ける）
# - 一括解除・CSV のインポート・ブロックのインポートなどは、その 1 件だけ黙って飛ばす
#   （UnfollowService / BlockService で止める）
# - 対象は「フォローしている側がローカルで、フォローされている側が指定したアカウント」だけ。
#   リモートからの処理（Reject・Undo など）や、指定したアカウント自身の操作は通す
module ProtectedFollowAccounts
  # API の利用者（capsicum）が機械的に見分ける固定の英文なので翻訳しない。Web UI は
  # app/javascript/mastodon/actions/protected_follow_alert.ts で利用者の言語に差し替える
  # rubocop:disable I18n/RailsI18n/DecorateString
  UNFOLLOW_MESSAGE = 'This user is specified by the server and cannot be unfollowed.'
  BLOCK_MESSAGE = 'This user is specified by the server and cannot be blocked.'
  # rubocop:enable I18n/RailsI18n/DecorateString

  class Error < Mastodon::NotPermittedError; end

  module_function

  def usernames
    ENV.fetch('PROTECTED_FOLLOW_ACCOUNTS', '').split(',').map { |name| name.strip.delete_prefix('@').downcase }.compact_blank
  end

  # 引っ越したアカウントは守らない。引っ越しの後始末（FollowMigrationService・
  # MigratedFollowDeliveryWorker）が旧アカウントへのフォローを外せるようにする（#1009 の Codex 指摘）
  def account?(account)
    account.present? && account.local? && !account.moved? && usernames.include?(account.username.downcase)
  end

  # follower が target へのフォローを外せない（ブロックもできない）とき true
  def protected?(follower, target)
    follower.present? && follower.local? && follower.id != target&.id && account?(target)
  end
end
