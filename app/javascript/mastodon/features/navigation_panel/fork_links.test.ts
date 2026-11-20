import { toLinkGroups } from './fork_links';

// links.json の読み取り（#991）。
describe('toLinkGroups', () => {
  it('見出し付きグループの配列を読む', () => {
    expect(
      toLinkGroups([
        {
          body: 'モロヘイヤ',
          links: [{ href: '/mulukhiya', body: 'Home', icon: 'eco' }],
        },
      ]),
    ).toEqual([
      {
        body: 'モロヘイヤ',
        links: [{ href: '/mulukhiya', body: 'Home', icon: 'eco' }],
      },
    ]);
  });

  it('リンクだけの配列は見出しなしの 1 グループにする', () => {
    expect(toLinkGroups([{ href: '/contact', body: 'お問い合わせ' }])).toEqual([
      { links: [{ href: '/contact', body: 'お問い合わせ' }] },
    ]);
  });

  it('リンクの配列のグループは見出しなしにする', () => {
    expect(toLinkGroups([[{ href: '/a', body: 'A' }]])).toEqual([
      { links: [{ href: '/a', body: 'A' }] },
    ]);
  });

  it('描画するフィールドが文字列でない項目だけを落とす', () => {
    expect(
      toLinkGroups([
        {
          body: 'その他',
          links: [
            { href: '/help', body: {} },
            { href: '/ok', body: 'OK', icon: 3 },
            { href: '/fine', body: 'Fine' },
          ],
        },
      ]),
    ).toEqual([{ body: 'その他', links: [{ href: '/fine', body: 'Fine' }] }]);
  });

  it('配列でなければ空にする', () => {
    expect(toLinkGroups({ links: [] })).toEqual([]);
  });
});
