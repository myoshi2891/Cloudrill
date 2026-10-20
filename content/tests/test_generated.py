"""コミット済みの生成物(fixture と Swift 用 JSON)が、生成スクリプトの出力と一致すること。"""

from __future__ import annotations

from pathlib import Path

from conftest import FIXTURES, VALID
from export_json import DEFAULT_OUT, export
from generate import generate


def _tree(base: Path) -> dict[str, bytes]:
    return {p.relative_to(base).as_posix(): p.read_bytes() for p in sorted(base.rglob("*")) if p.is_file()}


def test_fixtures_are_up_to_date(tmp_path: Path) -> None:
    generate(tmp_path)
    for name in ("valid", "invalid"):
        assert _tree(tmp_path / name) == _tree(FIXTURES / name), (
            f"content/tests/fixtures/{name} が古くなっています。python content/tests/fixtures/generate.py を実行してください"
        )


def test_swift_fixtures_are_up_to_date(tmp_path: Path) -> None:
    export(VALID, tmp_path / "out")
    assert _tree(tmp_path / "out") == _tree(DEFAULT_OUT), (
        "Swift 用 JSON が古くなっています。python content/scripts/export_json.py を実行してください"
    )
    assert DEFAULT_OUT == FIXTURES / "valid-json"
