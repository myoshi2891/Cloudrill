"""ルールに渡す検証コンテキスト(ロード・Schema 検証済みのコンテンツ)。"""

from __future__ import annotations

import re
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass
from enum import StrEnum
from functools import cached_property
from pathlib import Path
from typing import Any

import httpx
from jsonschema import ValidationError
from jsonschema.exceptions import best_match

from .config import ExamConfig, GlobalConfig, load_exam_config
from .loader import exam_dirs, load_content
from .model import Issue, JsonPath, Kind, Severity, SourceDoc, format_path, get_list, get_str
from .schemas import validator_for_kind

SCHEMA_RULE = "CI-01"


@dataclass(frozen=True)
class ExamDefinitionView:
    """exam.yaml(Schema 適合済み)から、ルールが使う値を取り出したもの。ルールは exam.yaml の生データを直接読まない。"""

    exam_id: str
    vendor: str
    guide_version: str
    domain_ids: tuple[int, ...]
    domain_weights: dict[int, float]
    sub_objective_domain: dict[str, int]  # サブ項目 ID → ドメイン番号
    question_kinds: frozenset[str]
    mock_question_count: int
    mock_set_count: int
    case_studies_per_set: int
    features: dict[str, bool]
    case_study_ids: tuple[str, ...]
    waf_pillar_ids: frozenset[str]

    @classmethod
    def from_doc(cls, doc: SourceDoc) -> ExamDefinitionView:
        data = doc.data
        domains = data["domains"]
        mock = data["format"]["mockExam"]
        sub_objective_domain: dict[str, int] = {}
        for domain in domains:
            for sub in domain["subObjectives"]:
                # 重複は CI-12 が報告する。ここでは先に定義されたものを採用する
                sub_objective_domain.setdefault(sub["id"], domain["id"])
        return cls(
            exam_id=data["id"],
            vendor=data["vendor"],
            guide_version=data["guideVersion"],
            domain_ids=tuple(d["id"] for d in domains),
            domain_weights={d["id"]: d["weight"] for d in domains},
            sub_objective_domain=sub_objective_domain,
            question_kinds=frozenset(data["format"]["questionKinds"]),
            mock_question_count=mock["questionCount"],
            mock_set_count=mock["setCount"],
            case_studies_per_set=mock["caseStudiesPerSet"],
            features=dict(data["features"]),
            case_study_ids=tuple(data["caseStudies"]),
            waf_pillar_ids=frozenset(p["id"] for p in data["taxonomies"]["wafPillars"]),
        )


def _of_kind(docs: list[SourceDoc], kind: Kind, valid_only: bool) -> list[SourceDoc]:
    return [d for d in docs if d.kind is kind and (d.schema_ok or not valid_only)]


@dataclass
class ExamContext:
    """1つの試験の検証コンテキスト。試験ごとのルール(scope=EXAM)に渡す。"""

    exam_id: str
    root: Path
    config: ExamConfig
    # exam.yaml が Schema 違反または欠落なら None。試験定義を使うルールは、その試験について何も報告しない(原因は CI-01 が報告する)
    definition: ExamDefinitionView | None
    vendor_ids: frozenset[str]
    docs: list[SourceDoc]  # この試験のファイルだけ

    # ---- 種別ごとの取り出し -------------------------------------------------

    def of_kind(self, kind: Kind, *, valid_only: bool = True) -> list[SourceDoc]:
        return _of_kind(self.docs, kind, valid_only)

    @cached_property
    def questions(self) -> list[SourceDoc]:
        """Schema に適合した問題(パス順)。"""
        return self.of_kind(Kind.QUESTION)

    @cached_property
    def question_by_id(self) -> dict[str, SourceDoc]:
        """ID → 問題。重複時はパス順で先のものを採用する(重複自体は CI-07 が報告)。"""
        result: dict[str, SourceDoc] = {}
        for doc in self.questions:
            qid = get_str(doc.data, "id")
            if qid is not None:
                result.setdefault(qid, doc)
        return result

    @cached_property
    def known_question_ids(self) -> set[str]:
        """Schema 違反のファイルも含めて、ID が読み取れる問題の ID 一覧(参照切れの二重報告を避ける)。"""
        return {qid for doc in self.of_kind(Kind.QUESTION, valid_only=False) if (qid := get_str(doc.data, "id"))}

    @cached_property
    def exam_doc(self) -> SourceDoc | None:
        """Schema に適合した exam.yaml。"""
        return next(iter(self.of_kind(Kind.EXAM)), None)

    @cached_property
    def exam_sets(self) -> list[tuple[SourceDoc, list[tuple[int, dict[str, Any]]]]]:
        """(exam-sets.yaml の doc, [(配列 index, 模試定義)])。Schema 違反なら空。"""
        return [
            (doc, [(i, s) for i, s in enumerate(get_list(doc.data, "examSets")) if isinstance(s, dict)])
            for doc in self.of_kind(Kind.EXAM_SETS)
        ]


