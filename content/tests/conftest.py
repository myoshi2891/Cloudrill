"""共通 fixture: valid のコピーに invalid overlay を適用した一時ディレクトリを作る。"""

from __future__ import annotations

import shutil
from pathlib import Path
from typing import Any

import httpx
import pytest
import yaml

from pcavalidate.config import Config, load_config

REPO = Path(__file__).resolve().parents[1]
FIXTURES = REPO / "tests" / "fixtures"
VALID = FIXTURES / "valid"
INVALID = FIXTURES / "invalid"
_META_FILES = frozenset({"expected.yaml", "_delete.txt"})


def invalid_cases() -> list[str]:
    return sorted(p.name for p in INVALID.iterdir() if p.is_dir())


def read_expected(case: str) -> dict[str, Any]:
    return yaml.safe_load((INVALID / case / "expected.yaml").read_text(encoding="utf-8"))


def materialize(case: str | None, dest: Path) -> Path:
    """valid を dest にコピーし、case の overlay(追加・上書き・削除)を適用する。"""
    root = dest / "content"
    shutil.copytree(VALID, root)
    if case is None:
        return root
    overlay = INVALID / case
    delete_list = overlay / "_delete.txt"
    if delete_list.is_file():
        for line in delete_list.read_text(encoding="utf-8").splitlines():
            if line.strip():
                (root / line.strip()).unlink()
    for file in sorted(overlay.rglob("*")):
        if file.is_file() and file.name not in _META_FILES:
            target = root / file.relative_to(overlay)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(file, target)
    return root


def link_handler(request: httpx.Request) -> httpx.Response:
    """リンク確認用のモック。ネットワークには出ない。"""
    host = request.url.host
    if host == "broken.invalid":
        return httpx.Response(404)
    if host == "head-405.invalid":
        return httpx.Response(405 if request.method == "HEAD" else 200)
    if host == "timeout.invalid":
        raise httpx.ConnectTimeout("timed out", request=request)
    return httpx.Response(200)


@pytest.fixture(scope="session")
def config() -> Config:
    return load_config(REPO / "validation.yaml")


@pytest.fixture
def mock_transport() -> httpx.MockTransport:
    return httpx.MockTransport(link_handler)
