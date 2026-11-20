import { protectedFollowMessage } from './protected_follow_alert';

// #1007 — サーバーの英文（app/lib/protected_follow_accounts.rb）と一致したときだけ差し替える
describe('protectedFollowMessage', () => {
  it('フォロー解除を拒んだ英文を見分ける', () => {
    expect(
      protectedFollowMessage(
        'This user is specified by the server and cannot be unfollowed.',
      )?.id,
    ).toBe('alert.protected_follow.cannot_unfollow');
  });

  it('ブロックを拒んだ英文を見分ける', () => {
    expect(
      protectedFollowMessage(
        'This user is specified by the server and cannot be blocked.',
      )?.id,
    ).toBe('alert.protected_follow.cannot_block');
  });

  it('ほかのエラーと空は素通しする', () => {
    expect(protectedFollowMessage('This action is not allowed')).toBeUndefined();
    expect(protectedFollowMessage(undefined)).toBeUndefined();
  });
});
