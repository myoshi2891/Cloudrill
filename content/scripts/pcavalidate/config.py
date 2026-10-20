"""validation.yaml の読み込みと最低限の構造チェック。"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

DEFAULT_CONFIG_NAME = "validation.yaml"
# スクリプト同梱の既定設定(--root にない場合のフォールバック)
_BUNDLED_CONFIG = Path(__file__).resolve().parents[2] / DEFAULT_CONFIG_NAME


class ConfigError(Exception):
    """設定ファイルの不備。CLI は終了コード 2 で終了する。"""


@dataclass(frozen=True)
class DefaultAssignment:
    case_studies: frozenset[str]
    level: str


@dataclass(frozen=True)
class Config:
    question_count: int
    # (対象ドメインの組, 期待数)。例: ((5, 6), 13)
    domain_distribution: tuple[tuple[tuple[int, ...], int], ...]
    case_min: int
    case_max: int
    default_assignments: dict[int, DefaultAssignment]
    draft_min_sample: int
    position_count: int
    position_min: float
    position_max: float
    longest_max: float
    longest_count_ties: bool
    ngram: int
    jaccard_threshold: float
    weights_sum: float
    weights_tolerance: float
    link_timeout: float
    link_concurrency: int
    link_user_agent: str
    link_retry_get_on: frozenset[int]
    sub_objectives: frozenset[str]


def _section(raw: dict[str, Any], key: str) -> dict[str, Any]:
    value = raw.get(key)
    if not isinstance(value, dict):
        raise ConfigError(f"validation.yaml: '{key}' セクションがありません")
    return value


def _num(section: dict[str, Any], key: str, where: str) -> float:
    value = section.get(key)
    # bool は int のサブクラスなので明示的に除外する
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ConfigError(f"validation.yaml: {where}.{key} は数値で指定してください")
    return float(value)


def _int(section: dict[str, Any], key: str, where: str) -> int:
    value = section.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ConfigError(f"validation.yaml: {where}.{key} は整数で指定してください")
    return value


def _int_key(key: object, where: str) -> int:
    """YAML のキー("1" または 1)を整数に変換する。"""
    if isinstance(key, bool):
        raise ConfigError(f"validation.yaml: {where} のキー '{key}' は整数で指定してください")
    try:
        return int(str(key).strip())
    except ValueError as e:
        raise ConfigError(f"validation.yaml: {where} のキー '{key}' は整数で指定してください") from e


def _parse_domains(key: object) -> tuple[int, ...]:
    parts = str(key).split("+")
    try:
        domains = tuple(int(p.strip()) for p in parts)
    except ValueError as e:
        raise ConfigError(f"validation.yaml: domainDistribution のキー '{key}' が不正です") from e
    if not all(1 <= d <= 6 for d in domains):
        raise ConfigError(f"validation.yaml: domainDistribution のキー '{key}' に 1〜6 以外のドメインがあります")
    return domains


def resolve_config_path(root: Path, explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit
    candidate = root / DEFAULT_CONFIG_NAME
    return candidate if candidate.is_file() else _BUNDLED_CONFIG


def load_config(path: Path) -> Config:
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as e:
        raise ConfigError(f"{path} を読み込めません: {e}") from e
    if not isinstance(raw, dict):
        raise ConfigError(f"{path} の形式が不正です")

    exam = _section(raw, "examSet")
    dist_raw = exam.get("domainDistribution")
    if not isinstance(dist_raw, dict):
        raise ConfigError("validation.yaml: examSet.domainDistribution がありません")
    distribution = tuple((_parse_domains(k), _int(dist_raw, k, "examSet.domainDistribution")) for k in dist_raw)

    case = exam.get("caseQuestions")
    if not isinstance(case, dict):
        raise ConfigError("validation.yaml: examSet.caseQuestions がありません")

    assignments: dict[int, DefaultAssignment] = {}
    assignments_raw = exam.get("defaultAssignments") or {}
    if not isinstance(assignments_raw, dict):
        raise ConfigError("validation.yaml: examSet.defaultAssignments の形式が不正です")
    for key, value in assignments_raw.items():
        if not isinstance(value, dict) or not isinstance(value.get("caseStudies"), list):
            raise ConfigError(f"validation.yaml: defaultAssignments.{key} の形式が不正です")
        assignments[_int_key(key, "examSet.defaultAssignments")] = DefaultAssignment(
            frozenset(value["caseStudies"]), str(value.get("level"))
        )

    stats = _section(raw, "statistics")
    pos = _section(raw, "answerPosition")
    longest = _section(raw, "longestChoice")
    sim = _section(raw, "similarity")
    weights = _section(raw, "weights")
    links = _section(raw, "links")
    guide = _section(raw, "examGuide")
    subs = guide.get("subObjectives")
    if not isinstance(subs, list) or not subs:
        raise ConfigError("validation.yaml: examGuide.subObjectives がありません")
    retry_raw = links.get("retryWithGetOn", [405])
    if not isinstance(retry_raw, list):
        raise ConfigError("validation.yaml: links.retryWithGetOn はリストで指定してください")
    retry_get_on = frozenset(_int({"retryWithGetOn": s}, "retryWithGetOn", "links") for s in retry_raw)

    return Config(
        question_count=_int(exam, "questionCount", "examSet"),
        domain_distribution=distribution,
        case_min=_int(case, "min", "examSet.caseQuestions"),
        case_max=_int(case, "max", "examSet.caseQuestions"),
        default_assignments=assignments,
        draft_min_sample=_int(stats, "draftMinSample", "statistics"),
        position_count=_int(pos, "positions", "answerPosition"),
        position_min=_num(pos, "minRatio", "answerPosition"),
        position_max=_num(pos, "maxRatio", "answerPosition"),
        longest_max=_num(longest, "maxRatio", "longestChoice"),
        longest_count_ties=bool(longest.get("countTies", True)),
        ngram=_int(sim, "ngram", "similarity"),
        jaccard_threshold=_num(sim, "jaccardThreshold", "similarity"),
        weights_sum=_num(weights, "expectedSum", "weights"),
        weights_tolerance=_num(weights, "tolerance", "weights"),
        link_timeout=_num(links, "timeoutSeconds", "links"),
        link_concurrency=_int(links, "concurrency", "links"),
        link_user_agent=str(links.get("userAgent", "pca-content-link-check")),
        link_retry_get_on=retry_get_on,
        sub_objectives=frozenset(str(s) for s in subs),
    )
