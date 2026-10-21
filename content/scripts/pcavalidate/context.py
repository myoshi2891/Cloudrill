"""ルールに渡す検証コンテキスト(ロード・Schema 検証済みのコンテンツ)。"""

from __future__ import annotations

import re
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path
from typing import Any

import httpx
from jsonschema import ValidationError
from jsonschema.exceptions import best_match

from .config import Config
from .loader import load_content
from .model import Issue, JsonPath, Kind, Severity, SourceDoc, format_path, get_list, get_str
from .schemas import validator_for_kind

SCHEMA_RULE = "CI-01"


@dataclass
class Context:
    root: Path
    config: Config
    docs: list[SourceDoc]
    load_issues: list[Issue]
    schema_issues: list[Issue]
    check_links: bool = False
    transport: httpx.BaseTransport | None = None

    # ---- 種別ごとの取り出し -------------------------------------------------

    def of_kind(self, kind: Kind, *, valid_only: bool = True) -> list[SourceDoc]:
        return [d for d in self.docs if d.kind is kind and (d.schema_ok or not valid_only)]

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
        return {qid for d in self.of_kind(Kind.QUESTION, valid_only=False) if (qid := get_str(d.data, "id"))}

    @cached_property
    def exam_sets(self) -> tuple[SourceDoc | None, list[tuple[int, dict[str, Any]]]]:
        """(exam-sets.yaml の doc, [(配列 index, 模試定義)])。Schema 違反なら空。"""
        docs = self.of_kind(Kind.EXAM_SETS)
        if not docs:
            return None, []
        doc = docs[0]
        return doc, [(i, s) for i, s in enumerate(get_list(doc.data, "examSets")) if isinstance(s, dict)]


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


def set_questions(ctx: Context, exam_set: dict[str, Any]) -> list[SourceDoc]:
    """模試に収録された(実在し Schema に適合する)問題。"""
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
    config: Config,
    *,
    check_links: bool = False,
    transport: httpx.BaseTransport | None = None,
) -> Context:
    loaded = load_content(root)
    schema_issues: list[Issue] = []
    for doc in loaded.docs:
        schema_issues.extend(schema_check(doc))
    return Context(root, config, loaded.docs, loaded.issues, schema_issues, check_links, transport)


# ---- ルール定義 -------------------------------------------------------------


@dataclass(frozen=True)
class Rule:
    id: str
    title: str
    check: Callable[[Context], Iterable[Issue]]


def walk(value: object, path: JsonPath = ()) -> Iterator[tuple[JsonPath, object]]:
    """データを深さ優先で走査する。"""
    yield path, value
    if isinstance(value, dict):
        for k, v in value.items():
            yield from walk(v, (*path, k))
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from walk(v, (*path, i))