@dataclass
class GlobalContext:
    """全体のファイルとすべての試験を持つ検証コンテキスト。全体のルール(scope=GLOBAL)に渡す。"""

    root: Path
    config: GlobalConfig
    docs: list[SourceDoc]  # 全体のファイルとすべての試験のファイル
    load_issues: list[Issue]
    schema_issues: list[Issue]
    exams: list[ExamContext]
    check_links: bool = False
    transport: httpx.BaseTransport | None = None

    def of_kind(self, kind: Kind, *, valid_only: bool = True) -> list[SourceDoc]:
        return _of_kind(self.docs, kind, valid_only)

    @cached_property
    def _exam_by_id(self) -> dict[str, ExamContext]:
        return {e.exam_id: e for e in self.exams}

    def exam(self, exam_id: str | None) -> ExamContext | None:
        """ファイルが属する試験のコンテキスト。全体のファイル(exam_id が None)には None を返す。"""
        return self._exam_by_id.get(exam_id) if exam_id is not None else None


# ---- 問題データの補助関数 ---------------------------------------------------


def choices_of(question: object) -> list[dict[str, Any]]:
    return [c for c in get_list(question, "choices") if isinstance(c, dict)]


def correct_indices(question: object) -> list[int]:
    return [i for i, c in enumerate(choices_of(question)) if c.get("isCorrect") is True]


def kind_of(question: object) -> str | None:
    qtype = question.get("type") if isinstance(question, dict) else None
    return get_str(qtype, "kind")


def ja_of(text: object) -> str:
    return get_str(text, "ja") or ""


def status_severity(exam_set: dict[str, Any]) -> Severity:
    """complete の模試は error、draft は warning。"""
    return Severity.ERROR if exam_set.get("status") == "complete" else Severity.WARNING


def set_questions(ctx: ExamContext, exam_set: dict[str, Any]) -> list[SourceDoc]:
    """模試に収録された(同じ試験に実在し Schema に適合する)問題。"""
    by_id = ctx.question_by_id
    return [by_id[q] for q in get_list(exam_set, "questionIDs") if isinstance(q, str) and q in by_id]


# ---- Schema 検証 ------------------------------------------------------------

# Schema では CI-01 として報告せず、CI-05 に委ねるエラーの位置
# (rationale / rationale.ja の欠落と rationale.ja の値の不備のみ。en の型違いや余分なキーは CI-01 のまま)
_CHOICE_PATH = re.compile(r"^choices\[\d+\]$")
_RATIONALE_PATH = re.compile(r"^choices\[\d+\]\.rationale$")
_RATIONALE_JA_PATH = re.compile(r"^choices\[\d+\]\.rationale\.ja$")


