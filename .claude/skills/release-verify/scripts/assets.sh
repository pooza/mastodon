#!/usr/bin/env bash
# アセット到達性の確認（#954）。トップの HTML が参照する CSS を全部引き、
# 200 かつ text/css であることを見る。
#
# 🔴 バックエンドが生きていれば API も /api/v2/instance も通るので、ブランチ・
#    マイグレーション・manifest の確認は全部緑のまま WebUI だけ崩れうる。
#
#   usage: assets.sh <domain>
#   例:    assets.sh mstdn.delmulin.com
set -uo pipefail

domain=${1:-}
if [ -z "$domain" ]; then
  echo "usage: ${0##*/} <domain>   例: ${0##*/} mstdn.delmulin.com" >&2
  exit 2
fi
domain=${domain#https://}
domain=${domain%/}

html=$(curl -fsS --max-time 20 "https://${domain}/" 2>/dev/null) || {
  echo "🔴 トップが引けない: https://${domain}/" >&2
  exit 1
}

paths=$(printf '%s' "$html" | grep -o '/packs/[^"]*\.css' | sort -u)
if [ -z "$paths" ]; then
  echo "🔴 トップの HTML に /packs/*.css の参照が無い。HTML の取り方かビルドを疑う。" >&2
  exit 1
fi

status=0
count=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  count=$((count + 1))
  read -r code ctype <<<"$(curl -s -o /dev/null --max-time 20 \
    -w '%{http_code} %{content_type}' "https://${domain}${path}")"
  case "${code}:${ctype}" in
    200:text/css*) printf '  OK  %s %s %s\n' "$code" "$ctype" "$path" ;;
    *)             printf '  NG  %s %s %s\n' "$code" "$ctype" "$path"; status=1 ;;
  esac
done <<<"$paths"

echo
if [ "$status" -eq 0 ]; then
  echo "${domain}: CSS ${count} 本すべて 200 / text/css。"
else
  echo "🔴 ${domain}: 到達しない CSS がある。manifest とファイルのずれを疑う。"
  echo "   （Vite のハッシュ付きチャンクなので「一部の CSS だけ 404」になる）"
fi
exit "$status"
