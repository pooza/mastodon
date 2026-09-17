#!/usr/bin/env bash
# CSP 実効ヘッダの確認。Material Symbols（スタートメニューのアイコン）は
# fonts.googleapis.com のスタイルシート頼みで、CSP のホスト指定が版上げで落ちると
# アイコンの代わりに `home` などの文字列がそのまま出る。
#
# 🔴 HTML に link が出ていることだけで判断しない。link は application.html.haml に
#    無条件で書かれているので、CSP が落ちていても必ず出る。grep は緑になるのに
#    ブラウザは弾く。spec/fork のガードもチェックアウトした Rails 設定を見るだけで、
#    実際に配信されているヘッダは見ていない。
#
# ⚠ style-src（スタイルシート）と font-src（フォント本体）は別のホスト。
#   両方見ないと片方だけ落ちた状態を見逃す。
#
#   usage: csp.sh <domain>
set -uo pipefail

domain=${1:-}
if [ -z "$domain" ]; then
  echo "usage: ${0##*/} <domain>   例: ${0##*/} mstdn.delmulin.com" >&2
  exit 2
fi
domain=${domain#https://}
domain=${domain%/}

csp=$(curl -fsSI --max-time 20 "https://${domain}/" 2>/dev/null |
  grep -i '^content-security-policy:' | tr ';' '\n') || true

if [ -z "$csp" ]; then
  echo "🔴 ${domain}: Content-Security-Policy ヘッダが返っていない。" >&2
  exit 1
fi

status=0
check() {
  local directive=$1 host=$2 label=$3
  local pattern=${host//./\\.}
  if printf '%s\n' "$csp" | grep -qE "^ *${directive} .*${pattern}"; then
    printf '  OK  %-10s %s（%s）\n' "$directive" "$host" "$label"
  else
    printf '  NG  %-10s %s（%s）\n' "$directive" "$host" "$label"
    status=1
  fi
}

check 'style-src' 'https://fonts.googleapis.com' 'スタイルシート'
check 'font-src'  'https://fonts.gstatic.com'    'フォント本体'

echo
if [ "$status" -eq 0 ]; then
  echo "${domain}: Material Symbols の取得元が CSP に入っている。"
else
  echo "🔴 ${domain}: CSP のホスト指定が落ちている。アイコンが文字列（home など）で出る。"
  echo "   実効ヘッダ:"
  printf '%s\n' "$csp" | sed 's/^/     /'
fi
exit "$status"
