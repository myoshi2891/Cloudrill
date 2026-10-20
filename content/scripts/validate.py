#!/usr/bin/env python3
"""pca-content のコンテンツ検証(CI-01〜CI-11)。

使い方:
    python scripts/validate.py [--root .] [--check-links] [--strict]
                               [--format text|json|github] [--only CI-02,CI-03]

終了コード: 0 = error なし / 1 = error あり(--strict では warning も含む)/ 2 = 引数・設定の不備
"""

from __future__ import annotations

import argparse
import os
import sys
from collections.abc import Sequence
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pcavalidate.config import ConfigError, load_config, resolve_config_path  # noqa: E402
from pcavalidate.engine import exit_code, run  # noqa: E402
from pcavalidate.report import format_github, format_json, format_text  # noqa: E402
from pcavalidate.rules import RULE_IDS  # noqa: E402


def _parse_only(value: str) -> frozenset[str]:
    ids = frozenset(v.strip().upper() for v in value.split(",") if v.strip())
    unknown = ids - RULE_IDS
    if unknown:
        raise argparse.ArgumentTypeError(f"不明なルール ID: {', '.join(sorted(unknown))}")
    return ids


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="pca-content のコンテンツを検証する")
    parser.add_argument("--root", type=Path, default=Path("."), help="コンテンツのルート(既定: .)")
    parser.add_argument("--config", type=Path, default=None, help="設定ファイル(既定: <root>/validation.yaml)")
    parser.add_argument("--check-links", action="store_true", help="CI-06(リンク切れ確認)を実行する")
    parser.add_argument("--strict", action="store_true", help="warning も error として扱う")
    parser.add_argument("--format", choices=("text", "json", "github"), default="text")
    parser.add_argument("--only", type=_parse_only, default=None, help="実行するルール ID(カンマ区切り)")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root: Path = args.root
    if not root.is_dir():
        print(f"error: --root {root} はディレクトリではありません", file=sys.stderr)
        return 2
    try:
        config = load_config(resolve_config_path(root, args.config))
    except ConfigError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    issues = run(root, config, only=args.only, check_links=args.check_links, strict=args.strict)

    if args.format == "json":
        sys.stdout.write(format_json(issues))
    elif args.format == "github":
        prefix = os.path.relpath(root.resolve(), Path.cwd())
        sys.stdout.write(format_github(issues, "" if prefix == "." else f"{Path(prefix).as_posix()}/"))
    else:
        sys.stdout.write(format_text(issues))
    return exit_code(issues)


if __name__ == "__main__":
    sys.exit(main())
