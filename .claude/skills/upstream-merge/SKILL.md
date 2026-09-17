---
name: upstream-merge
description: pooza/mastodon を upstream の新しい版へ追従させる。衝突の SAME/FORK トリアージ、取りこぼし検査、テーマ・タグセット・用語の定例作業、検証、6 台適用後の後始末まで。「4.7.2 が出ました」のように上流の版が出たときに呼ぶ。
disable-model-invocation: true
---

# upstream 追従（版上げ）

⚠⚠ **正本はこのファイル。** [docs/CLAUDE.md](../../../docs/CLAUDE.md) の「upstream 追従の手順」はここへのポインタ。

🔴 **外へ書く step を含む**（push・タグ・`stable/*` の付け替え・作業ブランチの削除）ので明示呼び出し専用。

## 全体の流れ

```text
upstream (tag) → merge/<版>/bshockdon → merge/<版>/curesta
                                      → merge/<版>/delmulin
```

派生ブランチに **upstream を直接マージしない。**必ず bshockdon 経由で流す。

| | やること | 節 |
| --- | --- | --- |
| 1 | 衝突の切り分け（SAME / FORK トリアージ） | [§1](#1-衝突の切り分けsame--fork-トリアージ) |
| 2 | 取りこぼし検査 | [§2](#2-取りこぼし検査) |
| 3 | 衝突しないのに壊れる箇所 | [§3](#3-衝突しないのに壊れる箇所最重要) |
| 4 | 版ごとの定例作業 | [§4](#4-版ごとの定例作業) |
| 5 | 検証 | [§5](#5-検証) |
| 6 | CI | [§6](#6-ci) |
| 7 | 後始末（6 台へ適用してから） | [§7](#7-後始末6-台への適用が終わってから) |

**RC が出たらステージング 3 台向けにマージを始める。**目的は **stable リリース当日に本番へデプロイできる状態を作っておくこと**で、本番に RC を載せるためではない。RC 期間のステージング適用は [staging-rc](../staging-rc/SKILL.md) へ。

⚠ **RC 期間にモロヘイヤ側でやることは無い。**この期間の作業は `pooza/mastodon` の 3 ブランチのマージとステージング適用に閉じる。パッチリリース（4.6.x 等）は差分が小さければ手で流す。

## このスキルはブランチを自分で見分ける

同梱スクリプトは `config/themes.yml` の登録テーマでインスタンスを判定する（`bshock`→bshockdon / `cure-*`→curesta / `dai` ほか→delmulin）。⚠⚠ **3 ブランチでこのスキルの中身を分岐させない。**ファイルが同一なら bshockdon→派生のマージで衝突しない。

## 1. 衝突の切り分け（SAME / FORK トリアージ）

マージベースは「stable-4.x が main から分岐した地点」まで遡るため、**衝突の大半はフォークと無関係な「4.x へのバックポート vs main の本流版」**になる。4.7.0-rc.1 では 58 件中 28 件がこれだった。

```bash
.claude/skills/upstream-merge/scripts/triage.sh v4.6.6   # 直前のリリースタグ
```

各衝突ファイルの HEAD 版を直前のリリースタグと突き合わせ、同一なら **フォーク改変ゼロ＝上流版を丸ごと採用してよい**と機械的に判定する。

🔴 **FORK 側を `git checkout --ours` で丸ごと採ってはいけない。**上流がそのファイルに加えた変更まで捨てることになる。**上流版を土台に、フォーク改変だけを再適用する**のが原則（例外は README.md のように上流を全面置換しているファイルだけ）。

## 2. 取りこぼし検査

解決後、**集合比較で漏れを検出する。**⚠ 目視で「たぶん大丈夫」と判断しない。

```bash
.claude/skills/upstream-merge/scripts/leftovers.sh <上流タグ> <前タグ> <ブランチ>
```

- `上流変更の取りこぼし疑い` … 上流と差異があるのに、フォークが改変しているファイルではない
- `フォーク改変の消失疑い` … フォークが改変しているのに、上流と差異が無くなっている

⚠ 上流がファイルを移動した場合は新旧パスの対で出るので、それだけは正常。

## 3. 衝突しないのに壊れる箇所（最重要）

**フォーク独自ファイルは上流のリネーム・依存削除に追従しないが、衝突としては現れない。**マージ後に必ずビルドを通すこと。4.7 で実際に踏んだ 3 件:

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| `lib/mastodon/version.rb` が 4.7.6 になる | major/minor は上流、patch だけ旧版が残る混成を自動マージが作る | フォークは version.rb を改変していないので上流版で上書き |
| テーマ SCSS がビルド不能 | 上流が `styles/mastodon/theme/` → `tokens/` にリネーム。独自エントリポイントは追従しない | §4 の再同期 |
| `Rolldown failed to resolve import "react-overlays/Overlay"` | 上流が react-overlays を依存ごと撤去 | §4 のタグセット移植 |

## 4. 版ごとの定例作業

### テーマエントリポイントの再同期

`app/javascript/styles/<テーマ>.scss` は **`application.scss` の全文 + 末尾のテーマブロック**という構造で、上流が application.scss を変えても追従しない。版上げのたびに再同期する:

```bash
.claude/skills/upstream-merge/scripts/theme-resync.py          # 確認だけ
.claude/skills/upstream-merge/scripts/theme-resync.py --write  # 書き戻す
```

対象テーマは `config/themes.yml` から読むので、**登録との不一致はスクリプトが落として知らせる**（片方にしか無いテーマ、ファイルが無いテーマ）。

⚠ 4.7 では併せて `@use 'mastodon/theme/economy'` → `@use 'mastodon/tokens/theme/economy'` のパス修正が必要だった。スクリプトは `mastodon/theme/` の残存も報告する。

### タグセットドロップダウンのミラー（#905）

[tagset_dropdown.tsx](../../../app/javascript/mastodon/features/compose/components/tagset_dropdown.tsx) は upstream の `language_dropdown.tsx` の薄い並行実装。**版上げのたびに language_dropdown の差分をそのまま当てる**:

```bash
git diff <前タグ> <新タグ> -- app/javascript/mastodon/features/compose/components/language_dropdown.tsx
```

4.7 では react-overlays → `components/popover`（floating-ui）への移行がここに該当した（`Overlay`→`Popover`、`useRef`→`useState` の参照渡し、`placement` state の撤去）。

⚠ このファイルは curesta / delmulin にしか無い。bshockdon では差分が出ないので飛ばしてよい。

### 用語ポリシーの再適用

```bash
.claude/skills/upstream-merge/scripts/terms-grep.sh
```

いずれも**ヒット 0 件**が正常。ブランチに応じて curesta 用の検査（投稿→キュア！ / ブースト→リキュア！）を足す。

🔴 **RC では ja 翻訳が更新されていないことが多く、置換対象が現れないことがある**（4.7.0-rc.1 がそうだった）。⚠⚠ **stable で Crowdin の ja が入った時点で必ず再チェックする。**

⚠ このスクリプトは**手元で当てるためのもの**。CI のゲートは別にあり、uppercase は stylelint、トゥートと キュア！置換は [spec/fork/terminology_guard_spec.rb](../../../spec/fork/terminology_guard_spec.rb) が見る（#972）。**手で直すのはここ、落ちるのはあちら**という役割分担。

## 5. 検証

```bash
bundle install && yarn install --immutable
bundle exec rubocop                 # offense 0 が正常
yarn build:production               # フォーク独自ファイルの破損はここでしか出ない
bundle exec rspec spec/fork         # ⚠ PostgreSQL 必須
```

⚠ `bundle exec rubocop` は **`bundle install` 済みでないと動かない。**上流の版上げで Gemfile.lock が進むと必ず失敗するので、マージ直後は入れ直す。

ビルド後、テーマが実際に効いているかを生成 CSS で確認する（後勝ちの上書きなので**最後の値**を見る）:

```bash
grep -o '\-\-color-grey-100:[^;]*' public/packs/assets/themes/<テーマ>-*.css | tail -1
```

default テーマと同じ値なら適用されていない。

**6 台へ適用したあとの外形確認は [release-verify](../release-verify/SKILL.md) へ。**

## 6. CI

上流の CI ワークフローは**すべて削除**し、[fork-ci.yml](../../../.github/workflows/fork-ci.yml) 一本に置き換えている。回るのは **spec/fork（PostgreSQL 込み）**と、**変更ファイルに限定した** ESLint / stylelint / RuboCop。手元で spec/fork を回せなくても CI が拾う。

通しのアセットビルドは [fork-assets-nightly.yml](../../../.github/workflows/fork-assets-nightly.yml) に分離している（#912）。**版を本番へ適用する前に一度回しておく。**

⚠ **schedule / workflow_dispatch はデフォルトブランチ（bshockdon）の定義しか起動できない。**RC 期間に `merge/**` を検査したいときは、手動実行の `ref` にブランチ名を渡す。

⚠ **push トリガーはブランチ名で絞っている**（`merge/**` / `stable/**` / 3 つのインスタンスブランチ）。**作業ブランチの命名規則を変えたらここも直す。**4.7 の追従では `work/4.6/**` のまま残っていたため、`merge/4.7/*` への push で CI が一度も走らなかった。

🔴 **`merge/**` が緑でも instance ブランチへ戻した push で落ちることがある。**Tier 1/2 は**変更ファイルに限定**して lint するため、**比較の基点が変わると検査対象も変わる**。2026-08-21 の 4.7.0 では、`merge/4.7/*` では対象外だった `styles/mastodon/tokens/theme/_economy.scss` が curesta / delmulin の instance ブランチ側で対象に入り、**#907 で書いた解説ブロックの空コメント 2 行**（`scss/comment-no-empty`）で落ちた。⚠⚠ **版上げの検証は instance ブランチへ戻した後の CI まで見る。**

## 7. 後始末（6 台への適用が終わってから）

**版上げは 6 台へ適用して終わりではない。**次の 3 つまでが 1 セット:

```bash
.claude/skills/upstream-merge/scripts/finalize.sh 4.7.2            # 確認だけ（既定）
.claude/skills/upstream-merge/scripts/finalize.sh 4.7.2 --execute  # タグ・stable・削除を実行
```

1. **リリースタグ** … `v<上流版>-<インスタンス>` の軽量タグ（例 `v4.7.2-curesta`）
2. **切り戻し先** … `stable/<系列>/<インスタンス>`（例 `stable/4.7/curesta`）
3. **作業ブランチの削除** … `merge/<系列>/<インスタンス>`。instance の祖先であることを確かめてから

🔴 **タグは版ごと、`stable/*` と `merge/*` は系列ごと。**`stable/4.7/*` は 4.7.0 で作って終わりではなく、**パッチリリースのたびに前進する移動ブランチ**（4.7.2 適用後はそこを指している）。「その版のスナップショットを新しく作る」ではないので、既存を fast-forward させる。⚠ fast-forward にならないときはスクリプトが止まる。巻き戻し先を壊すので自動で force しない。

🔴 **タグと `stable/<版>/*` は必ずしも同じコミットにならない。**タグは「その版としてのフォークの到達点」なので **instance ブランチの先端**に、`stable/<版>/*` は「本番が走っているコミット」なので**適用したコミット**に置く（4.7.0 では版上げ後に足した docs コミット 1 本ぶんずれた）。⚠ 既定では両方とも instance の先端を指すので、**ずれている版では `--applied <commit>` で適用コミットを渡す。**

⚠ **DB のスナップショットは残置する。**マイグレーションがある版では適用前に `<dataset>@pre-mastodon-<版>` を取る（→ [chubo2 infra-mastodon.md](https://github.com/pooza/chubo2/blob/main/docs/infra-mastodon.md)）。**数日運用して問題が無ければ削除する**のは運用者の判断。
