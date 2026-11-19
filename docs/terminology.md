# 上流の用語の台帳（#1004）

Mastodon の WebUI が機能を何と呼んでいるかを、版ごとに記録する。**上流の事実だけを書く**場所で、
フォーク・capsicum・モロヘイヤがそれをどう使うかの判断はそれぞれの側に置く
（capsicum は `docs/product-policy.md` の用語表、フォークの置換は
[spec/fork/terminology_guard_spec.rb](../spec/fork/terminology_guard_spec.rb)）。

⚠ **ja の訳が付くまでは 4.7 の用語を続投する。**5.0 の新しいキーは beta.1 の時点で ja の訳が
1 件も無い。英語から訳語を先回りして決めない — Crowdin で付く訳がずれると、
フォーク・capsicum・モロヘイヤの 3 か所で揃って言い直すことになる。

## 更新の仕方

```bash
.claude/skills/upstream-merge/scripts/terms-diff.py v4.7.5 v5.0.0-beta.1          # 版どうしの全体差分
git fetch upstream
.claude/skills/upstream-merge/scripts/terms-diff.py v5.0.0-beta.1 upstream/main --ledger   # 下の表のキーの訳が付いたか
```

- 版上げ（beta / RC / stable）のたびに走らせる（[upstream-merge スキル](../.claude/skills/upstream-merge/SKILL.md)「用語ポリシーの再適用」）
- ⚠ Crowdin の ja は版と関係なく upstream main に入る。訳語待ちの間は main とも比べる
- 表の「状態」が変わったら、pooza/capsicum と pooza/mulukhiya-toot-proxy に issue を立てて知らせる
  （本文に `pooza/mastodon#1004` とこの台帳へのリンク）

状態: **続投中** = 新しい呼び名に ja の訳がまだ無く、4.7 の ja を使い続けている / **確定** = ja の訳が付いた / **不変** = 5.0 でも同じ

## 5.0（基準: v5.0.0-beta.1・2026-11-06 確認）

| 機能 | 4.7 の ja（続投中の用語） | 4.7 のキー・en | 5.0 のキー・en | 5.0 の ja | 状態 |
|---|---|---|---|---|---|
| リスト | リスト | `column.lists` Lists | `column.custom_feeds` Custom Feeds / `account.menu.add_to_feed` Add to custom feed… | — | 続投中 |
| 非公開の返信 | 非公開の返信 | `column.direct` Private mentions | `tab_bar.messages` Messages / `privacy.message.short` Message | — | 続投中 |
| お気に入り | お気に入り | `status.favourite` Favorite | `status.like` Like / `navigation_bar.liked_posts` Liked Posts | — | 続投中 |
| ブックマーク | ブックマーク | `status.bookmark` Bookmark | `status.save` Save post / `column.saved_posts` Saved Posts | — | 続投中 |
| ひかえめな公開 | ひかえめな公開 | `privacy.unlisted.short` Quiet public | `compose.privacy.unlisted` Public, hidden from search | — | 続投中 |
| フォロワー（公開範囲） | フォロワー | `privacy.private.short` Followers | `compose.privacy.followers` Followers (+ mentions) | — | 続投中 |
| ローカルタイムライン | ローカルタイムライン | `column.community` Local timeline | `column.this_server` This Server | — | 続投中 |
| 連合タイムライン | 連合タイムライン | `column.public` Federated timeline | `column.other_servers` Other Servers（両方まとめて `tabs_bar.public_feeds` Public Feeds） | — | 続投中 |
| ブロックしたユーザー | ブロックしたユーザー | `navigation_bar.blocks` Blocked users | `column.blocked_accounts` Blocked Accounts（ミュートとまとめて `navigation_bar.relationships` Relationships） | — | 続投中 |
| ミュートしたユーザー | ミュートしたユーザー | `navigation_bar.mutes` Muted users | `column.muted_accounts` Muted Accounts | — | 続投中 |
| 代替テキスト | 代替テキスト | `alt_text_badge.title` Alt text | `alt_text_badge.title` Image description（同じキーで原文だけ変更） | — | 続投中 |
| ログアウト | ログアウト | `confirmations.logout.confirm` Log out | `navigation_bar.sign_out` Sign Out | — | 続投中 |
| ブースト | ブースト | `status.reblog` Boost | `status.reblog` Boost | ブースト | 不変 |
| リアルタイムフィード | リアルタイムフィード | `column.firehose` Live feeds | `column.firehose` Live feeds | リアルタイムフィード | 不変 |

- ⚠ 5.0 でも旧キー（`column.lists` など）は ja.json に残っている。旧 UI の部品が残っているだけで、
  新 UI の画面に出るのは右側のキー。「5.0 の ja に旧キーの訳がある」ことを確定と読まない
- 固定された投稿（`column.pins`）は 5.0 でキーが消えた。移り先は未確認
- curesta の「ブースト → リキュア！」は、5.0 でもブーストの呼び名が変わらないのでそのまま効く
