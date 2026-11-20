import { defineMessages } from 'react-intl';
import type { MessageDescriptor } from 'react-intl';

// pooza/mastodon#1007 — 指定したアカウント（お知らせボット）の解除・ブロックを拒んだときの文言。
// API は Misskey（pooza/misskey#467）とそろえた英文を返す（capsicum#1402 がそれを受ける）ので、
// Web UI ではその英文を見分けて、利用者の言語の文言に差し替える。
// ⚠ 英文は app/lib/protected_follow_accounts.rb の定数と一致させる。
const messages = defineMessages({
  cannotUnfollow: {
    id: 'alert.protected_follow.cannot_unfollow',
    defaultMessage:
      'This user is specified by the server and cannot be unfollowed.',
  },
  cannotBlock: {
    id: 'alert.protected_follow.cannot_block',
    defaultMessage: 'This user is specified by the server and cannot be blocked.',
  },
});

const byServerMessage: Record<string, MessageDescriptor> = {
  [messages.cannotUnfollow.defaultMessage]: messages.cannotUnfollow,
  [messages.cannotBlock.defaultMessage]: messages.cannotBlock,
};

export const protectedFollowMessage = (
  error: string | undefined,
): MessageDescriptor | undefined =>
  error === undefined ? undefined : byServerMessage[error];
