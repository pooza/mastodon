// Web の投稿欄で使う文字数上限（フォーク独自）。
//
// サーバーの上限（`configuration.statuses.max_characters`）をそのまま使わず 8 割に絞る。
// 旧 UI では `compose_form_container.js` で同じ計算をしていた（2024-09 の「字数」）。
// 5.0 で旧 UI が消えたので、新 UI の文字数表示と送信前検査の両方からここを呼ぶ。
const SERVER_DEFAULT_MAX_CHARACTERS = 3000;
const WEB_COMPOSE_RATIO = 0.8;

export function composeMaxCharacters(serverMax: number | undefined): number {
  return Math.floor(
    (serverMax ?? SERVER_DEFAULT_MAX_CHARACTERS) * WEB_COMPOSE_RATIO,
  );
}
