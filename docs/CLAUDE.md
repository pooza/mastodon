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

⚠⚠ **正本は Claude Code のスキル（#972）。** 手順を足すときは**スキルの側だけ**を直し、ここからはリンクする。**二重に持たない。**（横断の取り決めは [ginseng-style docs/skills.md](https://github.com/pooza/ginseng-style/blob/main/docs/skills.md)）

| スキル | 起動 | 中身 |
| --- | --- | --- |
| [upstream-merge](../.claude/skills/upstream-merge/SKILL.md) | 明示のみ | 版上げ一式。SAME/FORK トリアージ → 取りこぼし検査 → 版ごとの定例作業（テーマ再同期・タグセットのミラー・用語ポリシー）→ 検証 → CI → 後始末 |
| [release-verify](../.claude/skills/release-verify/SKILL.md) | 自動 | 6 台へ適用したあとの外形確認。ブランチ・マイグレーション・アセット到達性（#954）・CSP 実効ヘッダ・テーマ CSS の後勝ち |
| [staging-rc](../.claude/skills/staging-rc/SKILL.md) | 明示のみ | RC 期間のステージング適用（`merge/**` への切り替えと戻し） |

起動の線引きは **「外へ書く step が 1 つでもあれば明示のみ」**。`release-verify` は curl と grep だけで終わるので自動でよい。

⚠ スキルは `.claude/skills/` に置き、**3 ブランチで中身を同一に保つ**（共有する改変は bshockdon 側の構造で提供して派生へ流す、という既存の原則をスキルにも当てる）。インスタンスごとの違いは `config/themes.yml` の登録テーマから判定してファイルを分岐させない。`.gitignore` は `.claude/*` を落としつつ `!.claude/skills/` で skills だけ追跡している。


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
- **用語ポリシー（#972）** — [spec/fork/terminology_guard_spec.rb](../spec/fork/terminology_guard_spec.rb)。
  廃止用語「トゥート」が ja の翻訳に残っていないこと（全ブランチ）と、「投稿」→キュア！ /
  「ブースト」→リキュア！ の置換が生きていること（curesta のみ。`config/themes.yml` の登録テーマで判定）。
  ⚠ **上流の版上げで Crowdin の ja が入れ替わると静かに戻る**ので、手で直すのは
  [upstream-merge スキル](../.claude/skills/upstream-merge/SKILL.md)、落とすのはここ、という分担。
  大文字化の禁止（#906）は CSS 側の規則なので stylelint が見る

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

### ⚠ capsicum にバニラ Mastodon 以上を求めない

