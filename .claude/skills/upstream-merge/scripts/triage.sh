#!/usr/bin/env bash
# 衝突ファイルを SAME / FORK に切り分ける（upstream 追従 §1）。
#
# HEAD 版を直前のリリースタグと突き合わせ、同一なら「フォーク改変ゼロ＝上流版を
# 丸ごと採用してよい」と機械的に判定する。4.7.0-rc.1 では 58 件中 28 件が SAME だった。
#
#   usage: triage.sh <直前のリリースタグ>
set -euo pipefail

tag=${1:-}
if [ -z "$tag" ]; then
  echo "usage: ${0##*/} <直前のリリースタグ>   例: ${0##*/} v4.6.6" >&2
  exit 2
fi

if ! git rev-parse --verify --quiet "${tag}^{commit}" >/dev/null; then
  echo "タグが見つからない: ${tag}（git fetch upstream --tags 済みか）" >&2
  exit 2
fi

same=0
fork=0
out=$(mktemp)
trap 'rm -f "$out"' EXIT

while IFS= read -r -d '' f; do
  a=$(git rev-parse "HEAD:${f}" 2>/dev/null || echo none)
  b=$(git rev-parse "${tag}:${f}" 2>/dev/null || echo none)
  if [ "$a" = "$b" ]; then
    printf 'SAME  %s\n' "$f" >>"$out"
    same=$((same + 1))
  else
    printf 'FORK  %s\n' "$f" >>"$out"
    fork=$((fork + 1))
  fi
done < <(git diff --name-only --diff-filter=U -z)

if [ $((same + fork)) -eq 0 ]; then
  echo "衝突中のファイルは無い。"
  exit 0
fi

sort "$out"
echo
echo "SAME ${same} 件 / FORK ${fork} 件（基準タグ ${tag}）"
echo
echo "SAME … フォーク改変ゼロ。上流版を丸ごと採ってよい:"
echo "         git checkout --theirs -- <file> && git add <file>"
echo "FORK … 上流版を土台に、フォーク改変だけを再適用する。"
echo "  ⚠ FORK を --ours で丸ごと採ると、上流がそのファイルに加えた変更まで捨てる。"
