# pooza/mastodon 開発ガイド

## プロジェクト概要

FreeBSD向けに調整されたMastodonのフォーク。拙作ツール [pooza/mulukhiya-toot-proxy](https://github.com/pooza/mulukhiya-toot-proxy)（通称「モロヘイヤ」）と併用することが想定されている。

- **ベース**: mastodon/mastodon（upstream）
- **デフォルトブランチ**: `bshockdon`
- **対象OS**: FreeBSD 14.x
- **技術スタック**: Ruby (Rails) / Node.js (streaming) / PostgreSQL / Redis

## ブランチ戦略

| ブランチ | インスタンス | 目的 |
| --- | --- | --- |
| `bshockdon` | 美食丼 | デフォルト。upstreamのタグをマージし、FreeBSD向けの調整を加える |
| `curesta` | キュアスタ！ | bshockdonからフォーク。キュアスタ！固有の調整 |
| `delmulin` | デルムリン丼 | bshockdonからフォーク。デルムリン丼固有の調整 |

美食丼は汎用のMastodonであるため、`bshockdon` がベースとなる。

### マージフロー

```text
upstream (tag) → bshockdon → curesta
                           → delmulin
```

1. upstreamの新バージョンがリリースされたら、タグを `bshockdon` にマージ
2. `bshockdon` の変更を `curesta` / `delmulin` にマージして追従
3. コンフリクトは決まった箇所で発生するため、手動で解消する

## FreeBSD向けの主な調整

### rc.dスクリプト（`dist/freebsd/`）

FreeBSD向けのサービス起動スクリプト。3本構成:

| スクリプト | サービス | プロセス |
| --- | --- | --- |
| `mastodon-web` | Puma Webサーバー | `rails server -u puma` |
| `mastodon-sidekiq` | Sidekiqワーカー | `sidekiq -C config/sidekiq.yml` |
| `mastodon-streaming` | Node.js Streaming API | `npm start` |

#### 起動コマンドの構造

```sh
daemon -f -S -T <syslogタグ> -u $mastodon_user /usr/local/bin/bash -lc "cd $mastodon_path && <コマンド>"
```

- `daemon(8)`: FreeBSD標準のデーモン化ユーティリティ
  - `-f`: stdin/stdout/stderrを/dev/nullにリダイレクト
  - `-S`: syslog出力を有効化
  - `-T <tag>`: syslogタグ設定
  - `-u <user>`: 指定ユーザーで実行
- `/usr/local/bin/bash -lc`: ログインシェルとして実行（`.bash_profile` 経由でrbenv等を初期化）

#### rc.conf設定

```sh
mastodon_enable="YES"
mastodon_path="/usr/local/www/mastodon"  # Mastodonのインストールパス
mastodon_user="mastodon"                 # 実行ユーザー
```

#### mastodonユーザーの `.bash_profile`

ログインシェルはzshだが、rc.dスクリプトは `bash -lc` で実行する。以下の `.bash_profile` が必要:

```bash
# PATH
export PATH=$HOME/bin:$HOME/.rbenv/bin:$HOME/.rbenv/shims:/usr/local/bin:/usr/local/sbin:/bin:/sbin:/usr/bin:/usr/libexec:/usr/sbin:$PATH

# Locale
export LANG=ja_JP.UTF-8
export LC_CTYPE=ja_JP.UTF-8
export LC_ALL=ja_JP.UTF-8

# rbenv
eval "$(rbenv init - bash)"
```

### ストリーミングサービス

`streaming/` 配下は純粋なNode.jsアプリケーションであり、FreeBSD固有のコード修正は不要。サービス管理はrc.dスクリプトで行う。

### Ubuntu前提箇所について

upstreamのMastodonはUbuntuを唯一のサポート対象と匂わせている箇所が多い（systemdサービスファイル、Dockerfile、Vagrantfile等）。ただし、アプリケーションコード自体はOS非依存であり、FreeBSD対応に必要なのはrc.dスクリプトと環境設定のみ。

## 解決済み: #900 rc.dスクリプトの起動ブロック問題（2026-03-01）

### 症状

OS起動時（カーネル更新後の再起動等）にサービス起動が完了せず、`^C` が必要になる。

### 原因

旧スクリプトの起動コマンドに複数の問題があった:

```sh
# 旧: zsh + sudo + & によるバックグラウンド化
sudo -u $mastodon_user zsh -c 'RAILS_ENV=production bundle exec rails server -u puma | logger -t mastodon_web &'
```

1. **`zsh -c` を使用** — ログインシェルとして呼ばれておらず、環境変数の初期化が不完全な場合がある
2. **`&` によるバックグラウンド化が不十分** — パイプラインのバックグラウンド化がrc.dから見て正しく機能しない場合がある
3. **`daemon(8)` を使っていない** — FreeBSD標準のデーモン化手法でなかった

### 修正

```sh
# 新: daemon(8) + bash -lc
daemon -f -S -T mastodon_web -u $mastodon_user /usr/local/bin/bash -lc "cd $mastodon_path && RAILS_ENV=production bundle exec rails server -u puma"
```

- `daemon(8)` による正式なデーモン化（即座にrc.dに制御を返す）
- `/usr/local/bin/bash -lc` でログインシェルとして実行（`.bash_profile` 経由でrbenv初期化）
- `sudo` と `| logger &` を廃止（daemon の `-u`, `-S -T` で代替）

### 検証結果

全ステージング環境で `service mastodon-xxx restart` がブロックなしで完了することを確認:

- dev04（美食丼）
- dev15（デルムリン丼）
- dev22（キュアスタ！）

### 本番適用

[pooza/chubo2#5](https://github.com/pooza/chubo2/issues/5) で管理。本番にはmonitがあるため、適用時は monit停止 → サービス再起動 → monit再開 の手順が必要。

### 経緯

mulukhiya-toot-proxy側での調査（#4105, #4101）が先行し、モロヘイヤ側は5.2.0で修正済み。Mastodon側のrc.dスクリプトが残存原因として特定された。

## 情報の記載先ルール

- **課題・タスク** → GitHub Issueで管理（インフラ面の課題は `pooza/chubo2` のIssueとして起票）
- **プロジェクト共有すべき知見** → `docs/CLAUDE.md` などgit管理下のファイルに記載
- **インフラ情報** → [pooza/chubo2 インフラノート](https://github.com/pooza/chubo2/blob/main/docs/infra-note.md) を参照

## 開発サーバー・インフラ

SSH経由で操作可能。接続情報は `~/.ssh/config` で管理（リポジトリには含めない）。

| サーバー | インスタンス | 種別 | SSHエイリアス |
| --- | --- | --- | --- |
| dev04 | 美食丼 | ステージング | `dev04_mastodon` / `dev04_mulukhiya` |
| dev15 | デルムリン丼 | ステージング | `dev15_mastodon` / `dev15_mulukhiya` |
| dev22 | キュアスタ！ | ステージング | `dev22_mastodon` / `dev22_mulukhiya` |

- `devNN_mastodon`: mastodonユーザーで接続（Mastodon操作用）
- `devNN_mulukhiya`: poozaユーザーで接続（sudo可能、rc.dスクリプトのデプロイ等に使用）
- mastodonユーザーのホームディレクトリがMastodonリポジトリのルート

本番サーバーの情報は [pooza/chubo2 インフラノート](https://github.com/pooza/chubo2/blob/main/docs/infra-note.md) を参照。

## rc.dスクリプトのデプロイ手順

```bash
# 1. ローカルからスクリプトをコピー
scp dist/freebsd/mastodon-{web,sidekiq,streaming} devNN_mastodon:/tmp/

# 2. sudoできるユーザーで配置
ssh devNN_mulukhiya 'sudo cp /tmp/mastodon-{web,sidekiq,streaming} /usr/local/etc/rc.d/ && sudo chmod 755 /usr/local/etc/rc.d/mastodon-{web,sidekiq,streaming}'

# 3. サービス再起動（本番ではmonit停止/再開を挟む）
ssh devNN_mulukhiya 'sudo service mastodon-web restart && sudo service mastodon-sidekiq restart && sudo service mastodon-streaming restart'
```

## 関連リポジトリ

- [pooza/mulukhiya-toot-proxy](https://github.com/pooza/mulukhiya-toot-proxy) — 併用プロキシ（モロヘイヤ）
- [pooza/chubo2](https://github.com/pooza/chubo2) — インフラ情報（プライベート）
- [mastodon/mastodon](https://github.com/mastodon/mastodon) — upstream

## gh CLI使用時の注意

フォークリポジトリでは `gh` コマンドがupstream（mastodon/mastodon）をデフォルトで参照する場合がある。Issue操作やPR作成時は `-R pooza/mastodon` を明示すること。
