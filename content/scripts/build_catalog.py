#!/usr/bin/env python3
"""カタログを生成する。SOURCE_DATE_EPOCH 必須。成功 0 / 入力・I/O の不備 2。"""

import argparse
import os
import sys
from pathlib import Path

from contentpack.files import atomic_write, canonical_json
from contentpack.catalog import CatalogError, build_catalog

DEFAULT_ROOT = Path(__file__).resolve().parents[1]


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="配信カタログを生成する")
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--previous", type=Path)
    parser.add_argument("--update", action="append", nargs="+", default=[], metavar="EXAM=MANIFEST")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        value = os.environ.get("SOURCE_DATE_EPOCH", "")
        if not value.isdecimal():
            raise CatalogError("環境変数 SOURCE_DATE_EPOCH(0 以上の整数の秒)が必要です")
        updates = {}
        for group in args.update:
            for update in group:
                exam_id, separator, path = update.partition("=")
                if not separator or not exam_id or not path or exam_id in updates:
                    raise CatalogError("--update は重複のない EXAM=MANIFEST で指定してください")
                updates[exam_id] = Path(path)
        catalog = build_catalog(args.root, epoch=int(value), previous=args.previous, updates=updates)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        atomic_write(args.out, canonical_json(catalog))
    except (ValueError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
