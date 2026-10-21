"""ルールごとの検出テスト。"""

from __future__ import annotations

from collections import defaultdict
from pathlib import Path

import httpx
import pytest

from conftest import VALID, copy_exam, invalid_cases, link_handler, materialize, read_expected
from generate import ALPHA
from contentvalidate.config import GlobalConfig
from contentvalidate.engine import run
from contentvalidate.model import Issue
from contentvalidate.rules import RULE_IDS


def _by_rule(issues: list[Issue]) -> dict[str, list[str]]:
    result: dict[str, set[str]] = defaultdict(set)
    for issue in issues:
        result[issue.rule].add(str(issue.severity))
    return {rule: sorted(sev) for rule, sev in result.items()}


def test_valid_fixture_passes_all_rules(config: GlobalConfig, mock_transport: httpx.MockTransport) -> None:
    # Arrange: valid 一式(complete の模試 55 問を含む)
    # Act
    issues = run(VALID, config, check_links=True, transport=mock_transport)
    # Assert
    assert issues == []


def test_every_rule_has_an_invalid_case() -> None:
    covered = {rule for case in invalid_cases() for rule in read_expected(case)["expect"]}
    assert covered == RULE_IDS


@pytest.mark.parametrize("case", invalid_cases())
def test_invalid_case_detects_only_expected_rules(
    case: str, config: GlobalConfig, tmp_path: Path, mock_transport: httpx.MockTransport
) -> None:
    # Arrange
    expected = read_expected(case)
    root = materialize(case, tmp_path)
    check_links = bool(expected.get("options", {}).get("checkLinks", False))
    # Act
    issues = run(root, config, check_links=check_links, transport=mock_transport)
    # Assert
    assert _by_rule(issues) == {rule: sorted(sev) for rule, sev in expected["expect"].items()}, issues


def test_only_limits_rules(config: GlobalConfig, tmp_path: Path) -> None:
    root = materialize("CI-03-answer-position", tmp_path)
    assert run(root, config, only={"CI-01", "CI-04"}) == []
    assert {i.rule for i in run(root, config, only={"CI-03"})} == {"CI-03"}


def test_only_without_ci01_still_skips_schema_invalid_files(config: GlobalConfig, tmp_path: Path) -> None:
    # Schema 違反の問題は CI-01 を除外してもファイル間ルールの対象外のまま
    root = materialize("CI-01-schema-violation", tmp_path)
    assert run(root, config, only={"CI-02", "CI-07", "CI-11"}) == []


def test_strict_promotes_warnings(config: GlobalConfig, tmp_path: Path) -> None:
    root = materialize("CI-11-missing-en", tmp_path)
    issues = run(root, config, strict=True)
    assert issues and all(str(i.severity) == "error" for i in issues)


def test_issue_reports_line_number(config: GlobalConfig, tmp_path: Path) -> None:
    root = materialize("CI-10-weights-sum", tmp_path)
    lines = (root / ALPHA / "exam.yaml").read_text(encoding="utf-8").splitlines()
    [issue] = run(root, config)
    assert issue.file == f"{ALPHA}/exam.yaml"
    assert issue.line == lines.index("domains:") + 1


def test_yaml_syntax_error_has_line(config: GlobalConfig, tmp_path: Path) -> None:
    root = materialize("CI-01-yaml-syntax", tmp_path)
    [issue] = run(root, config)
    assert issue.line is not None and issue.line >= 2


def test_ci05_delegation_does_not_report_ci01(config: GlobalConfig, tmp_path: Path) -> None:
    root = materialize("CI-05-empty-rationale", tmp_path)
    issues = run(root, config)
    # Schema の minLength 違反(CI-01)と CI-05 の二重報告にならない
    assert [i.rule for i in issues] == ["CI-05"]


