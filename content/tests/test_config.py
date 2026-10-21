"""validation.yaml の階層化(全体 + 試験ごと)。"""

from __future__ import annotations

import copy
import shutil
from pathlib import Path
from typing import Any

import pytest
import yaml

from conftest import VALID
from contentvalidate.config import ConfigError, GlobalConfig, load_config, load_exam_config
from validate import main

# 全体の validation.yaml の最小構成(試験ごとの項目 examSet・examGuide は持たない)
BASE_GLOBAL: dict[str, Any] = {
    "version": 1,
    "statistics": {"draftMinSample": 20},
    "answerPosition": {"positions": 4, "minRatio": 0.20, "maxRatio": 0.30},
    "longestChoice": {"maxRatio": 0.35, "countTies": True},
    "similarity": {"ngram": 3, "jaccardThreshold": 0.8},
    "weights": {"expectedSum": 1.0, "tolerance": 0.001},
    "links": {"timeoutSeconds": 10, "concurrency": 8, "userAgent": "ua", "retryWithGetOn": [405]},
}

EXAM_SET: dict[str, Any] = {
    "domainDistribution": {"1": 14, "5+6": 13},
    "caseQuestions": {"min": 12, "max": 15},
    "defaultAssignments": {"1": {"caseStudies": ["ehr", "altostrat"], "level": "basic"}},
}


def _write(path: Path, data: dict[str, Any]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")
    return path


def _global(tmp_path: Path, overrides: dict[str, Any] | None = None) -> GlobalConfig:
    raw = copy.deepcopy(BASE_GLOBAL)
    raw.update(overrides or {})
    return load_config(_write(tmp_path / "validation.yaml", raw))


def _exam_dir(tmp_path: Path, exam: dict[str, Any] | None) -> Path:
    exam_dir = tmp_path / "exams" / "a"
    exam_dir.mkdir(parents=True, exist_ok=True)
    if exam is not None:
        _write(exam_dir / "validation.yaml", exam)
    return exam_dir


def test_exam_config_overrides_global_threshold(tmp_path: Path) -> None:
    # Arrange
    global_config = _global(tmp_path)
    exam_dir = _exam_dir(tmp_path, {"answerPosition": {"maxRatio": 0.35}})
    # Act
    config = load_exam_config(global_config, exam_dir)
    # Assert
    assert global_config.thresholds.position_max == 0.30
    assert config.thresholds.position_max == 0.35
    assert config.thresholds.position_min == 0.20
    assert config.exam_id == "a"


def test_exam_config_merges_nested_mapping(tmp_path: Path) -> None:
    exam_dir = _exam_dir(tmp_path, {"longestChoice": {"maxRatio": 0.40}})
    config = load_exam_config(_global(tmp_path), exam_dir)
    assert config.thresholds.longest_max == 0.40
    assert config.thresholds.longest_count_ties is True


def test_exam_config_replaces_list(tmp_path: Path) -> None:
    exam_dir = _exam_dir(tmp_path, {"links": {"retryWithGetOn": [405, 403]}})
    config = load_exam_config(_global(tmp_path), exam_dir)
    assert config.thresholds.link_retry_get_on == frozenset({405, 403})


def test_exam_config_without_exam_set_policy(tmp_path: Path) -> None:
    # 試験の validation.yaml 自体がない場合も、全体の値だけで設定を作る
    config = load_exam_config(_global(tmp_path), _exam_dir(tmp_path, None))
    assert config.exam_set_policy is None


def test_exam_config_reads_exam_set_policy(tmp_path: Path) -> None:
    config = load_exam_config(_global(tmp_path), _exam_dir(tmp_path, {"examSet": EXAM_SET}))
    policy = config.exam_set_policy
    assert policy is not None
    assert policy.domain_distribution == (((1,), 14), ((5, 6), 13))
    assert (policy.case_min, policy.case_max) == (12, 15)
    assert policy.default_assignments[1].case_studies == frozenset({"ehr", "altostrat"})


def test_exam_config_domain_key_accepts_any_positive_int(tmp_path: Path) -> None:
    exam_set = {**EXAM_SET, "domainDistribution": {"7": 3}}
    config = load_exam_config(_global(tmp_path), _exam_dir(tmp_path, {"examSet": exam_set}))
    assert config.exam_set_policy is not None
    assert config.exam_set_policy.domain_distribution == (((7,), 3),)


def test_exam_config_rejects_zero_domain(tmp_path: Path) -> None:
    exam_set = {**EXAM_SET, "domainDistribution": {"0": 3}}
    with pytest.raises(ConfigError):
        load_exam_config(_global(tmp_path), _exam_dir(tmp_path, {"examSet": exam_set}))


@pytest.mark.parametrize(
    "exam",
    [
        {"answerPositon": {"maxRatio": 0.35}},  # セクション名の typo
        {"answerPosition": {"maxRaito": 0.35}},  # セクション内のキーの typo
        {"examSet": {**EXAM_SET, "questionCount": 55}},  # exam.yaml に移した項目
    ],
)
def test_exam_config_rejects_unknown_key(tmp_path: Path, exam: dict[str, Any]) -> None:
    with pytest.raises(ConfigError):
        load_exam_config(_global(tmp_path), _exam_dir(tmp_path, exam))


def test_exam_config_rejects_bool_as_number(tmp_path: Path) -> None:
    exam_dir = _exam_dir(tmp_path, {"answerPosition": {"maxRatio": True}})
    with pytest.raises(ConfigError):
        load_exam_config(_global(tmp_path), exam_dir)


@pytest.mark.parametrize(("key", "message"), [("examGuide", "exam.yaml"), ("examSet", "試験ごと")])
def test_global_config_rejects_exam_sections(tmp_path: Path, key: str, message: str) -> None:
    with pytest.raises(ConfigError, match=message):
        _global(tmp_path, {key: {}})


def test_cli_bad_exam_config_exits_2(tmp_path: Path) -> None:
    # Arrange
    root = tmp_path / "content"
    shutil.copytree(VALID, root)
    _write(root / "exams" / "test-alpha" / "validation.yaml", {"answerPositon": {}})
    # Act / Assert
    assert main(["--root", str(root)]) == 2