[pooza/capsicum](https://github.com/pooza/capsicum) は**このフォークの Mastodon クライアント**でもある
（モロヘイヤ対応のクライアントアプリ）。⚠⚠ **だが capsicum に求めるのは「バニラの Mastodon として
喋れること」までで、それ以上ではない。**

🔴 **フォーク固有の差分はクライアントではなくモロヘイヤ側に寄せる。**本節冒頭の「本体改造の
最小化」と同じ判断軸で、**寄せ先がプロキシ層**なのも同じ。

- ⚠ **このフォーク独自の API・独自の挙動を前提にした機能を、capsicum 側に要求しない。**
  要求した時点で「バニラの Mastodon クライアント」ではなくなり、フォークの改変がクライアントにも
  複製される
- ⚠ 逆向きも同じで、**capsicum に何か要るとなったら、まずモロヘイヤ側で提供できないかを問う**
- ⚠⚠ **番組表まわりは例外ではない。**下記 3 クライアントが読んでいるのは
  `/mulukhiya/api/program` ＝ **モロヘイヤの API** であって、このフォークの API ではない

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
- ⚠ **`air` は「揃えるかどうか」ではなく、ダイスキー側の実装漏れ。**⚠⚠ **このフォークの変更は不要**
  （`pooza/misskey#424` で対応）。⚠ **クライアントごとの好みではなく仕様で決まっている**ので、
  「どちらへ揃えるか」を議論の対象にしない:

  - モロヘイヤ [docs/api.md](https://github.com/pooza/mulukhiya-toot-proxy/blob/main/docs/api.md) —
    「`air` … エア番組（実在しない／TV 放送のない番組）フラグ。**`true` で「エア番組」タグが付与される**」
  - capsicum `compose_screen.dart` のコメント — 「air フラグ … は**独立した軸**」

  3 クライアント × 2 軸の実測（2026-08-31）。⚠⚠ **6 セル中、ダイスキーの表示ラベルだけが例外**:

  | クライアント | 表示ラベル | 投稿に載るタグ |
  | --- | --- | --- |
  | capsicum | `air` 無条件（`compose_screen.dart:4713`） | `air` 無条件（同 `:2451`） |
  | このフォーク | `air` 無条件（[tagset_dropdown.tsx:107](../app/javascript/mastodon/features/compose/components/tagset_dropdown.tsx)） | `air` 無条件（[compose.js:437](../app/javascript/mastodon/reducers/compose.js)） |
  | ダイスキー | 🔴 **`livecure` が真のときだけ**（`WidgetTagset.vue:106-109`） | `air` 無条件（同 `:186`） |

  ⚠ **ダイスキーは内部でも食い違っている。**`air: true, livecure: false` の枠では
  **ラベルに「エア番組」が出ないのに `user_tags` には入る**。確認ダイアログはラベルを再利用する
  ので、**利用者が見た文字列と実際に送られるタグが一致しない**。⚠⚠ **ダイスキーのラベルを
  無条件へ直す 1 箇所で、クライアント間の差と内部の食い違いが同時に解消する**

- ⚠⚠ **2 軸（表示ラベル / 投稿に載るタグ）で見る癖をつける。**上の `air` は、①クライアント間だけを
  見ていると「どちらへ揃えるか」の好みの問題に見え、②内部の食い違いに気づけない。
  🔴 **逆向き（`air` を `livecure` 従属に揃える）を選ぶと、2 リポジトリ 3 箇所の変更になる**
  ——直す前に、どちらの向きが何箇所に波及するかを数えること

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

→ [staging-rc スキル](../.claude/skills/staging-rc/SKILL.md)。refspec が絞られている台の確認、`git checkout` をパイプに通さない理由、health の 200 待ち、stable 当日に instance ブランチへ戻す流れ。

🔴 **dev25 = キュアスタ！ / dev26 = デルムリン丼。**ドメイン名の見た目と機番の対応が逆なので取り違えやすい（正本は chubo2 [noah.yaml](https://github.com/pooza/chubo2/blob/main/config/node/noah.yaml) の `proxies`）。

### 適用後の検証

→ [release-verify スキル](../.claude/skills/release-verify/SKILL.md)。**デプロイ手順の外から独立に確かめる**（スクリプトが最後まで走ったことは根拠にならない）。⚠ アセット到達性（#954）と CSP 実効ヘッダは、**API が全部緑のまま WebUI だけ崩れる**経路なので機械的に引く。


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
| フォーク開発の知見（独自改変・モロヘイヤ連携・FreeBSD 向けの調整） | **この docs/CLAUDE.md** |
| 名前のついた手順（版上げ・適用後の検証・RC 期間のステージング適用） | **`.claude/skills/`**（#972）。docs はポインタ |
| リポジトリ横断の作法（Codex レビューの処理など） | [ginseng-style](https://github.com/pooza/ginseng-style) のプラグイン。こちらで作らない |
| インフラの現況・手順・再発する罠 | [chubo2 docs/infra-note.md](https://github.com/pooza/chubo2/blob/main/docs/infra-note.md) |
| 日付のある出来事の記録 | [chubo2 docs/infra-history.md](https://github.com/pooza/chubo2/blob/main/docs/infra-history.md) |
| モロヘイヤの設計方針・リリース運用 | [mulukhiya-toot-proxy docs/CLAUDE.md](https://github.com/pooza/mulukhiya-toot-proxy/blob/main/docs/CLAUDE.md) |
| セッションメモリ | 正本へのポインタと「なぜ非自明か」だけ。現況は書かない |

## 横断の作法は ginseng-style のプラグインで

リポジトリをまたぐ作法は [ginseng-style](https://github.com/pooza/ginseng-style) の Claude Code
プラグインが正本。**このフォークで作り直さない。**

- **Codex（自動レビュー）の指摘の処理** → `/ginseng:codex-review`
  （[SKILL.md](https://github.com/pooza/ginseng-style/blob/main/plugins/ginseng/skills/codex-review/SKILL.md)）
- 入れ方: `/plugin marketplace add pooza/ginseng-style` → `/plugin install ginseng@ginseng-style`。
  ⚠ **マシンごとに 1 回ずつ手で入れる**（外部ソースのプラグインは自動では入らない）

⚠ **このフォーク固有の手順は `.claude/skills/`**（#972）。横断の作法ではないのでプラグインへ上げない。

## 関連リポジトリ

- [pooza/mulukhiya-toot-proxy](https://github.com/pooza/mulukhiya-toot-proxy) — 併用プロキシ（モロヘイヤ）
- [pooza/chubo2](https://github.com/pooza/chubo2) — インフラ情報・itamae レシピ（プライベート）
- [pooza/misskey](https://github.com/pooza/misskey) — ダイスキー用フォーク（`daisskey` ブランチ）
- [pooza/capsicum](https://github.com/pooza/capsicum) — モロヘイヤ対応のクライアントアプリ。⚠ **このフォークのクライアントでもあるが、バニラ Mastodon 以上は求めない**（→「capsicum にバニラ Mastodon 以上を求めない」）
- [mastodon/mastodon](https://github.com/mastodon/mastodon) — upstream

## gh CLI 使用時の注意

フォークリポジトリでは `gh` が upstream（mastodon/mastodon）をデフォルトで参照することがある。
Issue 操作や PR 作成時は **`-R pooza/mastodon` を明示**すること。PR の base も対象ブランチを明示する。
