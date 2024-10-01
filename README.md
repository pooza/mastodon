# デルムリン丼

https://mstdn.delmulin.com

フォーク元 https://github.com/mastodon/mastodon

## 変更点

- FreeBSD向けの調整
- 拙作[mulukhiya-toot-proxy](https://github.com/pooza/mulukhiya-toot-proxy)むけの調整
  - WebUIの画像リサイズ処理をキャンセル
  - 投稿の「もっと見る」メニューに「タグ付け」追加
- 実況メニュー
- Elasticsearchなしでも動作する、簡易な投稿検索 ~~pgroonga対応~~
- スタートメニューの項目をAjaxで拡張
- ローカルタイムラインのリンクの宛先を #delmulin タグに
- レートリミットの対象外とするネットワークを指定できる様に
- 2024/2に大量発生したスパムへの対策
- パラメータ調整多数
