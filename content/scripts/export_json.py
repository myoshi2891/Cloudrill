#!/usr/bin/env python3
"""YAML コンテンツを JSON に変換する(Swift の Codable テスト用 fixture の生成)。

    python content/scripts/export_json.py [--src content/tests/fixtures/valid]
                                          [--out content/tests/fixtures/valid-json]

出力は packages/DomainModels の Swift テストが直接参照する(パッケージ内にはコピーしない)。

YAML は validate.py と同じ読み込み処理(キーの文字列化など)で JSON 相当にしてから書き出す。
docs/*.md は Swift 側にモデルがないため対象外。
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from collections.abc import Sequence
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from contentvalidate.loader import YamlLoadError, parse_yaml  # noqa: E402

CONTENT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = CONTENT_ROOT / "tests/fixtures/valid"
DEFAULT_OUT = CONTENT_ROOT / "tests/fixtures/valid-json"


def export(src: Path, out: Path) -> list[Path]:
    """src 配下の *.yaml を out 配下の同じ相対パス(拡張子 .json)に書き出す。out は作り直す。"""
    shutil.rmtree(out, ignore_errors=True)
    written: list[Path] = []
    for file in sorted(src.rglob("*.yaml")):
        data, _, _ = parse_yaml(file.read_text(encoding="utf-8"))
        target = out / file.relative_to(src).with_suffix(".json")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        written.append(target)
    return written


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="YAML コンテンツを JSON に変換する")
    parser.add_argument("--src", type=Path, default=DEFAULT_SRC)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args(argv)
    try:
        written = export(args.src, args.out)
    except YamlLoadError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    print(f"{len(written)} files → {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
