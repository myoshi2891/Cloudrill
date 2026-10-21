"""loader.load_content の試験ディレクトリ(exams/<examID>/)の走査。"""

from __future__ import annotations

from pathlib import Path

from contentvalidate.loader import load_content
from contentvalidate.model import Kind, Severity


def _write(root: Path, rel: str, text: str = "{}\n") -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _exam(root: Path, exam_id: str) -> None:
    """必須ファイルだけを持つ試験ディレクトリを作る(中身の妥当性は問わない)。"""
    for name in ("exam.yaml", "exam-sets.yaml"):
        _write(root, f"exams/{exam_id}/{name}")


def _errors(root: Path) -> list[tuple[str, str, str]]:
    return [(i.rule, i.file, i.message) for i in load_content(root).issues if i.severity is Severity.ERROR]


def test_loader_two_exams_assigns_exam_id(tmp_path: Path) -> None:
    # Arrange
    _write(tmp_path, "vendors.yaml")
    for exam_id in ("a", "b"):
        _exam(tmp_path, exam_id)
        _write(tmp_path, f"exams/{exam_id}/questions/domain1/Q-1.1-0001.yaml")
    # Act
    docs = load_content(tmp_path).docs
    # Assert
    questions = [d for d in docs if d.kind is Kind.QUESTION]
    assert [(d.exam_id, d.path) for d in questions] == [
        ("a", "exams/a/questions/domain1/Q-1.1-0001.yaml"),
        ("b", "exams/b/questions/domain1/Q-1.1-0001.yaml"),
    ]


def test_loader_vendors_is_global(tmp_path: Path) -> None:
    # Arrange
    _write(tmp_path, "vendors.yaml")
    _exam(tmp_path, "a")
    # Act
    docs = load_content(tmp_path).docs
    # Assert
    vendors = [d for d in docs if d.path == "vendors.yaml"]
    assert len(vendors) == 1
    assert vendors[0].kind is Kind.VENDORS
    assert vendors[0].exam_id is None


def test_loader_missing_exam_yaml_is_reported(tmp_path: Path) -> None:
    # Arrange
    _write(tmp_path, "vendors.yaml")
    _exam(tmp_path, "a")
    (tmp_path / "exams/a/exam.yaml").unlink()
    # Act
    errors = _errors(tmp_path)
    # Assert
    assert ("CI-01", "exams/a/exam.yaml", "必須ファイル exam.yaml がありません") in errors


def test_loader_missing_vendors_is_reported(tmp_path: Path) -> None:
    # Arrange
    _exam(tmp_path, "a")
    # Act
    errors = _errors(tmp_path)
    # Assert
    assert errors == [("CI-01", "vendors.yaml", "必須ファイル vendors.yaml がありません")]


def test_loader_no_exams_is_reported(tmp_path: Path) -> None:
    # Arrange
    _write(tmp_path, "vendors.yaml")
    (tmp_path / "exams").mkdir()
    # Act
    errors = _errors(tmp_path)
    # Assert
    assert [(rule, file) for rule, file, _ in errors] == [("CI-01", "exams")]
    assert "試験がありません" in errors[0][2]


def test_loader_ignores_exam_validation_yaml(tmp_path: Path) -> None:
    # Arrange
    _write(tmp_path, "vendors.yaml")
    _exam(tmp_path, "a")
    _write(tmp_path, "exams/a/validation.yaml", "answerPosition: {}\n")
    # Act
    result = load_content(tmp_path)
    # Assert
    assert all(not d.path.endswith("validation.yaml") for d in result.docs)
    assert result.issues == []


def test_loader_paths_are_relative_to_root(tmp_path: Path) -> None:
    # Arrange
    _write(tmp_path, "vendors.yaml")
    _exam(tmp_path, "a")
    _write(tmp_path, "exams/a/questions/domain1/Q-1.1-0001.yaml")
    # Act
    docs = load_content(tmp_path).docs
    # Assert
    exam_docs = sorted((d.kind, d.path) for d in docs if d.exam_id == "a")
    assert exam_docs == sorted([
        (Kind.EXAM, "exams/a/exam.yaml"),
        (Kind.EXAM_SETS, "exams/a/exam-sets.yaml"),
        (Kind.QUESTION, "exams/a/questions/domain1/Q-1.1-0001.yaml"),
    ])