def test_link_check_retries_get_on_405_and_reports_timeout(config: GlobalConfig, tmp_path: Path, mock_transport: httpx.MockTransport) -> None:
    # Arrange: HEAD 405 → GET 200 の URL と、タイムアウトする URL
    root = materialize(None, tmp_path)
    q = root / ALPHA / "questions/domain2/Q-2.2-0101.yaml"
    text = q.read_text(encoding="utf-8").replace("https://cloud.google.com/docs", "https://head-405.invalid/page")
    q.write_text(text, encoding="utf-8")
    q2 = root / ALPHA / "questions/domain4/Q-4.1-0102.yaml"
    text2 = q2.read_text(encoding="utf-8").replace("https://cloud.google.com/docs", "https://timeout.invalid/page")
    q2.write_text(text2, encoding="utf-8")
    # Act
    issues = run(root, config, only={"CI-06"}, check_links=True, transport=mock_transport)
    # Assert
    assert [(i.rule, i.file) for i in issues] == [("CI-06", f"{ALPHA}/questions/domain4/Q-4.1-0102.yaml")]
    assert "タイムアウト" in issues[0].message


def test_link_check_is_skipped_without_flag(config: GlobalConfig, tmp_path: Path) -> None:
    root = materialize("CI-06-broken-link", tmp_path)
    assert run(root, config) == []


def test_missing_required_file_is_reported(config: GlobalConfig, tmp_path: Path) -> None:
    root = materialize(None, tmp_path)
    (root / ALPHA / "exam-sets.yaml").unlink()
    issues = run(root, config)
    assert [(i.rule, i.file) for i in issues] == [("CI-01", f"{ALPHA}/exam-sets.yaml")]


def test_duplicate_yaml_key_is_reported(config: GlobalConfig, tmp_path: Path) -> None:
    root = materialize(None, tmp_path)
    exam = root / ALPHA / "exam.yaml"
    exam.write_text(exam.read_text(encoding="utf-8") + "shortName: ALPHA\n", encoding="utf-8")
    issues = run(root, config)
    assert [i.rule for i in issues] == ["CI-01"]
    assert "重複" in issues[0].message


def test_same_ids_in_different_exams_are_allowed(config: GlobalConfig, tmp_path: Path) -> None:
    # Arrange: 中身が同じ 2 つの試験(問題 ID・カード ID・問題文がすべて同じ)
    root = materialize(None, tmp_path)
    copy_exam(root, "test-beta")
    # Act / Assert: 重複と類似は試験の中だけで確認する(CI-07)
    assert run(root, config) == []


def test_link_check_dedupes_across_exams(config: GlobalConfig, tmp_path: Path) -> None:
    # Arrange: 2 つの試験が同じ壊れた URL を参照する
    root = materialize("CI-06-broken-link", tmp_path)
    copy_exam(root, "test-beta")
    heads: list[str] = []

    def counting(request: httpx.Request) -> httpx.Response:
        if request.method == "HEAD":
            heads.append(str(request.url))
        return link_handler(request)

    # Act
    issues = run(root, config, only={"CI-06"}, check_links=True, transport=httpx.MockTransport(counting))
    # Assert: HEAD は URL ごとに 1 回で、検出結果は両方の試験に出る
    assert len(heads) == len(set(heads))
    assert {i.file.split("/")[1] for i in issues} == {"test-alpha", "test-beta"}


def test_rules_skip_when_exam_definition_invalid(config: GlobalConfig, tmp_path: Path) -> None:
    # Arrange: exam.yaml が Schema 違反(domains がない)
    root = materialize(None, tmp_path)
    exam = root / ALPHA / "exam.yaml"
    text = exam.read_text(encoding="utf-8")
    exam.write_text(text[: text.index("domains:")] + text[text.index("features:") :], encoding="utf-8")
    # Act
    issues = run(root, config)
    # Assert: 原因の CI-01 だけを報告し、試験定義を使うルールは何も報告しない
    assert {i.rule for i in issues} == {"CI-01"}
    assert {i.file for i in issues} == {f"{ALPHA}/exam.yaml"}
