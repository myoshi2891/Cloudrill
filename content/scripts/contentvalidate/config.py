"""validation.yaml の読み込みと最低限の構造チェック。

設定は2階層: 全体(content/validation.yaml)の閾値に、試験ごとの exams/<examID>/validation.yaml を深いマージで重ねる。
マッピング同士はキーごとに再帰的にマージし、それ以外(リストやスカラー)は試験側の値で置き換える。
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

DEFAULT_CONFIG_NAME = "validation.yaml"
# スクリプト同梱の既定設定(--root にない場合のフォールバック)
_BUNDLED_CONFIG = Path(__file__).resolve().parents[2] / DEFAULT_CONFIG_NAME

# セクション → 許可するキー(None はキーを問わないマッピング)。未知のキーは typo とみなす
_THRESHOLD_KEYS: dict[str, frozenset[str]] = {
    "statistics": frozenset({"draftMinSample"}),
    "answerPosition": frozenset({"positions", "minRatio", "maxRatio"}),
    "longestChoice": frozenset({"maxRatio", "countTies"}),
    "similarity": frozenset({"ngram", "jaccardThreshold"}),
    "weights": frozenset({"expectedSum", "tolerance"}),
    "links": frozenset({"timeoutSeconds", "concurrency", "userAgent", "retryWithGetOn"}),
}
_EXAM_SET_KEYS = frozenset({"domainDistribution", "caseQuestions", "defaultAssignments"})
# 全体の設定に置けない(試験ごとの設定や exam.yaml に移した)セクションと、その案内
_MOVED_SECTIONS = {
    "examGuide": "exam.yaml へ移行済みです(サブ項目は exam.yaml の domains[].subObjectives)",
    "examSet": "試験ごとの exams/<examID>/validation.yaml に書いてください",
}


class ConfigError(Exception):
    """設定ファイルの不備。CLI は終了コード 2 で終了する。"""


@dataclass(frozen=True)
class DefaultAssignment:
    case_studies: frozenset[str]
    level: str


@dataclass(frozen=True)
class Thresholds:
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


@dataclass(frozen=True)
class ExamSetPolicy:
    # (対象ドメインの組, 期待数)。例: ((5, 6), 13)
    domain_distribution: tuple[tuple[tuple[int, ...], int], ...]
    case_min: int
    case_max: int
    default_assignments: dict[int, DefaultAssignment]


@dataclass(frozen=True)
class GlobalConfig:
    # 試験ごとの設定のマージ元
    raw: Mapping[str, Any]
    thresholds: Thresholds


@dataclass(frozen=True)
class ExamConfig:
    exam_id: str
    thresholds: Thresholds
    # 試験ごとの validation.yaml に examSet がなければ None(模試の構成チェックを省略する)
    exam_set_policy: ExamSetPolicy | None


# ---- 値の取り出し -----------------------------------------------------------


def _section(raw: Mapping[str, Any], key: str, where: str) -> Mapping[str, Any]:
    value = raw.get(key)
    if not isinstance(value, dict):
        raise ConfigError(f"{where}: '{key}' セクションがありません")
    return value


def _num(section: Mapping[str, Any], key: str, where: str, source: str = DEFAULT_CONFIG_NAME) -> float:
    """source はエラーメッセージに出すファイル名。"""
    value = section.get(key)
    # bool は int のサブクラスなので明示的に除外する
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ConfigError(f"{source}: {where}.{key} は数値で指定してください")
    return float(value)


def _int(section: Mapping[str, Any], key: str, where: str, source: str = DEFAULT_CONFIG_NAME) -> int:
    """source はエラーメッセージに出すファイル名。"""
    value = section.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ConfigError(f"{source}: {where}.{key} は整数で指定してください")
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
    # 上限は試験ごとに異なるので固定しない(exam.yaml の domains との照合はルール側で行う)
    if not all(d >= 1 for d in domains):
        raise ConfigError(f"validation.yaml: domainDistribution のキー '{key}' に 1 未満のドメインがあります")
    return domains


def _check_keys(raw: Mapping[str, Any], where: str, *, allow_exam_set: bool) -> None:
    for key, value in raw.items():
        if key == "version":
            continue
        if key == "examSet" and allow_exam_set:
            allowed = _EXAM_SET_KEYS
        elif key in _MOVED_SECTIONS:
            raise ConfigError(f"{where}: '{key}' は {_MOVED_SECTIONS[key]}")
        elif key in _THRESHOLD_KEYS:
            allowed = _THRESHOLD_KEYS[key]
        else:
            raise ConfigError(f"{where}: 未知のセクション '{key}' があります")
        if not isinstance(value, dict):
            raise ConfigError(f"{where}: '{key}' はマッピングで指定してください")
        unknown = sorted(str(k) for k in value if k not in allowed)
        if unknown:
            raise ConfigError(f"{where}: {key} に未知のキー {', '.join(unknown)} があります")


def _merge(base: Mapping[str, Any], override: Mapping[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    for key, value in override.items():
        current = merged.get(key)
        if isinstance(current, dict) and isinstance(value, dict):
            merged[key] = _merge(current, value)
        else:
            merged[key] = value
    return merged


def _read(path: Path) -> dict[str, Any]:
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as e:
        raise ConfigError(f"{path} を読み込めません: {e}") from e
    if not isinstance(raw, dict):
        raise ConfigError(f"{path} の形式が不正です")
    return raw


# ---- 組み立て ---------------------------------------------------------------


def _thresholds(raw: Mapping[str, Any], where: str) -> Thresholds:
    stats = _section(raw, "statistics", where)
    pos = _section(raw, "answerPosition", where)
    longest = _section(raw, "longestChoice", where)
    sim = _section(raw, "similarity", where)
    weights = _section(raw, "weights", where)
    links = _section(raw, "links", where)
    retry_raw = links.get("retryWithGetOn", [405])
    if not isinstance(retry_raw, list):
        raise ConfigError(f"{where}: links.retryWithGetOn はリストで指定してください")
    retry_get_on = frozenset(_int({"retryWithGetOn": s}, "retryWithGetOn", "links", where) for s in retry_raw)

    return Thresholds(
        draft_min_sample=_int(stats, "draftMinSample", "statistics", where),
        position_count=_int(pos, "positions", "answerPosition", where),
        position_min=_num(pos, "minRatio", "answerPosition", where),
        position_max=_num(pos, "maxRatio", "answerPosition", where),
        longest_max=_num(longest, "maxRatio", "longestChoice", where),
        longest_count_ties=bool(longest.get("countTies", True)),
        ngram=_int(sim, "ngram", "similarity", where),
        jaccard_threshold=_num(sim, "jaccardThreshold", "similarity", where),
        weights_sum=_num(weights, "expectedSum", "weights", where),
        weights_tolerance=_num(weights, "tolerance", "weights", where),
        link_timeout=_num(links, "timeoutSeconds", "links", where),
        link_concurrency=_int(links, "concurrency", "links", where),
        link_user_agent=str(links.get("userAgent", "examprep-content-link-check")),
        link_retry_get_on=retry_get_on,
    )


def _exam_set_policy(exam: Mapping[str, Any]) -> ExamSetPolicy:
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

    return ExamSetPolicy(
        domain_distribution=distribution,
        case_min=_int(case, "min", "examSet.caseQuestions"),
        case_max=_int(case, "max", "examSet.caseQuestions"),
        default_assignments=assignments,
    )


def resolve_config_path(root: Path, explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit
    candidate = root / DEFAULT_CONFIG_NAME
    return candidate if candidate.is_file() else _BUNDLED_CONFIG


def load_config(path: Path) -> GlobalConfig:
    """全体の validation.yaml。試験ごとの項目(examSet・examGuide)は置けない。"""
    raw = _read(path)
    where = str(path)
    _check_keys(raw, where, allow_exam_set=False)
    return GlobalConfig(raw, _thresholds(raw, where))


def load_exam_config(global_config: GlobalConfig, exam_dir: Path) -> ExamConfig:
    """exam_dir/validation.yaml(なければ空)を全体の設定に重ねる。"""
    path = exam_dir / DEFAULT_CONFIG_NAME
    exam_raw = _read(path) if path.is_file() else {}
    where = str(path)
    _check_keys(exam_raw, where, allow_exam_set=True)
    merged = _merge(global_config.raw, exam_raw)
    exam_set = merged.get("examSet")
    return ExamConfig(
        exam_id=exam_dir.name,
        thresholds=_thresholds(merged, where),
        exam_set_policy=_exam_set_policy(exam_set) if isinstance(exam_set, dict) else None,
    )