def _delegated_rule(kind: Kind, error: ValidationError) -> str | None:
    if kind is not Kind.QUESTION:
        return None
    path = format_path(tuple(error.absolute_path))
    if error.validator == "required":
        # 欠落は親オブジェクトの required エラーとして出る
        if _CHOICE_PATH.match(path) and error.message.startswith("'rationale'"):
            return "CI-05"
        if _RATIONALE_PATH.match(path) and error.message.startswith("'ja'"):
            return "CI-05"
        return None
    if _RATIONALE_JA_PATH.match(path):
        return "CI-05"
    return None


def _describe(error: ValidationError) -> str:
    if error.validator in ("oneOf", "anyOf") and error.context:
        inner = best_match(error.context)
        return f"{error.message[:120]} (最も近い候補: {inner.message[:160]})"
    return error.message[:300]


def schema_check(doc: SourceDoc) -> list[Issue]:
    """Schema 検証を行い doc.schema_ok を設定する。委譲対象のエラーは返さない。"""
    validator = validator_for_kind(doc.kind)
    issues: list[Issue] = []
    for error in validator.iter_errors(doc.data):
        if _delegated_rule(doc.kind, error) is not None:
            continue
        path: JsonPath = tuple(error.absolute_path)
        issues.append(doc.issue(SCHEMA_RULE, Severity.ERROR, f"Schema 違反 ({format_path(path)}): {_describe(error)}", path))
    doc.schema_ok = not issues
    return issues


def build_context(
    root: Path,
    config: GlobalConfig,
    *,
    exam_ids: frozenset[str] | None = None,
    check_links: bool = False,
    transport: httpx.BaseTransport | None = None,
) -> GlobalContext:
    """exam_ids を指定すると、その試験だけを読み込む(全体のファイルは常に読み込む)。"""
    loaded = load_content(root, exam_ids)
    schema_issues: list[Issue] = []
    for doc in loaded.docs:
        schema_issues.extend(schema_check(doc))

    vendor_ids = frozenset(
        vid for doc in _of_kind(loaded.docs, Kind.VENDORS, True) for v in get_list(doc.data, "vendors") if (vid := get_str(v, "id"))
    )
    exams: list[ExamContext] = []
    for exam_dir in exam_dirs(root):
        exam_id = exam_dir.name
        if exam_ids is not None and exam_id not in exam_ids:
            continue
        docs = [d for d in loaded.docs if d.exam_id == exam_id]
        exam_doc = next(iter(_of_kind(docs, Kind.EXAM, True)), None)
        definition = ExamDefinitionView.from_doc(exam_doc) if exam_doc is not None else None
        # 試験ごとの validation.yaml の不備は ConfigError として呼び出し元(CLI は終了コード 2)に伝える
        exams.append(ExamContext(exam_id, exam_dir, load_exam_config(config, exam_dir), definition, vendor_ids, docs))
    return GlobalContext(root, config, loaded.docs, loaded.issues, schema_issues, exams, check_links, transport)


# ---- ルール定義 -------------------------------------------------------------


class Scope(StrEnum):
    EXAM = "exam"  # 試験ごとに実行する
    GLOBAL = "global"  # 全体で1回だけ実行する


@dataclass(frozen=True)
class Rule:
    """検証ルール。試験ごとのルールは check、全体のルールは check_global のどちらか一方だけを持つ。"""

    id: str
    title: str
    check: Callable[[ExamContext], Iterable[Issue]] | None = None
    check_global: Callable[[GlobalContext], Iterable[Issue]] | None = None

    def __post_init__(self) -> None:
        if (self.check is None) == (self.check_global is None):
            raise ValueError(f"{self.id}: check と check_global のどちらか一方だけを指定してください")

    @property
    def scope(self) -> Scope:
        return Scope.GLOBAL if self.check_global is not None else Scope.EXAM


def walk(value: object, path: JsonPath = ()) -> Iterator[tuple[JsonPath, object]]:
    """データを深さ優先で走査する。"""
    yield path, value
    if isinstance(value, dict):
        for k, v in value.items():
            yield from walk(v, (*path, k))
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from walk(v, (*path, i))
