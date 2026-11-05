#!/usr/bin/env python3
"""上流の用語の変化を 2 つの版のあいだで突き合わせる（upstream 追従 §4・#1004）。

WebUI の文言ファイル（app/javascript/mastodon/locales/{en,ja}.json）を git から直接読み、
次の 4 つを出す。結果を見て docs/terminology.md（台帳）を更新し、変化があれば
capsicum・モロヘイヤへ issue で知らせる。

  1. 英語原文が変わったキー（改称の手がかり）
  2. 削除されたキー / 追加されたキー（キーの入れ替え＝機能の改称・作り直し）
  3. ja の訳が新しく付いたキー・ja の訳が変わったキー（訳語の確定）
  4. 台帳に載せたキーの現状（--ledger）

⚠ Crowdin の ja は版と関係なく upstream main に入る。5.0 の訳語待ちの間は
  `terms-diff.py v5.0.0-beta.1 upstream/main --ledger` のように main とも比べる
  （先に `git fetch upstream`）。

  usage: terms-diff.py <旧 ref> <新 ref> [--ledger] [--grep <正規表現>]

    --ledger          台帳（docs/terminology.md）に `キー` で書いたものだけ、新 ref での en / ja を出す
    --grep <正規表現>  キー・en・ja のいずれかが一致する行だけに絞る
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
LOCALES = "app/javascript/mastodon/locales"
LEDGER = ROOT / "docs" / "terminology.md"
LEDGER_KEY = re.compile(r"`([a-z_]+(?:\.[A-Za-z0-9_\-]+)+)`")


def load(ref: str, lang: str) -> dict[str, str]:
  try:
    raw = subprocess.check_output(
      ["git", "-C", str(ROOT), "show", f"{ref}:{LOCALES}/{lang}.json"],
      stderr=subprocess.PIPE,
    )
  except subprocess.CalledProcessError as e:
    sys.exit(f"{ref} の {lang}.json を読めない: {e.stderr.decode().strip()}")
  return json.loads(raw)


def show(v: str | None) -> str:
  return "（未訳）" if v is None else v


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("old")
  ap.add_argument("new")
  ap.add_argument("--ledger", action="store_true")
  ap.add_argument("--grep")
  args = ap.parse_args()

  en_old, en_new = load(args.old, "en"), load(args.new, "en")
  ja_old, ja_new = load(args.old, "ja"), load(args.new, "ja")
  pat = re.compile(args.grep, re.I) if args.grep else None

  def hit(*fields: str | None) -> bool:
    return pat is None or any(f and pat.search(f) for f in fields)

  def section(title: str, rows: list[str]) -> None:
    print(f"=== {title}（{len(rows)} 件）===")
    for r in rows:
      print(f"  {r}")
    print()

  if args.ledger:
    if not LEDGER.exists():
      sys.exit(f"台帳が無い: {LEDGER}")
    keys = sorted(set(LEDGER_KEY.findall(LEDGER.read_text())))
    rows = []
    for k in keys:
      if k not in en_new:
        rows.append(f"{k} | （{args.new} に無い）")
        continue
      mark = "" if ja_new.get(k) is None else "★"
      if ja_new.get(k) != ja_old.get(k) and ja_new.get(k) is not None:
        mark = "★新"
      if hit(k, en_new[k], ja_new.get(k)):
        rows.append(f"{mark:2} {k} | {en_new[k]} | ja: {show(ja_new.get(k))}")
    section(f"台帳のキー（{args.new}）★=訳あり ★新={args.old} から訳が付いた・変わった", rows)
    return 0

  common = sorted(set(en_old) & set(en_new))
  section(
    "英語原文が変わったキー",
    [
      f"{k} | {en_old[k]} => {en_new[k]} | ja: {show(ja_new.get(k))}"
      for k in common
      if en_old[k] != en_new[k] and hit(k, en_old[k], en_new[k], ja_new.get(k))
    ],
  )
  section(
    "削除されたキー",
    [
      f"{k} | {en_old[k]} | ja: {show(ja_old.get(k))}"
      for k in sorted(set(en_old) - set(en_new))
      if hit(k, en_old[k], ja_old.get(k))
    ],
  )
  section(
    "追加されたキー",
    [
      f"{k} | {en_new[k]} | ja: {show(ja_new.get(k))}"
      for k in sorted(set(en_new) - set(en_old))
      if hit(k, en_new[k], ja_new.get(k))
    ],
  )
  section(
    "ja の訳が新しく付いた・変わったキー",
    [
      f"{k} | {en_new[k]} | ja: {show(ja_old.get(k))} => {ja_new[k]}"
      for k in sorted(en_new)
      if ja_new.get(k) is not None
      and ja_new.get(k) != ja_old.get(k)
      and hit(k, en_new[k], ja_old.get(k), ja_new.get(k))
    ],
  )
  return 0


if __name__ == "__main__":
  sys.exit(main())
