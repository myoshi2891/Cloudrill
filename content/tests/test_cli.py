"""CLI(終了コードと出力形式)のテスト。"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

from conftest import REPO, VALID, materialize
from pcavalidate.model import Issue, Severity
from pcavalidate.report import format_github
from validate import main

GITHUB_LINE = re.compile(r"^::(error|warning) file=[^,]+(,line=\d+)?,title=CI-\d{2}::\[CI-\d{2}\] .+$")


def test_exit_code_zero_for_valid(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["--root", str(VALID)]) == 0
    assert "集計: error 0 件, warning 0 件" in capsys.readouterr().out


def test_exit_code_one_on_error(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    root = materialize("CI-10-weights-sum", tmp_path)
    assert main(["--root", str(root)]) == 1
    out = capsys.readouterr().out
    assert re.search(r"^weights\.yaml:\d+: \[CI-10\] error: ", out, re.MULTILINE)
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


def test_missing_root_exits_two(tmp_path: Path) -> None:
    assert main(["--root", str(tmp_path / "missing")]) == 2


def test_broken_config_exits_two(tmp_path: Path) -> None:
    config = tmp_path / "validation.yaml"
    config.write_text("version: 1\n", encoding="utf-8")
    assert main(["--root", str(VALID), "--config", str(config)]) == 2


def test_script_runs_as_subprocess() -> None:
    result = subprocess.run(
        [sys.executable, "scripts/validate.py", "--root", "tests/fixtures/valid", "--format", "github"],
        cwd=REPO, capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == ""


def test_repository_content_has_no_errors(capsys: pytest.CaptureFixture[str]) -> None:
    # リポジトリ直下のサンプルコンテンツ(draft の模試の warning は許容)
    assert main(["--root", str(REPO)]) == 0
