# pooza/mastodon 開発ガイド

## プロジェクト概要

FreeBSD 向けに調整された Mastodon のフォーク。拙作ツール [pooza/mulukhiya-toot-proxy](https://github.com/pooza/mulukhiya-toot-proxy)（通称「モロヘイヤ」）と併用することが前提。

- **ベース**: mastodon/mastodon（upstream）
- **デフォルトブランチ**: `bshockdon`
- **対象 OS**: FreeBSD（ZFS）。本番 shallu / zugoga は 14.4-RELEASE、gomander とステージング 3 台は 15.1-RELEASE
- **技術スタック**: Ruby (Rails) / Node.js (streaming) / PostgreSQL / Redis

**このドキュメントはフォーク開発の知見を置く場所。** サーバー構成・デプロイ手順・インフラの罠は
[pooza/chubo2 の docs/infra-note.md](https://github.com/pooza/chubo2/blob/main/docs/infra-note.md) が正本で、
ここには複写しない（→「情報の記載先ルール」）。

## ブランチ戦略

### インスタンス別ブランチ

| ブランチ | インスタンス | 本番 | ステージング | 目的 |
| --- | --- | --- | --- | --- |
| `bshockdon` | 美食丼 | shallu | dev24 | デフォルト。upstream のタグをマージし、FreeBSD 向けの調整を加える |
| `curesta` | キュアスタ！ | gomander | dev25 | bshockdon から派生。キュアスタ！固有の調整 |
| `delmulin` | デルムリン丼 | zugoga | dev26 | bshockdon から派生。デルムリン丼固有の調整 |

美食丼は汎用の Mastodon であるため `bshockdon` がベース。**3 インスタンスで共有する改変は
必ず `bshockdon` 側の構造で提供する**（派生側に独自構造を作ると差分が膨らむ）。

### 作業ブランチの命名

| 命名 | 例 | 用途 |
| --- | --- | --- |
| `merge/<次の版>/<インスタンス>` | `merge/4.7/bshockdon` | upstream 追従の作業ブランチ。RC 期間に切って進める |
| `stable/<版>/<インスタンス>` | `stable/4.6/curesta` | リリース済み版のスナップショット。切り戻し先 |

### マージフロー

```text
upstream (tag) → merge/<版>/bshockdon → merge/<版>/curesta
                                      → merge/<版>/delmulin
```

派生ブランチには **upstream を直接マージしない**。必ず bshockdon 経由で流す。

## upstream 追従の手順

### タイミング（chubo2 側と共有の運用方針）

- **RC が出たらステージング 3 台向けにマージを始める。** 目的は **stable リリース当日に本番へ
  デプロイできる状態を作っておくこと**。本番に RC を載せるためではない
- **RC 期間にモロヘイヤ側でやることは無い。** この期間の作業は `pooza/mastodon` の 3 ブランチの
  マージとステージング適用に閉じる
- パッチリリース（4.6.x 等）は差分が小さければ運用者が手で流す

### 1. 衝突の切り分け（SAME / FORK トリアージ）

マージベースは「stable-4.x が main から分岐した地点」まで遡るため、**衝突の大半はフォークと無関係な
「4.x へのバックポート vs main の本流版」**になる。4.7.0-rc.1 では 58 件中 28 件がこれだった。

各衝突ファイルの HEAD 版を**直前のリリースタグ**と突き合わせ、同一なら **フォーク改変ゼロ＝上流版を
丸ごと採用してよい**と機械的に判定できる:

```bash
for f in $(git diff --name-only --diff-filter=U); do
  a=$(git rev-parse "HEAD:$f" 2>/dev/null || echo none)
  b=$(git rev-parse "v4.6.6:$f" 2>/dev/null || echo none)   # 直前のリリースタグ
  [ "$a" = "$b" ] && echo "SAME  $f" || echo "FORK  $f"
done | sort
```

⚠ **FORK 側を `git checkout --ours` で丸ごと採ってはいけない。** 上流がそのファイルに加えた
変更まで捨てることになる。**上流版を土台に、フォーク改変だけを再適用する**のが原則
（例外は README.md のように上流を全面置換しているファイルだけ）。

### 2. 取りこぼし検査（機械的にやる）

解決後、**集合比較で漏れを検出する**。目視で「たぶん大丈夫」と判断しない:

```bash
git diff --cached --name-only <上流タグ> | sort > /tmp/A   # 上流と差異があるファイル
git diff --name-only <前タグ> origin/<ブランチ> | sort > /tmp/B  # フォークが実際に改変しているファイル

comm -23 /tmp/A /tmp/B   # 上流変更の取りこぼし疑い
comm -13 /tmp/A /tmp/B   # フォーク改変の消失疑い
```

上流がファイルを移動した場合は新旧パスの対で出るので、それだけは正常。

### 3. 衝突しないのに壊れる箇所（最重要）

**フォーク独自ファイルは上流のリネーム・依存削除に追従しないが、衝突としては現れない。**
マージ後に必ずビルドを通すこと。4.7 で実際に踏んだ 3 件:

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| `lib/mastodon/version.rb` が 4.7.6 になる | major/minor は上流、patch だけ旧版が残る混成を自動マージが作る | フォークは version.rb を改変していないので上流版で上書き |
| テーマ SCSS がビルド不能 | 上流が `styles/mastodon/theme/` → `tokens/` にリネーム。独自エントリポイントは追従しない | 後述の再同期 |
| `Rolldown failed to resolve import "react-overlays/Overlay"` | 上流が react-overlays を依存ごと撤去 | 後述のタグセット移植 |

### 4. 版ごとの定例作業

#### テーマエントリポイントの再同期

`app/javascript/styles/<テーマ>.scss` は **`application.scss` の全文 + 末尾のテーマブロック**という
構造で、上流が application.scss を変えても追従しない。版上げのたびに再同期する:

```python
base = open("app/javascript/styles/application.scss").read().rstrip("\n")
for name in [...]:                        # ブランチごとのテーマ名
    lines = open(f"app/javascript/styles/{name}.scss").read().split("\n")
    fork = "\n".join(lines[24:]).rstrip("\n")   # 25 行目以降＝テーマブロック
    open(f"app/javascript/styles/{name}.scss","w").write(base + "\n" + fork + "\n")
```

対象は `bshockdon`: bshock / `curesta`: cure-lime, cure-orange /
`delmulin`: dai, daidai-orange, hyunckel, leona, maam, popp。
`config/themes.yml` の登録と一致していることも確認する。

⚠ 4.7 では併せて `@use 'mastodon/theme/economy'` → `@use 'mastodon/tokens/theme/economy'` の
パス修正が必要だった。`grep -n "mastodon/theme" app/javascript/styles/*.scss` が 0 件になること。

#### タグセットドロップダウンのミラー（#905）

[tagset_dropdown.tsx](../app/javascript/mastodon/features/compose/components/tagset_dropdown.tsx) は
upstream の `language_dropdown.tsx` の薄い並行実装。**版上げのたびに language_dropdown の差分を
そのまま当てる**:

```bash
git diff <前タグ> <新タグ> -- app/javascript/mastodon/features/compose/components/language_dropdown.tsx
```

4.7 では react-overlays → `components/popover`（floating-ui）への移行がここに該当した
（`Overlay`→`Popover`、`useRef`→`useState` の参照渡し、`placement` state の撤去）。

#### 用語ポリシーの再適用

```bash
# 大文字化を採用しない（#906）— 全ブランチ
grep -rE 'text-transform:\s*(uppercase|capitalize)' app/javascript

# 廃止用語「トゥート」の排除 — 全ブランチ
grep -rn 'トゥート' config/locales app/javascript/mastodon/locales

# 投稿→キュア！ / ブースト→リキュア！ — curesta のみ
grep -rn '投稿\|ブースト' config/locales/*ja*.yml app/javascript/mastodon/locales/ja.json
```

いずれも**ヒット 0 件**が正常。⚠ **RC では ja 翻訳が更新されていないことが多く、置換対象が
現れないことがある**（4.7.0-rc.1 がそうだった）。**stable で Crowdin の ja が入った時点で
必ず再チェックする。**

### 5. 検証

```bash
bundle install && yarn install --immutable
bundle exec rubocop                 # offense 0 が正常
yarn build:production               # フォーク独自ファイルの破損はここでしか出ない
bundle exec rspec spec/fork         # ⚠ PostgreSQL 必須
```

ビルド後、テーマが実際に効いているかを生成 CSS で確認する（後勝ちの上書きなので**最後の値**を見る）:

```bash
grep -o '\-\-color-grey-100:[^;]*' public/packs/assets/themes/<テーマ>-*.css | tail -1
```

default テーマと同じ値なら適用されていない。

### 6. CI

上流の CI ワークフローは**すべて削除**し、[.github/workflows/fork-ci.yml](../.github/workflows/fork-ci.yml)
一本に置き換えている。回るのは **spec/fork（PostgreSQL 込み）** と、**変更ファイルに限定した**
ESLint / stylelint / RuboCop。手元で spec/fork を回せなくても CI が拾う。

通しのアセットビルドは重いので毎 push には載せず、[fork-assets-nightly.yml](../.github/workflows/fork-assets-nightly.yml)
に分離している（#912）。本番と同じコマンド（`RAILS_ENV=production` ＋ Node のヒープ指定）で
`assets:precompile` を回し、**manifest が参照するファイルの実在**と **`config/themes.yml` の
全テーマの CSS 生成**まで確認する。既定はインスタンス 3 本の nightly。

⚠ **schedule / workflow_dispatch はデフォルトブランチ（bshockdon）の定義しか起動できない。**
RC 期間に `merge/**` を検査したいときは、手動実行の `ref` にブランチ名を渡す（定義は bshockdon の
ものが使われ、チェックアウト先だけが変わる）。**版を本番へ適用する前に一度回しておく。**

⚠ **push トリガーはブランチ名で絞っている**（`merge/**` / `stable/**` / 3 つのインスタンスブランチ）。
**作業ブランチの命名規則を変えたらここも直す。**4.7 の追従では `work/4.6/**` のまま残っていたため、
`merge/4.7/*` への push で CI が一度も走らなかった。

⚠ **`merge/**` が緑でも instance ブランチへ戻した push で落ちることがある。**Tier 1/2 は
**変更ファイルに限定**して lint するため、**比較の基点が変わると検査対象も変わる**。
2026-08-21 の 4.7.0 では、`merge/4.7/*` では対象外だった `styles/mastodon/tokens/theme/_economy.scss`
が curesta / delmulin の instance ブランチ側で対象に入り、**#907 で書いた解説ブロックの空コメント
2 行**（`scss/comment-no-empty`）で落ちた。**版上げの検証は instance ブランチへ戻した後の CI まで見る。**

### 7. 後始末（6 台への適用が終わってから）

**版上げは 6 台へ適用して終わりではない。**次の 3 つまでが 1 セット:

```bash
# 1. リリースタグ。命名は v<上流版>-<インスタンス> の軽量タグ（例 v4.7.0-curesta）
for i in bshockdon curesta delmulin; do git tag "v<版>-$i" "origin/$i"; done
git push origin v<版>-bshockdon v<版>-curesta v<版>-delmulin

# 2. 切り戻し先のスナップショット。⚠ 本番へ実際に適用したコミットに置く
git branch stable/<版>/<インスタンス> <適用したコミット>

# 3. 作業ブランチの削除。instance / stable の祖先であることを確かめてから
git merge-base --is-ancestor origin/merge/<版>/<i> origin/<i> && git push origin --delete merge/<版>/<i>
```

⚠ **タグと `stable/<版>/*` は必ずしも同じコミットにならない。**タグは「その版としてのフォークの
到達点」なので **instance ブランチの先端**に、`stable/<版>/*` は「本番が走っているコミット」なので
**適用したコミット**に置く（4.7.0 では版上げ後に足した docs コミット 1 本ぶんずれた）。

⚠ **DB のスナップショットは残置する。**マイグレーションがある版では適用前に
`<dataset>@pre-mastodon-<版>` を取る（→ chubo2 infra-note）。**数日運用して問題が無ければ削除する**
のは運用者の判断。

## フォーク改変の防衛線: spec/fork

[spec/fork/fork_customizations_spec.rb](../spec/fork/fork_customizations_spec.rb) が、マージ衝突解決で
静かに巻き戻ると**ユーザー影響が出る**改変をガードしている（#909）。merge ドライバは採用しない。

| 対象 | フォーク値 | upstream 既定 |
| --- | --- | --- |
| `Account::DEFAULT_FIELDS_SIZE` | 10 | 4 |
| `Account::DISPLAY_NAME_LENGTH_LIMIT` | 60 | 40 |
| `Account::NOTE_LENGTH_LIMIT` | 3000 | 500 |
| `TagFeed::LIMIT_PER_MODE` | 100 | 4 |
| `PollOptionsValidator::MAX_OPTIONS` | 10 | 4 |
| `StatusLengthValidator::MAX_CHARS` | ENV 既定 3000 | 500 |

加えて挙動の巻き戻りを静的に検知するガードがある:

- **アナモルフィック動画の SAR 対応（#923）** — `VideoMetadataExtractor#parse_sar` / `display_width`
- **streaming のローカル TL → DEFAULT_TAG 読み替え（#925）** — `streaming/index.js`
- **受信スパムフィルタ（荒らし共栄圏対策）** — `like_a_spam?` の条件・rollback・ログ出力
- **ハッシュタグ列のタグ数上限（WebUI 側）** — サーバー側 `TagFeed::LIMIT_PER_MODE` との一致まで確認
- **Misskey 絵文字同期（delmulin のみ）** — `spec/fork/misskey_emoji_sync_spec.rb`
- **Material Symbols（Google Fonts）の参照（#954）** — CSP の**実効ポリシー**（`style-src` / `font-src`）と
  レイアウトの stylesheet link。ソース文字列ではなく組み上がったポリシーを見るのは、4.7 のように
  initializer の構造ごと変わっても検知するため（development ブロックにだけ残った場合も落とす）

⚠ **spec/fork は PostgreSQL が要る。** 手元で DB を上げられないときは上表の定数を `grep` で
確認しておけば巻き戻りの大半は捕まる（本走は Fork CI が回す）。

**ガードを足す判断基準は「消えても平常時は誰も困らないか」。**困らないものほど危ない。休眠中の
防御（スパムフィルタ）や、サーバー・WebUI で対になっている値は、落ちても平常運転では誰も気づかず、
必要になった瞬間に初めて効いていないと分かる。

## フォーク改変カタログ

**何を守り、何を上流に寄せてよいかの判断表。**マージ衝突で迷ったらここを見る。
2026-08-15 に全改変を運用者と突き合わせて確定した。

### 全ブランチ共通

| 改変 | 目的 | 扱い |
| --- | --- | --- |
| 上限値の拡張（投稿3000字・表示名60・bio 3000・補足情報10・投票10択・タグ列100） | 運用方針 | **守る**（spec/fork がガード） |
| 受信スパムフィルタ `like_a_spam?`（[create.rb](../app/lib/activitypub/activity/create.rb)） | 2024/2 の「荒らし共栄圏」を名乗る集団によるスパム大量送信への対抗。**実効があった防御を、再燃に備えて休眠状態で残している** | **守る**（同上） |
| アナモルフィック動画の SAR 対応（#923） | サムネ・プレーヤー枠の縦伸び修正 | **守る**（同上） |
| Rack::Attack の safelist（localhost / `MY_NETWORKS`） | **モロヘイヤが同一ホストから叩くため。**本体のレートリミットに引っかからないようにする意図的な緩和 | **守る** |
| プール既定値 20（puma / sidekiq / DB / Redis / streaming） | 性能調整。**5 系統すべて 20 で揃える**（かつて puma と Redis だけ 40 でずれていた）。⚠ `.env.production` に `MAX_THREADS` が無い環境では**この既定値がそのまま効く**（dev25 の puma 起動ログが `Max threads: 20` で確認済み） | 守る。ずれを見たら揃える |
| スタートメニューの Ajax 拡張（[navigation_panel](../app/javascript/mastodon/features/navigation_panel/index.tsx)） | `/links.json` を読んでメニュー項目を足す | **守る** |
| Google Fonts（Material Symbols、[application.html.haml](../app/views/layouts/application.html.haml)） | 上記メニューのアイコン。`links.json` の `icon` はリガチャ名で、**このフォントが無いと文字列がそのまま出る**。⚠ **症状は WebUI にしか出ない**ため、クライアント経由の利用者にも管理者にも見えない | **守る**（CSP のフォントホスト追加とセット。spec/fork がガード #954） |
| 「タグ付け」メニュー・タグセット・エピソードブラウザ導線 | モロヘイヤ連携（→ 前節） | **守る** |
| 管理画面のソフトウェア一覧にモロヘイヤの版を追加 | 運用の見通し | 守る |
| 公開範囲ボタンから引用ポリシー併記を削除（[visibility_button.tsx](../app/javascript/mastodon/features/compose/components/visibility_button.tsx)） | 4.7 で上流が併記を追加したが、**隣にタグセットが並ぶため 1 行に収まらなくなる**。モーダルを開けば確認できる情報なので落とした | **条件付き**。1 行に収まるなら上流に戻してよい |

### インスタンス固有

| ブランチ | 改変 |
| --- | --- |
| curesta | ja 用語置換（→ 前節）・独自テーマ 2 種・`dist/servers/` 4 本（precure.ml / blog / feed / rubicure / cure-api） |
| delmulin | 独自テーマ 6 種・Misskey 絵文字同期（`app/lib/misskey_emoji_sync.rb` + `tootctl emoji sync`）・`dist/servers/mstdn.delmulin.com.conf` |
| curesta / delmulin 共通 | ローカル TL の呼称を「コミュニティ」に（デフォルトタグ＋リレーで姉妹サーバーとタグ TL を共有しているため）。`firehose.local` はソースの `defaultMessage` も変更、`column.firehose_local` / `navigation_bar.live_feed_local` は**ロケールのみ**変更 |

⚠ **`yarn i18n:extract` を手で実行すると `column.firehose_local` の en が上流表現に戻る**
（`defaultMessage` を変えていないため）。上流の check-i18n ワークフローは削除済みで CI では走らない。

### 上流に寄せてよい / 既に不要になったもの

**改変は放っておくと腐る。**2026-08-15 の棚卸しで以下を削除した。同種のものを見つけたら同様に落とす。

| 落としたもの | 理由 |
| --- | --- |
| `app/workers/concerns/bulk_mailer.rb` | 上流が `bulk_mailing_concern.rb` にリネームした際のマージ事故。参照ゼロの死んだコードだった |
| `linked_data_signature.rb` の e-komik.org 回避策 | 2025-02 の応急処置。相手サーバーが ActivityPub 実装ごと消滅し、本番 3 台とも保存済み投稿 0 件 |
| `material-icons/400-24px/{leaf,audio}.svg` | leaf はアイコンを Material Symbols に移行して以降の未使用素材、audio は上流削除分の残骸 |
| README の「WebUI の画像リサイズ処理をキャンセル」 | 上流が #23726 でクライアント側リサイズを機能ごと廃止し、該当改変が自然消滅していた |

## モロヘイヤ（mulukhiya-toot-proxy）との連携

モロヘイヤの設計方針は「**本体改造の最小化**」——プロキシ層でふるまいを足し、Mastodon 本体への
パッチを減らすこと。**このフォークに機能を足す前に「モロヘイヤ側でできないか」を先に問う。**
逆に、モロヘイヤが SNS の DB へ書き込むことになる場合は本体改造（＝このフォーク）を採る。
判断基準の正本はモロヘイヤ側 [docs/CLAUDE.md](https://github.com/pooza/mulukhiya-toot-proxy/blob/main/docs/CLAUDE.md)。

### 接続の構造

- モロヘイヤの Puma は **3008**、Mastodon Web は 3000、streaming は 4000
- 振り分けは **nginx が担う**（`dist/servers/*.conf`）。`X-Mulukhiya` ヘッダの有無で
  `$mulukhiya_backend` と Mastodon 本体を切り替え、`/mulukhiya` 配下はモロヘイヤへ直送
- ⚠ 本番 3 台では `/usr/local/etc/nginx/servers/*.conf` が**リポジトリへのシンボリックリンク**。
  `dist/servers/*.conf` を変更した版では `nginx -t` + reload が要る（ステージングは実ファイル）

### このフォークが持つモロヘイヤ依存

| 箇所 | 内容 |
| --- | --- |
| [tagset_dropdown.tsx](../app/javascript/mastodon/features/compose/components/tagset_dropdown.tsx) | `/mulukhiya/api/program` から番組表を取得して実況タグセットを構成 |
| [reducers/compose.js](../app/javascript/mastodon/reducers/compose.js) | タグセット適用・`/mulukhiya/app/episode`（エピソードブラウザ）起動 |
| status action bar | 「タグ付け」メニュー → `/mulukhiya/app/status/<id>` を別窓で開く |
| [navigation_panel](../app/javascript/mastodon/features/navigation_panel/index.tsx) | モロヘイヤへの導線 |
| [software_versions_dimension.rb](../app/lib/admin/metrics/dimension/software_versions_dimension.rb) | 管理画面のソフトウェア一覧に `/mulukhiya/api/about` の版を追加 |
| streaming の DEFAULT_TAG 読み替え（#925） | ローカル TL を DEFAULT_TAG のハッシュタグストリームへ。REST 側は nginx の 302 |

### ⚠ 番組表を読むクライアントは 3 つある

`/mulukhiya/api/program`（番組表）を読んで実況タグセットの選択肢を組み立てているのは、
**モロヘイヤを共通のバックエンドに持つ 3 つのフロントエンド**。⚠ **このフォークはそのうちの 1 つに
過ぎない。**

| クライアント | 実装 | 備考 |
| --- | --- | --- |
| [pooza/capsicum](https://github.com/pooza/capsicum) | `compose_screen.dart` の `_programSublabel`、書式は `program_schedule_display.dart` | ⚠ **先行して入ることが多い** |
| このフォーク | [tagset_dropdown.tsx](../app/javascript/mastodon/features/compose/components/tagset_dropdown.tsx)、書式は [program_schedule.ts](../app/javascript/mastodon/features/compose/util/program_schedule.ts) | |
| [pooza/misskey](https://github.com/pooza/misskey)（`daisskey`） | `WidgetTagset.vue`、書式は `utility/program-schedule.ts` | |

⚠⚠ **番組表の見せ方を変えるときは 3 つ揃える。**利用者は同じ番組表を複数のクライアントで見比べる
ので、**書式が割れると「どれが今日の枠か」を突き合わせられなくなる**。⚠ **capsicum が先に入るのが
通例**なので、後続 2 つは **capsicum の表示に合わせる**（#953 / `pooza/misskey#419` はこの順で揃えた）。

- **期待値を共有する。** 3 者のテストは同じケースを持つ（capsicum の
  `program_schedule_display_test.dart` が起点）。⚠ **片方だけ直すと、テストが揃っていても
  «揃っている» ことの担保にならない**
- ⚠ **API 側（モロヘイヤ）の変更は要らないことが多い。** `next_on` / `start_time` は既に返っており、
  レスポンスは放送順（`next_on` 昇順 → `start_time` 昇順）で並ぶ。⚠⚠ **足りないのは表示だけ、という
  切り分けを先にやる**（本節冒頭の「モロヘイヤ側でできないか」を先に問う、の裏返し）
- ⚠ **表示ラベルとタグセットの値を混ぜない。** 投稿に載るタグ（`changeTagset` に渡す値）は
  番組表の表示ラベルとは別物。日付を表示に足しても、タグ側には入れない
- ⚠⚠ **既に食い違っている箇所がある。** `air` の表示条件は、このフォークが `entry.air` なら無条件、
  Misskey 版は `livecure` が真のときだけ。**揃えるかどうかは未判断**

### デフォルトハッシュタグとコミュニティ

- タグの**付与**はモロヘイヤ（`DefaultTagHandler`）、**読み取り経路**（ローカル TL・streaming・検索）は
  このフォークと `pooza/misskey` の `daisskey` ブランチが担う
- 同じデフォルトタグ＋同一リレー（`deas.b-shock.co.jp`）で結ばれたサーバーを「姉妹サーバー」と呼ぶ。
  デルムリン丼 ↔ ダイスキー、キュアスタ！ ↔ 外部管理のダイスキー
- インスタンス別のタグ: キュアスタ！ = `#precure_fun` / デルムリン丼 = `#delmulin`
- ⚠ **この機能は misskey-dev へ PR 済みで却下されている。upstream への再提案はしない**
  （理由はモロヘイヤ側 docs を参照）。範囲拡張の議論は #908

### 注意

- **media_catalog は既定 OFF**（モロヘイヤ 5.23.0〜）。本番 Mastodon で重 SQL とプール枯渇を
  起こしたため。この機能を前提にした実装を入れない
- Mastodon は `metadata.maintainer` を返さない（フォークも同様）。モロヘイヤ側で
  `maintainer_name` が nil なのは仕様

## FreeBSD 向けの調整

### rc.d スクリプト（`dist/freebsd/`）

| スクリプト | サービス | プロセス |
| --- | --- | --- |
| `mastodon-web` | Puma Web サーバー | `rails server -u puma` |
| `mastodon-sidekiq` | Sidekiq ワーカー | `sidekiq -C config/sidekiq.yml` |
| `mastodon-streaming` | Node.js Streaming API | `npm start` |

```sh
daemon -f -S -T <syslogタグ> -u $mastodon_user /usr/local/bin/bash -lc "cd $mastodon_path && <コマンド>"
```

- `daemon(8)` で正式にデーモン化する（`-f` stdio を /dev/null へ、`-S -T` syslog 出力）。
  旧方式の `zsh -c '... | logger &'` は OS 起動時にブロックする問題があり、#900 で置き換えた
- `/usr/local/bin/bash -lc` は必須。`.bash_profile` 経由で rbenv を初期化するため
  （mastodon ユーザーのログインシェルは zsh だが、rc.d からは bash を明示的に呼ぶ）

rc.d スクリプトは **chubo の cookbook 管理外**。リポジトリから手で install する:

```bash
ssh <host> 'sudo install -o root -g wheel -m 755 \
  ~mastodon/repos/mastodon/dist/freebsd/mastodon-web /usr/local/etc/rc.d/mastodon-web'
```

配布物と実機が乖離しやすいので、**アップグレードのついでに 3 本とも diff を取る**こと。
⚠ 起動方式ごと変える差し替えでは **「旧で止める → 入れ替える → 新で起動する」**の順で行う。

### Ubuntu 前提箇所について

upstream は Ubuntu を唯一のサポート対象と匂わせているが、アプリケーションコード自体は OS 非依存。
FreeBSD 対応に必要なのは rc.d スクリプトと環境設定のみ。

## サーバーとデプロイ

**正本は [chubo2 の infra-note.md](https://github.com/pooza/chubo2/blob/main/docs/infra-note.md)。**
「Mastodon 本体のアップグレード（FreeBSD 6 台）」節に、対象 6 台・必要工程の見極め方・
`assets:precompile` のヒープ指定・ヘルスチェック・ログの読み方・平常運転のノイズまで揃っている。

このドキュメントで押さえておくべき最小限:

- 対象は **本番 3 台（shallu / zugoga / gomander）＋ ステージング 3 台（dev24 / dev25 / dev26）**
- 着地ユーザーは 6 台とも `mastodon`、リポジトリは **`~mastodon/repos/mastodon`**
- SSH は本番が `<host>.b-shock.co.jp`（デフォルト mastodon 着地）、ステージングは
  `mastodon@devNN`（インフラ操作で sudo が要るときは `pooza@devNN`）
- サービス再起動は **`< /dev/null > /dev/null 2>&1` を必ず付ける**（daemon が SSH の stdout を
  握って ssh が抜けなくなる）。本番は monit があるので停止 → 再起動 → 再開で挟む
- `/api/v2/instance` の `version` は再起動直後 1〜2 分は旧版のまま出る（Redis キャッシュ）。異常ではない

⚠ 旧ステージング（drime + dev04 / dev15 / dev22 / dev23）と旧キュアスタ！本番（lbock）は
**退役済み**。`devNN_mastodon` のような SSH エイリアスも廃止されている。

### RC 期間のステージング適用（`merge/**` への切り替え）

RC を載せるときは、各台のチェックアウト先を instance ブランチから `merge/<版>/<インスタンス>` に
切り替える。stable が出たら instance ブランチへ戻す。2026-08-15 の 4.7.0-rc.1 適用で踏んだ罠:

**stable 当日の流れ**（2026-08-21 の 4.7.0 で実施）: upstream タグを `merge/<版>/bshockdon` へ
マージ → 派生 2 本へ流す → **instance ブランチを `merge/<版>/*` へ fast-forward** → push・CI →
ステージング 3 台のチェックアウト先を instance ブランチへ戻して適用 → 本番 3 台。
⚠ **RC 期間に instance ブランチ側だけへ入った commit（4.7 では #912）は merge ブランチに無い。**
先に `git merge origin/<instance>` して merge ブランチを上位集合にしてからでないと、
instance ブランチへ戻すときに fast-forward できない。

⚠ **fetch の refspec が絞られている台がある。**dev25 / dev26 は single-branch clone の名残で
`+refs/heads/bshockdon:refs/remotes/origin/bshockdon` になっており、**`merge/4.7/*` を fetch できず
チェックアウトが失敗した**。切り替え前に確認し、必要なら広げる:

```bash
git config --get-all remote.origin.fetch          # 確認
git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'   # 広げる
git rev-parse --verify origin/<branch>            # ref があることを確かめてから checkout
```

⚠ **手順を自動化するとき、`git checkout` の出力をパイプに通さない。**`set -e` はパイプ末尾の
終了コードしか見ないため、`git checkout ... | tail -1` と書くと**切り替え失敗を素通りして
bundle / migrate / assets まで走る**。「適用したつもりで旧版のまま、アセットだけ再生成」という
最悪の状態になりうる。切り替え後は必ず検証する:

```bash
test "$(git rev-parse --abbrev-ref HEAD)" = "$BR"
```

⚠ **再起動後のヘルスチェックは固定待ちにしない。**puma の停止に 23 秒・起動完了まで計 47 秒
かかった実測があり、`sleep 30` では**起動途中に当たって誤った赤が出る**。200 が返るまで待つ:

```bash
until [ "$(curl -s -o /dev/null -w '%{http_code}' https://<staging-domain>/health)" = "200" ]; do sleep 10; done
```

**適用の成否は、デプロイ手順の外から独立に検証する。**スクリプトが最後まで走ったことは根拠に
ならない（上記の握り潰しがあるため）:

```bash
git rev-parse --abbrev-ref HEAD                              # 意図したブランチか
RAILS_ENV=production bundle exec rails db:abort_if_pending_migrations
stat -f %Sm public/packs/.vite/manifest.json                 # アセットが今回のものか
curl -s https://<domain>/api/v2/instance | jq -r .version    # 外形（Redis キャッシュで 1〜2 分遅れる）
```

⚠ **アセットの到達性も外から確かめる（#954）。**バックエンドが生きていれば API も
`/api/v2/instance` も通るので、**上の 4 本は全部緑のまま WebUI だけ崩れる**。4.6 以降のフロントは
Vite のハッシュ付きチャンクなので、manifest とファイルがずれると「一部の CSS だけ 404」になる。
普段 WebUI を使わないと気づけないため、機械的に引く:

```bash
# トップの HTML が参照する CSS を全部引き、200 かつ text/css であること
curl -s https://<domain>/ \
  | grep -o '/packs/[^"]*\.css' | sort -u \
  | while read -r path; do
      curl -s -o /dev/null -w "%{http_code} %{content_type} $path\n" "https://<domain>$path"
    done
```

全台で**同一の manifest** であることも見る。LB 分散で HTML と CSS が別ビルドの台に当たると、
1 台だけ取りこぼしていても引き方によっては緑に見える:

```bash
# 各台で実行し、ハッシュが揃うこと
md5 -q public/packs/.vite/manifest.json
```

Material Symbols（スタートメニューのアイコン）は `fonts.googleapis.com` のスタイルシート頼みで、
CSP のホスト指定が版上げで落ちると**アイコンの代わりに `home` などの文字列がそのまま出る**。
静的な取りこぼしは `spec/fork/` のガードで拾うが、適用後は外形でも見る。

⚠ **HTML に link が出ていることだけで CSP を判断しない。**link は
`application.html.haml` に無条件で書かれているので、**CSP が落ちていても必ず出る**。
ブラウザは CSP で弾いて文字列を表示するのに、`grep` は緑になる。
`spec/fork/` のガードもチェックアウトした Rails 設定を見るだけで、実際に配信されている
ヘッダは見ていない。**レスポンスの CSP ヘッダを直接見る**こと:

```bash
csp=$(curl -sI https://<domain>/ | grep -i '^content-security-policy:' | tr ';' '\n')
echo "$csp" | grep -qE '^ *style-src .*https://fonts\.googleapis\.com' \
  && echo 'style-src OK' || echo 'style-src NG'
echo "$csp" | grep -qE '^ *font-src .*https://fonts\.gstatic\.com' \
  && echo 'font-src OK' || echo 'font-src NG'
```

`style-src`（スタイルシート）と `font-src`（フォント本体）は**別のホスト**なので、
両方見ないと片方だけ落ちた状態を見逃す。

## ローカル開発環境

- `bundle exec rubocop` は **`bundle install` 済みでないと動かない**。上流の版上げで Gemfile.lock が
  進むと必ず失敗するので、マージ直後は入れ直す
- `rspec` は **PostgreSQL 必須**。DB が無い環境では `ruby -c` と静的 grep で代替する
- アセットは `yarn build:production`。フォーク独自ファイルの破損はここでしか顕在化しない

## 情報の記載先ルール

chubo2 の [doc-maintenance.md](https://github.com/pooza/chubo2/blob/main/docs/doc-maintenance.md) に揃える。
**二重管理をしない**のが第一原則。

| 内容 | 置き場 |
| --- | --- |
| 未了の作業・課題 | GitHub Issue（`pooza/mastodon`。インフラ面は `pooza/chubo2`） |
| フォーク開発の知見（追従手順・独自改変・モロヘイヤ連携） | **この docs/CLAUDE.md** |
| インフラの現況・手順・再発する罠 | [chubo2 docs/infra-note.md](https://github.com/pooza/chubo2/blob/main/docs/infra-note.md) |
| 日付のある出来事の記録 | [chubo2 docs/infra-history.md](https://github.com/pooza/chubo2/blob/main/docs/infra-history.md) |
| モロヘイヤの設計方針・リリース運用 | [mulukhiya-toot-proxy docs/CLAUDE.md](https://github.com/pooza/mulukhiya-toot-proxy/blob/main/docs/CLAUDE.md) |
| セッションメモリ | 正本へのポインタと「なぜ非自明か」だけ。現況は書かない |

## 関連リポジトリ

- [pooza/mulukhiya-toot-proxy](https://github.com/pooza/mulukhiya-toot-proxy) — 併用プロキシ（モロヘイヤ）
- [pooza/chubo2](https://github.com/pooza/chubo2) — インフラ情報・itamae レシピ（プライベート）
- [pooza/misskey](https://github.com/pooza/misskey) — ダイスキー用フォーク（`daisskey` ブランチ）
- [pooza/capsicum](https://github.com/pooza/capsicum) — モロヘイヤ対応のクライアントアプリ（→「番組表を読むクライアントは 3 つある」）
- [mastodon/mastodon](https://github.com/mastodon/mastodon) — upstream

## gh CLI 使用時の注意

フォークリポジトリでは `gh` が upstream（mastodon/mastodon）をデフォルトで参照することがある。
Issue 操作や PR 作成時は **`-R pooza/mastodon` を明示**すること。PR の base も対象ブランチを明示する。
