import { changeTagset } from '../actions/compose';

import { composeReducer } from './compose';

// 実況タグセット（#989）の reducer。番組表エントリは action で受け取り、
// reducer では通信しない（#997 の Codex 指摘）。
describe('composeReducer: COMPOSE_TAGSET_CHANGE', () => {
  const draft = composeReducer(undefined, { type: 'INIT' }).set(
    'text',
    '書きかけの下書き',
  );

  it('タグなしを選ぶと user_tags を null にするコマンドになる', () => {
    const state = composeReducer(draft, changeTagset('empty'));
    expect(state.get('text')).toBe(
      ['command: user_config', 'tagging:', '  user_tags: null'].join('\n'),
    );
  });

  it('番組を選ぶとエントリからタグセットのコマンドを組み立てる', () => {
    const state = composeReducer(
      draft,
      changeTagset('precure', {
        series: 'テストプリキュア！',
        livecure: true,
        episode: 38,
        subtitle: 'サブタイトル',
        minutes: 30,
        extra_tags: ['ニチアサ'],
      }),
    );
    expect(state.get('text')).toBe(
      [
        'command: user_config',
        'tagging:',
        '  user_tags:',
        '  - テストプリキュア！',
        '  - 実況',
        '  - 38話',
        '  - サブタイトル',
        '  - ニチアサ',
        '  minutes: 30',
      ].join('\n'),
    );
  });

  it('extra_tags を持たない番組でも例外にならない', () => {
    const state = composeReducer(
      draft,
      changeTagset('air', { series: 'エア番組テスト', air: true }),
    );
    expect(state.get('text')).toBe(
      [
        'command: user_config',
        'tagging:',
        '  user_tags:',
        '  - エア番組テスト',
        '  - エア番組',
      ].join('\n'),
    );
  });

  it('エントリが無いときは下書きを変えない', () => {
    const state = composeReducer(draft, changeTagset('unknown'));
    expect(state.get('text')).toBe('書きかけの下書き');
  });
});
