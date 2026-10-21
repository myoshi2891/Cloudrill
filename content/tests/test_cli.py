"""CLI(終了コードと出力形式)のテスト。"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

from conftest import CONTENT_ROOT, VALID, copy_exam, materialize
from contentvalidate.config import load_config
from contentvalidate.model import Issue, Severity
from contentvalidate.report import format_github
from validate import main

GITHUB_LINE = re.compile(r"^::(error|warning) file=[^,]+(,line=\d+)?,title=CI-\d{2}::\[CI-\d{2}\] .+$")


def test_exit_code_zero_for_valid(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["--root", str(VALID)]) == 0
    assert "集計: error 0 件, warning 0 件" in capsys.readouterr().out


def test_exit_code_one_on_error(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    root = materialize("CI-10-weights-sum", tmp_path)
    assert main(["--root", str(root)]) == 1
    out = capsys.readouterr().out
    assert re.search(r"^exams/test-alpha/exam\.yaml:\d+: \[CI-10\] error: ", out, re.MULTILINE)
    assert "  CI-10 error: 1" in out


def test_warning_only_exits_zero_unless_strict(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    root = materialize("CI-11-missing-en", tmp_path)
    assert main(["--root", str(root)]) == 0
    assert main(["--root", str(root), "--strict"]) == 1


def test_json_format(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    root = materialize("CI-08-count-mismatch", tmp_path)
    assert main(["--root", str(root), "--format", "json"]) == 1
    data = json.loads(capsys.readouterr().out)
    assert len(data) == 1
    assert set(data[0]) == {"rule", "severity", "file", "line", "message"}
    assert data[0]["rule"] == "CI-08" and data[0]["severity"] == "error"
    assert isinstance(data[0]["line"], int)


def test_json_format_empty_list_for_valid(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["--root", str(VALID), "--format", "json"]) == 0
    assert json.loads(capsys.readouterr().out) == []


def test_github_format(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    root = materialize("CI-02-case-mismatch", tmp_path)
    assert main(["--root", str(root), "--format", "github"]) == 1
    lines = capsys.readouterr().out.splitlines()
    assert lines and all(GITHUB_LINE.match(line) for line in lines), lines


def test_github_escaping() -> None:
    issue = Issue("a,b:c.yaml", 3, "CI-01", Severity.ERROR, "100% 確認\n次の行")
    assert format_github([issue]) == "::error file=a%2Cb%3Ac.yaml,line=3,title=CI-01::[CI-01] 100%25 確認%0A次の行\n"


def test_only_option(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    root = materialize("CI-10-weights-sum", tmp_path)
    assert main(["--root", str(root), "--only", "ci-01,CI-02"]) == 0


def test_unknown_rule_in_only_exits_two(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc:
        main(["--only", "CI-99"])
    assert exc.value.code == 2


def test_cli_exam_option_limits_exams(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    # Arrange: test-gamma にだけ違反(英語訳の欠落)がある
    root = materialize(None, tmp_path)
    gamma = copy_exam(root, "test-gamma")
    question = gamma / "questions/domain2/Q-2.2-0101.yaml"
    question.write_text(question.read_text(encoding="utf-8").replace("  en: ", "  en_removed: ", 1), encoding="utf-8")
    assert main(["--root", str(root), "--format", "json"]) == 1
    capsys.readouterr()
    # Act
    code = main(["--root", str(root), "--exam", "test-alpha", "--format", "json"])
    # Assert
    files = {issue["file"] for issue in json.loads(capsys.readouterr().out)}
    assert code == 0
    assert not any(f.startswith("exams/test-gamma/") for f in files)


def test_cli_unknown_exam_exits_2(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["--root", str(VALID), "--exam", "nope"]) == 2
    assert "nope" in capsys.readouterr().err


def test_missing_root_exits_two(tmp_path: Path) -> None:
    assert main(["--root", str(tmp_path / "missing")]) == 2


def test_broken_config_exits_two(tmp_path: Path) -> None:
    config = tmp_path / "validation.yaml"
    config.write_text("version: 1\n", encoding="utf-8")
    assert main(["--root", str(VALID), "--config", str(config)]) == 2


def test_script_runs_as_subprocess() -> None:
    result = subprocess.run(
        [sys.executable, "scripts/validate.py", "--root", "tests/fixtures/valid", "--format", "github"],
        cwd=CONTENT_ROOT, capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == ""


def test_repository_content_has_no_errors(capsys: pytest.CaptureFixture[str]) -> None:
    # リポジトリ直下のサンプルコンテンツ(draft の模試の warning は許容)
    assert main(["--root", str(CONTENT_ROOT)]) == 0


def test_default_root_is_content_dir_regardless_of_cwd(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    # 無関係なディレクトリから実行しても、既定の --root は content/ になる
    monkeypatch.chdir(tmp_path)
    assert main(["--format", "json"]) == 0
    files = {issue["file"] for issue in json.loads(capsys.readouterr().out)}
    assert files <= {"exams/gcp-pca/exam-sets.yaml"}


def test_github_paths_are_relative_to_workspace(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    # CI では working-directory が content/ でも、アノテーションはリポジトリルート基準にする
    monkeypatch.setenv("GITHUB_WORKSPACE", str(CONTENT_ROOT.parent))
    monkeypatch.chdir(CONTENT_ROOT)
    main(["--format", "github"])
    lines = capsys.readouterr().out.splitlines()
    assert lines and all("file=content/" in line for line in lines)


def test_link_check_user_agent() -> None:
    # 接尾辞(連絡先)は任意。名称がブランド名ではなく examprep であることだけを確認する
    config = load_config(CONTENT_ROOT / "validation.yaml")
    assert config.thresholds.link_user_agent.startswith("examprep-content-link-check/1.0")
