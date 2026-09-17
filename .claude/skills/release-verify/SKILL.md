---
name: release-verify
description: pooza/mastodon を 6 台（本番 shallu/gomander/zugoga・ステージング dev24/25/26）へ適用したあと、本当に当たっているかを外形から確かめる。ブランチ・マイグレーション・アセット到達性・CSP 実効ヘッダ・テーマ CSS の後勝ちまで。版上げの検証や「デプロイできてる？」の確認に使う。
---

# 版上げの検証（適用後の外形）

⚠⚠ **正本はこのファイル。** [docs/CLAUDE.md](../../../docs/CLAUDE.md) の「サーバーとデプロイ」のうち適用後の確認はここへのポインタ。

**読むだけで終わる**（curl と grep と ssh 越しの参照のみ）ので自動起動してよい。⚠ **デプロイそのものはここではやらない。**手順の正本は [chubo2 infra-mastodon.md](https://github.com/pooza/chubo2/blob/main/docs/infra-mastodon.md)。

## 🔴 なぜ独立に検証するのか

**スクリプトが最後まで走ったことは、適用できた根拠にならない。**`git checkout` の出力をパイプに通すと `set -e` がパイプ末尾の終了コードしか見ないため、**切り替え失敗を素通りして bundle / migrate / assets まで走る**。「適用したつもりで旧版のまま、アセットだけ再生成」という最悪の状態になりうる（→ [staging-rc](../staging-rc/SKILL.md)）。

## 対象

| | ホスト | ドメイン | ブランチ |
| --- | --- | --- | --- |
| 本番 | shallu | 美食丼 | `bshockdon` |
| 本番 | gomander | キュアスタ！ | `curesta` |
| 本番 | zugoga | デルムリン丼 | `delmulin` |
| ステージング | dev24 / dev25 / dev26 | — | 同上 |

着地ユーザーは 6 台とも `mastodon`、リポジトリは `~mastodon/repos/mastodon`。SSH は本番が `<host>.b-shock.co.jp`（デフォルト mastodon 着地）、ステージングは `mastodon@devNN`。

## 1. ホスト側（各台で）

```bash
git rev-parse --abbrev-ref HEAD                              # 意図したブランチか
RAILS_ENV=production bundle exec rails db:abort_if_pending_migrations
stat -f %Sm public/packs/.vite/manifest.json                 # アセットが今回のものか
md5 -q public/packs/.vite/manifest.json                      # 全台で揃うこと
```

⚠ `stat -f` / `md5 -q` は **FreeBSD の書式**。6 台とも FreeBSD なのでこれでよい。

**全台で同一の manifest** であることも見る。LB 分散で HTML と CSS が別ビルドの台に当たると、1 台だけ取りこぼしていても引き方によっては緑に見える。

## 2. 外形（手元から）

```bash
.claude/skills/release-verify/scripts/assets.sh <domain>   # アセット到達性（#954）
.claude/skills/release-verify/scripts/csp.sh    <domain>   # CSP 実効ヘッダ
curl -s https://<domain>/api/v2/instance | jq -r .version  # 版
```

⚠ `/api/v2/instance` の `version` は**再起動直後 1〜2 分は旧版のまま出る**（Redis キャッシュ）。異常ではない。

### アセット到達性（#954）

🔴 **バックエンドが生きていれば API も `/api/v2/instance` も通るので、§1 の 4 本は全部緑のまま WebUI だけ崩れる。**4.6 以降のフロントは Vite のハッシュ付きチャンクなので、manifest とファイルがずれると「一部の CSS だけ 404」になる。**普段 WebUI を使わないと気づけない**ため機械的に引く。

### CSP 実効ヘッダ

Material Symbols（スタートメニューのアイコン）は `fonts.googleapis.com` のスタイルシート頼みで、CSP のホスト指定が版上げで落ちると**アイコンの代わりに `home` などの文字列がそのまま出る**。

🔴 **HTML に link が出ていることだけで CSP を判断しない。**link は `application.html.haml` に無条件で書かれているので、**CSP が落ちていても必ず出る**。ブラウザは CSP で弾いて文字列を表示するのに、`grep` は緑になる。⚠ `spec/fork/` のガードもチェックアウトした Rails 設定を見るだけで、**実際に配信されているヘッダは見ていない**。

⚠ `style-src`（スタイルシート）と `font-src`（フォント本体）は**別のホスト**なので、両方見ないと片方だけ落ちた状態を見逃す。

## 3. テーマ CSS の後勝ち

ビルド後、テーマが実際に効いているかを生成 CSS で確認する。**後勝ちの上書きなので最後の値を見る:**

```bash
grep -o '\-\-color-grey-100:[^;]*' public/packs/assets/themes/<テーマ>-*.css | tail -1
```

default テーマと同じ値なら適用されていない。テーマ名は `config/themes.yml` の登録から取る。

## 4. instance ブランチへ戻したあとの CI

🔴 **`merge/**` が緑でも instance ブランチへ戻した push で落ちることがある。**Tier 1/2 は**変更ファイルに限定**して lint するため、**比較の基点が変わると検査対象も変わる**。⚠⚠ **版上げの検証は instance ブランチへ戻した後の CI まで見る**（→ [upstream-merge §6](../upstream-merge/SKILL.md#6-ci)）。
