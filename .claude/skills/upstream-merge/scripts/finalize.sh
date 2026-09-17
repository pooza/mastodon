#!/usr/bin/env bash
# 後始末（upstream 追従 §7）。6 台への適用が終わってから回す。
#
#   1. リリースタグ v<版>-<インスタンス>（軽量タグ）を instance ブランチの先端へ
#   2. 切り戻し先 stable/<系列>/<インスタンス> を「本番へ実際に適用したコミット」へ
#   3. 作業ブランチ merge/<系列>/<インスタンス> の削除（祖先であることを確かめてから）
#
# ⚠ タグは版ごと（v4.7.2-curesta）、stable と merge は系列ごと（stable/4.7/curesta）。
#   stable/<系列>/* は固定のスナップショットではなく、パッチリリースのたびに前進する。
#
# 🔴 既定は確認だけ。--execute を付けたときだけ外へ書く。
#
#   usage: finalize.sh <版> [--execute] [--applied <インスタンス>=<commit>]...
#   例:    finalize.sh 4.7.2
#          finalize.sh 4.7.2 --applied curesta=abc1234 --execute
set -euo pipefail

INSTANCES="bshockdon curesta delmulin"

version=""
execute=0
declare -A applied=()

while [ $# -gt 0 ]; do
  case "$1" in
    --execute) execute=1; shift ;;
    --applied)
      [ $# -ge 2 ] || { echo "--applied には <インスタンス>=<commit> が要る" >&2; exit 2; }
      i=${2%%=*}; c=${2#*=}
      [ "$i" != "$2" ] && [ -n "$c" ] || { echo "形式が違う: $2" >&2; exit 2; }
      applied[$i]=$c; shift 2 ;;
    -*) echo "不明な引数: $1" >&2; exit 2 ;;
    *) [ -z "$version" ] || { echo "版は 1 つだけ: $1" >&2; exit 2; }
       version=$1; shift ;;
  esac
done

if [ -z "$version" ]; then
  echo "usage: ${0##*/} <版> [--execute] [--applied <インスタンス>=<commit>]..." >&2
  echo "  例:  ${0##*/} 4.7.2 --applied curesta=abc1234 --execute" >&2
  exit 2
fi

# 系列は先頭 2 要素（4.7.2 -> 4.7）。⚠ ${version%.*} は 4.7 を渡されたとき 4 になる。
case "$version" in
  *.*.*) series=${version%.*} ;;
  *.*)   series=$version ;;
  *)     echo "版の形式が違う: ${version}（例 4.7.2）" >&2; exit 2 ;;
esac

git fetch origin --quiet --prune

run() {
  if [ "$execute" -eq 1 ]; then
    echo "  \$ $*"
    "$@"
  else
    echo "  （dry-run） $*"
  fi
}

problems=0
note() { echo "  🔴 $*"; problems=$((problems + 1)); }

echo "版: ${version}"
[ "$execute" -eq 1 ] || echo "🔴 dry-run。実行するには --execute を付ける。"
echo

# --- 1. リリースタグ ---------------------------------------------------------
echo "=== 1. リリースタグ（instance ブランチの先端） ==="
tags=()
for i in $INSTANCES; do
  tag="v${version}-${i}"
  if ! git rev-parse --verify --quiet "refs/remotes/origin/${i}" >/dev/null; then
    note "origin/${i} が無い"; continue
  fi
  tip=$(git rev-parse --short "origin/${i}")
  if git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null; then
    at=$(git rev-parse --short "${tag}^{commit}")
    if [ "$at" = "$tip" ]; then
      echo "  済  ${tag} -> ${at}"
    else
      note "${tag} は既にあるが ${at}（origin/${i} の先端は ${tip}）。手で確かめる"
    fi
    continue
  fi
  echo "  新  ${tag} -> ${tip}"
  run git tag "$tag" "origin/${i}"
  tags+=("$tag")
done
if [ ${#tags[@]} -gt 0 ]; then
  run git push origin "${tags[@]}"
fi

# --- 2. 切り戻し先のスナップショット -----------------------------------------
echo
echo "=== 2. 切り戻し先 stable/${series}/<インスタンス> ==="
echo "  ⚠ タグと stable/* は必ずしも同じコミットにならない。"
echo "    タグ＝その版としてのフォークの到達点（instance の先端）"
echo "    stable/*＝本番が走っているコミット（--applied で渡す）"
echo "  ⚠ stable/<系列>/* は既存を前進させる。fast-forward でないときは手で確かめる。"
for i in $INSTANCES; do
  br="stable/${series}/${i}"
  target=${applied[$i]:-origin/${i}}
  if ! git rev-parse --verify --quiet "${target}^{commit}" >/dev/null; then
    note "${br} の対象 ref が無い: ${target}"; continue
  fi
  short=$(git rev-parse --short "${target}")
  src=$([ -n "${applied[$i]:-}" ] && echo '--applied' || echo 'origin の先端')

  if ! git rev-parse --verify --quiet "refs/remotes/origin/${br}" >/dev/null; then
    echo "  新  ${br} -> ${short}（${src}）"
    run git branch "$br" "$target"
    run git push origin "${br}:refs/heads/${br}"
    continue
  fi

  now=$(git rev-parse --short "origin/${br}")
  if [ "$now" = "$short" ]; then
    echo "  済  ${br} -> ${now}"
  elif git merge-base --is-ancestor "origin/${br}" "$target"; then
    echo "  進  ${br} ${now} -> ${short}（${src}・fast-forward）"
    run git branch -f "$br" "$target"
    run git push origin "${br}:refs/heads/${br}"
  else
    note "${br} は ${now} で、${short} への fast-forward にならない。巻き戻し先を手で確かめる"
  fi
done

# --- 3. 作業ブランチの削除 ---------------------------------------------------
echo
echo "=== 3. 作業ブランチ merge/${series}/<インスタンス> の削除 ==="
for i in $INSTANCES; do
  mb="merge/${series}/${i}"
  if ! git rev-parse --verify --quiet "refs/remotes/origin/${mb}" >/dev/null; then
    echo "  無  origin/${mb}（削除済みか、この版では切っていない）"
    continue
  fi
  if git merge-base --is-ancestor "origin/${mb}" "origin/${i}"; then
    echo "  可  origin/${mb} は origin/${i} の祖先"
    run git push origin --delete "$mb"
  else
    note "origin/${mb} は origin/${i} の祖先ではない。取り込み漏れが無いか確かめる"
  fi
done

echo
if [ "$problems" -gt 0 ]; then
  echo "🔴 要確認 ${problems} 件。上を見てから進める。"
  exit 1
fi
if [ "$execute" -eq 1 ]; then
  echo "後始末おわり。⚠ DB スナップショット <dataset>@pre-mastodon-${version} の削除は運用者の判断。"
else
  echo "確認おわり。実行するには --execute を付ける。"
fi
