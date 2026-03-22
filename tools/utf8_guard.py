#!/usr/bin/env python3
import argparse
import os
import sys
import unicodedata
from pathlib import Path

TEXT_EXTENSIONS = {
    ".dart",
    ".md",
    ".txt",
    ".yaml",
    ".yml",
    ".json",
    ".sql",
    ".xml",
    ".html",
    ".htm",
    ".js",
    ".ts",
    ".gradle",
    ".kts",
    ".properties",
    ".kt",
    ".java",
    ".ps1",
    ".sh",
}

EXCLUDED_DIRS = {
    ".git",
    ".dart_tool",
    "build",
    "node_modules",
    "dist",
    "Pods",
    ".idea",
    ".next",
    "out",
}

MOJIBAKE_MARKERS = [
    "Ã",
    "â€",
    "â€™",
    "â€œ",
    "â€\x9d",
    "â€“",
    "â€”",
    "ðŸ",
    "�",
    "Ä\x87",
    "Ä\x8d",
    "Ä‘",
    "Å¡",
    "Å¾",
    "Ä†",
    "ÄŒ",
    "Ä\x90",
    "Å ",
    "Å½",
]

REPLACEMENTS = {
    "Ä\x87": "ć",
    "Ä\x8d": "č",
    "Ä‘": "đ",
    "Å¡": "š",
    "Å¾": "ž",
    "Ä†": "Ć",
    "ÄŒ": "Č",
    "Ä\x90": "Đ",
    "Å ": "Š",
    "Å½": "Ž",
    "â€”": "—",
    "â€“": "–",
    "â€™": "’",
    "â€œ": "“",
    "â€\x9d": "”",
    "â€¢": "•",
    "â„¢": "™",
    "Â": "",
}


def should_scan_file(path: Path) -> bool:
    if not path.is_file():
        return False
    return path.suffix.lower() in TEXT_EXTENSIONS


def iter_files(root: Path):
    for current_root, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
        for filename in files:
            path = Path(current_root) / filename
            if should_scan_file(path):
                yield path


def fix_text(text: str) -> str:
    fixed = text
    for bad, good in REPLACEMENTS.items():
        fixed = fixed.replace(bad, good)
    fixed = unicodedata.normalize("NFC", fixed)
    return fixed


def scan_file(path: Path, root: Path, fix: bool):
    rel = path.relative_to(root)
    issues = []
    changed = False

    raw = path.read_bytes()
    has_bom = raw.startswith(b"\xef\xbb\xbf")
    if has_bom:
        issues.append("BOM")

    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        issues.append(f"INVALID_UTF8:{exc.start}")
        return str(rel), issues, changed

    if any(marker in text for marker in MOJIBAKE_MARKERS):
        issues.append("MOJIBAKE")

    fixed_text = text
    if fix:
        fixed_text = fix_text(text)

    if fixed_text != text or has_bom:
        changed = True
        if fix:
            path.write_text(fixed_text, encoding="utf-8", newline="\n")

    if fix:
        reissues = []
        new_raw = path.read_bytes() if changed else raw
        if new_raw.startswith(b"\xef\xbb\xbf"):
            reissues.append("BOM")
        try:
            new_text = new_raw.decode("utf-8")
            if any(marker in new_text for marker in MOJIBAKE_MARKERS):
                reissues.append("MOJIBAKE")
        except UnicodeDecodeError as exc:
            reissues.append(f"INVALID_UTF8:{exc.start}")
        issues = reissues

    return str(rel), issues, changed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="UTF-8 / mojibake guard for repository text files"
    )
    parser.add_argument(
        "--path", default=".", help="Root path to scan (default: current directory)"
    )
    parser.add_argument(
        "--fix",
        action="store_true",
        help="Attempt safe fixes (remove BOM, normalize UTF-8, basic mojibake replacements)",
    )
    args = parser.parse_args()

    root = Path(args.path).resolve()
    if not root.exists():
        print(f"Path does not exist: {root}")
        return 2

    total = 0
    changed = 0
    problematic = 0

    for file_path in iter_files(root):
        total += 1
        rel, issues, was_changed = scan_file(file_path, root, args.fix)
        if was_changed and args.fix:
            changed += 1
        if issues:
            problematic += 1
            print(f"[ISSUE] {rel} -> {', '.join(issues)}")

    mode = "FIX" if args.fix else "CHECK"
    print(f"\n[{mode}] scanned={total} problematic={problematic} changed={changed}")
    return 1 if problematic > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
