#!/usr/bin/env python3
"""1つの試験の配信パックを作る(DDD-P2 P2-S02)。

使い方:
    SOURCE_DATE_EPOCH=<秒> python content/scripts/build_pack.py --exam <examID> --version <X.Y.Z>
        --min-app-version <X.Y.Z> --key-id <ID> [--root content] [--config <validation.yaml>] --out <出力先>

出力: <出力先>/<examID>/<version>/(manifest.sig は作らない。署名は sign_manifest.py が行う)
終了コード: 0 = 成功 / 1 = コンテンツの検証で error がある / 2 = 引数・環境の不備、出力先がすでにある
"""

from __future__ import annotations

import argparse
import os
import sys
from collections.abc import Sequence
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from contentpack.build import BuildError, ContentInvalid, build_pack  # noqa: E402
from contentvalidate.report import format_text  # noqa: E402

# 既定のコンテンツルート(このスクリプトから見た content/)。実行場所に依存しない
DEFAULT_ROOT = Path(__file__).resolve().parents[1]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="配信パックを作る")
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT, help="コンテンツのルート(既定: このスクリプトの親の content/)")
    parser.add_argument("--config", type=Path, default=None, help="設定ファイル(既定: <root>/validation.yaml)")
    parser.add_argument("--exam", required=True, help="試験 ID")
    parser.add_argument("--version", required=True, help="パックの版(SemVer)")
    parser.add_argument("--min-app-version", required=True, help="パックを読める最初のアプリの版(SemVer)")
    parser.add_argument("--key-id", required=True, help="署名に使う鍵の ID")
    parser.add_argument("--out", type=Path, required=True, help="出力先(<out>/<examID>/<version>/ を作る)")
    return parser


def _epoch() -> int | None:
    value = os.environ.get("SOURCE_DATE_EPOCH", "")
    return int(value) if value.isdecimal() else None


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    epoch = _epoch()
    if epoch is None:
        print("error: 環境変数 SOURCE_DATE_EPOCH(0 以上の整数の秒)が必要です", file=sys.stderr)
        return 2
    try:
        built = build_pack(
            args.root, args.exam, args.version, args.min_app_version, args.key_id, args.out, epoch, config_path=args.config
        )
    except BuildError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    except ContentInvalid as e:
        sys.stderr.write(format_text(e.issues))
        print(f"error: {e}", file=sys.stderr)
        return 1
    if built.warnings:
        sys.stderr.write(format_text(built.warnings))
    print(f"{built.path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
