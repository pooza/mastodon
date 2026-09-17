#!/usr/bin/env bash
# 取りこぼし検査（upstream 追従 §2）。集合比較で漏れを検出する。
#
# 目視で「たぶん大丈夫」と判断しないための機械的な検査。マージ解決を stage した状態で回す。
#
#   usage: leftovers.sh <上流タグ> <前タグ> <ブランチ>
#   例:    leftovers.sh v4.7.2 v4.7.1 origin/bshockdon
set -euo pipefail

upstream_tag=${1:-}
prev_tag=${2:-}
branch=${3:-}

if [ -z "$upstream_tag" ] || [ -z "$prev_tag" ] || [ -z "$branch" ]; then
  echo "usage: ${0##*/} <上流タグ> <前タグ> <ブランチ>" >&2
  echo "  例:  ${0##*/} v4.7.2 v4.7.1 origin/bshockdon" >&2
  exit 2
fi

for ref in "$upstream_tag" "$prev_tag" "$branch"; do
  git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null ||
    { echo "ref が見つからない: ${ref}" >&2; exit 2; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A: 上流と差異があるファイル（＝いまの解決結果がフォーク側として持っているもの）
git diff --cached --name-only "$upstream_tag" | sort >"${work}/A"
# B: フォークが実際に改変しているファイル
git diff --name-only "$prev_tag" "$branch" | sort >"${work}/B"

a_only=$(comm -23 "${work}/A" "${work}/B")
b_only=$(comm -13 "${work}/A" "${work}/B")

echo "=== 上流変更の取りこぼし疑い（A にあって B に無い） ==="
if [ -n "$a_only" ]; then echo "$a_only"; else echo "（なし）"; fi
echo
echo "=== フォーク改変の消失疑い（B にあって A に無い） ==="
if [ -n "$b_only" ]; then echo "$b_only"; else echo "（なし）"; fi
echo
echo "⚠ 上流がファイルを移動した場合は新旧パスの対で出る。それだけは正常。"

if [ -z "$a_only" ] && [ -z "$b_only" ]; then
  echo "取りこぼしなし。"
fi
