#!/usr/bin/env python3
"""テーマエントリポイントの再同期（upstream 追従 §4）。

app/javascript/styles/<テーマ>.scss は「application.scss の全文 + 末尾のテーマブロック」
という構造で、上流が application.scss を変えても追従しない。版上げのたびに再同期する。

対象テーマは config/themes.yml から読む（ハードコードしない）。3 ブランチで同じ内容の
まま動かすための約束。

  usage: theme-resync.py [--write] [--prev <前タグ>]

    --write          既定は確認だけ。付けると書き戻す
    --prev <タグ>    テーマブロックの切り出しに、前の版の application.scss を使う
                     （上流が application.scss の途中から行を消した版で必要）
"""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
STYLES = ROOT / "app" / "javascript" / "styles"
THEMES_YML = ROOT / "config" / "themes.yml"
APPLICATION = STYLES / "application.scss"

ENTRY = re.compile(r"^\s*([^#:\s]+)\s*:\s*(\S+)\s*$")


def read_themes() -> dict[str, str]:
    """config/themes.yml の登録を {テーマ名: パス} で返す（default は除く）。"""
    themes: dict[str, str] = {}
    for line in THEMES_YML.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = ENTRY.match(line)
        if m and m.group(1) != "default":
            themes[m.group(1)] = m.group(2)
    return themes


def old_base_lines(prev: str) -> list[str]:
    rel = APPLICATION.relative_to(ROOT).as_posix()
    out = subprocess.run(
        ["git", "show", f"{prev}:{rel}"],
        cwd=ROOT, capture_output=True, text=True, check=False,
    )
    if out.returncode != 0:
        sys.exit(f"前タグの application.scss を取れない: {prev}\n{out.stderr.strip()}")
    return out.stdout.rstrip("\n").split("\n")


def split_fork_block(theme_lines: list[str], base_lines: list[str],
                     prev_lines: list[str] | None, name: str) -> list[str]:
    """テーマファイルから、末尾のフォーク固有ブロックだけを切り出す。"""
    if prev_lines is not None:
        n = len(prev_lines)
        if theme_lines[:n] != prev_lines:
            sys.exit(
                f"{name}: 前タグの application.scss が先頭に一致しない。\n"
                "  すでに再同期済みか、--prev のタグが違う。"
            )
        return theme_lines[n:]

    # 前タグの指定が無いときは、いまの application.scss との共通接頭辞で切る。
    i = 0
    while i < len(theme_lines) and i < len(base_lines) and theme_lines[i] == base_lines[i]:
        i += 1
    tail = theme_lines[i:]

    # 共通接頭辞が base の途中で切れた場合（上流が行を消した版）は、tail の先頭に
    # base の残りが混ざる。@use 'mastodon/... が出てきたらそれなので、止める。
    for line in tail:
        if not line.strip():
            continue
        if line.startswith("@use 'mastodon/") and "tokens/theme/" not in line:
            sys.exit(
                f"{name}: テーマブロックの切り出しに失敗した（base の途中で切れている）。\n"
                f"  切り出し位置: {i + 1} 行目 / 先頭の残り: {line}\n"
                "  --prev <前タグ> を付けて再実行する。"
            )
        break
    return tail


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--write", action="store_true", help="書き戻す（既定は確認だけ）")
    ap.add_argument("--prev", metavar="TAG", help="前の版のタグ")
    args = ap.parse_args()

    themes = read_themes()
    if not themes:
        sys.exit(f"config/themes.yml にテーマの登録が無い: {THEMES_YML}")

    base = APPLICATION.read_text().rstrip("\n")
    base_lines = base.split("\n")
    prev_lines = old_base_lines(args.prev) if args.prev else None

    # 1. themes.yml の登録とファイルの突き合わせ
    problems = []
    for name, rel in sorted(themes.items()):
        if not (ROOT / "app" / "javascript" / rel).exists():
            problems.append(f"登録されているがファイルが無い: {name} -> {rel}")
    registered = {pathlib.PurePosixPath(r).name for r in themes.values()}
    for path in sorted(STYLES.glob("*.scss")):
        if path.name != "application.scss" and path.name not in registered:
            problems.append(f"ファイルがあるが themes.yml に登録が無い: {path.name}")
    if problems:
        print("=== config/themes.yml と実ファイルの不一致 ===")
        for p in problems:
            print(f"  🔴 {p}")
        return 1

    # 2. 再同期
    changed, unchanged = [], []
    for name, rel in sorted(themes.items()):
        path = ROOT / "app" / "javascript" / rel
        lines = path.read_text().rstrip("\n").split("\n")
        fork = "\n".join(split_fork_block(lines, base_lines, prev_lines, name)).rstrip("\n")
        new = base + "\n" + fork + "\n"
        if new == path.read_text():
            unchanged.append(name)
            continue
        changed.append(name)
        if args.write:
            path.write_text(new)

    print(f"対象テーマ（themes.yml 由来）: {', '.join(sorted(themes))}")
    if changed:
        verb = "再同期した" if args.write else "再同期が要る"
        print(f"{verb}: {', '.join(changed)}")
    if unchanged:
        print(f"変更なし: {', '.join(unchanged)}")
    if changed and not args.write:
        print("\n--write を付けて書き戻す。")

    # 3. 4.7 で踏んだリネームの残存
    stale = [
        f"{path.name}:{i}: {line.strip()}"
        for path in sorted(STYLES.glob("*.scss"))
        for i, line in enumerate(path.read_text().splitlines(), 1)
        if "mastodon/theme/" in line
    ]
    if stale:
        print("\n🔴 mastodon/theme/ の参照が残っている（4.7 で tokens/theme/ へ移動）:")
        for s in stale:
            print(f"  {s}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
