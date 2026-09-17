---
name: staging-rc
description: upstream の RC 期間に、ステージング 3 台（dev24/dev25/dev26）のチェックアウト先を instance ブランチから merge/<版>/<インスタンス> へ切り替える。stable が出たら戻す。refspec の確認、切り替えの検証、health 200 待ちまで。
disable-model-invocation: true
---

# RC 期間のステージング適用（`merge/**` への切り替え）

⚠⚠ **正本はこのファイル。** [docs/CLAUDE.md](../../../docs/CLAUDE.md) の「RC 期間のステージング適用」はここへのポインタ。

🔴 **実機のチェックアウトを切り替える**ので明示呼び出し専用。

**目的は stable リリース当日に本番へデプロイできる状態を作っておくこと。**本番に RC を載せるためではない。⚠ 対象は**ステージング 3 台だけ**。

| ホスト | ドメイン | ブランチ |
| --- | --- | --- |
| dev24 | st2.mstdn.b-shock.org（美食丼 stg） | `merge/<版>/bshockdon` |
| dev25 | st2.precure.ml（キュアスタ！ stg） | `merge/<版>/curesta` |
| dev26 | st3.mstdn.delmulin.com（デルムリン丼 stg） | `merge/<版>/delmulin` |

🔴 **dev25 と dev26 を取り違えない。**ドメイン名の見た目（`delmulin.com` ↔ delmulin）と機番の対応が**逆**なので間違えやすい。正本は chubo2 の [noah.yaml](https://github.com/pooza/chubo2/blob/main/config/node/noah.yaml) の `proxies`（実際に 443 を終端しているリバースプロキシの設定）。⚠ 迷ったら `curl -s https://<domain>/api/v2/instance | jq -r .title` で確かめる。

SSH は `mastodon@devNN`（インフラ操作で sudo が要るときは `pooza@devNN`）。リポジトリは `~mastodon/repos/mastodon`。⚠ 旧ステージング（drime + dev04 / dev15 / dev22 / dev23）は**退役済み**で、`devNN_mastodon` のような SSH エイリアスも廃止されている。

## 1. fetch の refspec を確認する（切り替える前に）

🔴 **dev25 / dev26 は single-branch clone の名残**で `+refs/heads/bshockdon:refs/remotes/origin/bshockdon` になっており、**`merge/4.7/*` を fetch できずチェックアウトが失敗した**（2026-08-15 の 4.7.0-rc.1）。

```bash
git config --get-all remote.origin.fetch                               # 確認
git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'   # 広げる
git rev-parse --verify origin/<branch>                                 # ref があることを確かめてから checkout
```

## 2. 切り替える

🔴 **`git checkout` の出力をパイプに通さない。**`set -e` は**パイプ末尾の終了コードしか見ない**ため、`git checkout ... | tail -1` と書くと**切り替え失敗を素通りして bundle / migrate / assets まで走る**。⚠⚠ 「適用したつもりで旧版のまま、アセットだけ再生成」という最悪の状態になりうる。

切り替えたら必ず検証する:

```bash
test "$(git rev-parse --abbrev-ref HEAD)" = "$BR"
```

サービス再起動は **`< /dev/null > /dev/null 2>&1` を必ず付ける**（daemon が SSH の stdout を握って ssh が抜けなくなる）。

## 3. health は固定待ちにしない

🔴 **`sleep 30` では起動途中に当たって誤った赤が出る。**puma の停止に 23 秒・起動完了まで計 47 秒かかった実測がある。**200 が返るまで待つ:**

```bash
until [ "$(curl -s -o /dev/null -w '%{http_code}' https://<staging-domain>/health)" = "200" ]; do sleep 10; done
```

## 4. 外形を確かめる

→ [release-verify](../release-verify/SKILL.md)。ステージングでも同じものを見る。

## 5. stable 当日に instance ブランチへ戻す

2026-08-21 の 4.7.0 で実施した流れ:

1. upstream タグを `merge/<版>/bshockdon` へマージ
2. 派生 2 本へ流す
3. **instance ブランチを `merge/<版>/*` へ fast-forward**
4. push・CI
5. ステージング 3 台のチェックアウト先を instance ブランチへ戻して適用
6. 本番 3 台

🔴 **RC 期間に instance ブランチ側だけへ入った commit は merge ブランチに無い**（4.7 では #912）。⚠⚠ **先に `git merge origin/<instance>` して merge ブランチを上位集合にしてから**でないと、instance ブランチへ戻すときに fast-forward できない。

⚠ **CI の schedule / workflow_dispatch はデフォルトブランチ（bshockdon）の定義しか起動できない。**RC 期間に `merge/**` を検査したいときは、手動実行の `ref` にブランチ名を渡す（定義は bshockdon のものが使われ、チェックアウト先だけが変わる）。

そのあとの後始末は [upstream-merge §7](../upstream-merge/SKILL.md#7-後始末6-台への適用が終わってから)。
