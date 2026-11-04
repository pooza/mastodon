import { composeMaxCharacters } from './max_characters';

describe('composeMaxCharacters', () => {
  it('サーバーの上限の 8 割を返す', () => {
    expect(composeMaxCharacters(3000)).toBe(2400);
    expect(composeMaxCharacters(500)).toBe(400);
  });

  it('端数は切り捨てる', () => {
    expect(composeMaxCharacters(999)).toBe(799);
  });

  it('サーバー設定が無ければ 3000 を基準にする', () => {
    expect(composeMaxCharacters(undefined)).toBe(2400);
  });
});
