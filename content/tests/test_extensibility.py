"""拡張性の受け入れテスト: 形の違う試験(test-beta)を、検証ツールのコードを変えずに扱えること。"""

from __future__ import annotations

import ast
from pathlib import Path

import pytest

from conftest import CONTENT_ROOT, VALID
from contentvalidate.config import GlobalConfig
from contentvalidate.context import build_context
from contentvalidate.engine import run
from contentvalidate.loader import exam_dirs

VALIDATOR = CONTENT_ROOT / "scripts" / "contentvalidate"
# 検証ツールのコードに書いてはいけない、試験固有の値
EXAM_SPECIFIC = ("gcp-pca", "test-alpha", "test-beta", "ehr", "altostrat", "cymbal", "knightMotives")
EXAM_IDS = [d.name for d in exam_dirs(VALID)]


def test_valid_fixture_has_two_differently_shaped_exams() -> None:
    assert EXAM_IDS == ["test-alpha", "test-beta"]


@pytest.mark.parametrize("exam_id", EXAM_IDS)
def test_each_exam_fixture_is_validated(exam_id: str, config: GlobalConfig) -> None:
    # Arrange
    exam_ids = frozenset({exam_id})
    ctx = build_context(VALID, config, exam_ids=exam_ids)
    # Act
    issues = run(VALID, config, exam_ids=exam_ids)
    # Assert: 違反がなく、試験定義を読めていて、模試が 1 つ以上検査の対象になっている
    assert issues == []
    [exam] = ctx.exams
    assert exam.definition is not None
    assert sum(len(sets) for _, sets in exam.exam_sets) >= 1


def _string_constants(path: Path) -> list[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    return [node.value for node in ast.walk(tree) if isinstance(node, ast.Constant) and isinstance(node.value, str)]


def test_validator_has_no_exam_specific_literals() -> None:
    # Arrange
    sources = sorted(VALIDATOR.rglob("*.py"))
    assert sources
    # Act
    found = [
        (path.relative_to(VALIDATOR).as_posix(), word)
        for path in sources
        for value in _string_constants(path)
        for word in EXAM_SPECIFIC
        if word in value
    ]
    # Assert: 試験ごとの値は exam.yaml と validation.yaml に置き、コードには書かない
    assert found == []


def test_same_id_in_other_exam_is_allowed(config: GlobalConfig) -> None:
    # Arrange: 2 つの試験に同じ問題 ID がある(どちらも Q-<サブ項目>-<連番> で採番するため)
    alpha = {p.name for p in (VALID / "exams/test-alpha/questions").rglob("*.yaml")}
    beta = {p.name for p in (VALID / "exams/test-beta/questions").rglob("*.yaml")}
    assert alpha & beta
    # Act / Assert: ID の一意性は試験の中だけで確認する(CI-07)
    assert run(VALID, config, only={"CI-07"}) == []
