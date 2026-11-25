#!/usr/bin/env bash
# 用語ポリシーの再適用チェック（upstream 追従 §4）。いずれもヒット 0 件が正常。
#
# ⚠ これは「手元で当てて直すため」のもの。CI のゲートは別にある:
#     uppercase          … stylelint（#906）
#     トゥート / キュア！  … spec/fork/terminology_guard_spec.rb（#972）
#
# 🔴 RC では ja 翻訳が更新されていないことが多く、置換対象が現れないことがある
#    （4.7.0-rc.1 がそうだった）。stable で Crowdin の ja が入った時点で必ず再チェックする。
#
#   usage: terms-grep.sh
set -uo pipefail

cd "$(dirname "$0")/../../../.." || exit 2

# インスタンスは dist/servers/ のブランチ固有の nginx 設定で見分ける（3 ブランチで同じ中身のまま動かすため）。
# ⚠ 4.7 までは config/themes.yml で見分けていたが、5.0 で 3 ブランチとも同じになった（#1005）。
instance=unknown
if [ -f dist/servers/precure.ml.conf ]; then
  instance=curesta
elif [ -f dist/servers/mstdn.delmulin.com.conf ]; then
  instance=delmulin
elif [ -f dist/servers/mstdn.b-shock.org.conf ]; then
  instance=bshockdon
fi
echo "インスタンス: ${instance}（dist/servers/ から判定）"
echo

status=0

report() {
  local label=$1 hits=$2
  if [ -z "$hits" ]; then
    printf '  OK  %s\n' "$label"
  else
    printf '  NG  %s\n' "$label"
    printf '%s\n' "$hits" | sed 's/^/        /'
    status=1
  fi
}

echo "=== 大文字化を採用しない（#906）— 全ブランチ ==="
report 'text-transform: uppercase / capitalize' \
  "$(grep -rnE 'text-transform:\s*(uppercase|capitalize)' app/javascript 2>/dev/null || true)"

echo
echo "=== 廃止用語「トゥート」の排除 — 全ブランチ ==="
report 'トゥート' \
  "$(grep -rn 'トゥート' config/locales app/javascript/mastodon/locales 2>/dev/null || true)"

if [ "$instance" = curesta ]; then
  echo
  echo "=== 投稿→キュア！ / ブースト→リキュア！ — curesta のみ ==="
  report '投稿 / ブースト（ja）' \
    "$(grep -rn '投稿\|ブースト' config/locales/*ja*.yml app/javascript/mastodon/locales/ja.json 2>/dev/null || true)"
fi

echo
if [ "$status" -eq 0 ]; then
  echo "用語ポリシー: 問題なし。"
else
  echo "🔴 残存あり。上の箇所を直す。"
fi
exit "$status"
