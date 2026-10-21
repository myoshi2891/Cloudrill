"""CI-12: 試験定義(exam.yaml)と、ディレクトリ名・vendors.yaml・試験のコンテンツとの整合。"""

from __future__ import annotations

from collections.abc import Iterator

from ..context import ExamContext, ExamDefinitionView, Rule, kind_of
from ..model import Issue, Kind, Severity, SourceDoc, get_list, get_str

RULE_ID = "CI-12"

# 機能のフラグ → その機能のコンテンツの種別(機能を追加するときは、ここに1行足す)
FEATURE_KINDS: dict[str, Kind] = {
    "caseStudies": Kind.CASE,
    "decisionTrees": Kind.DECISION,
    "keywordDrills": Kind.DRILL,
    "flashcards": Kind.FLASHCARD,
    "docs": Kind.DOCS,
}


def _identity(ctx: ExamContext, exam: SourceDoc, definition: ExamDefinitionView) -> Iterator[Issue]:
    if definition.exam_id != ctx.exam_id:
        yield exam.issue(RULE_ID, Severity.ERROR, f"id '{definition.exam_id}' がディレクトリ名 '{ctx.exam_id}' と一致しません", ("id",))
    # vendors.yaml が欠落・Schema 違反なら確認しない(原因は CI-01 が報告する)
    if ctx.vendor_ids and definition.vendor not in ctx.vendor_ids:
        yield exam.issue(RULE_ID, Severity.ERROR, f"vendor '{definition.vendor}' は vendors.yaml にありません", ("vendor",))


def _domains(exam: SourceDoc, definition: ExamDefinitionView) -> Iterator[Issue]:
    expected = tuple(range(1, len(definition.domain_ids) + 1))
    if definition.domain_ids != expected:
        ids = ", ".join(str(d) for d in definition.domain_ids)
        yield exam.issue(RULE_ID, Severity.ERROR, f"domains の id が 1 から始まる連番ではありません({ids})", ("domains",))

    first: dict[str, int] = {}
    for i, domain in enumerate(get_list(exam.data, "domains")):
        for j, sub in enumerate(get_list(domain, "subObjectives")):
            sub_id = get_str(sub, "id")
            if sub_id is None:
                continue
            if sub_id in first:
                yield exam.issue(
                    RULE_ID, Severity.ERROR,
                    f"サブ項目 '{sub_id}' が重複しています(最初の定義: ドメイン {first[sub_id]})",
                    ("domains", i, "subObjectives", j, "id"),
                )
            else:
                first[sub_id] = domain.get("id")


def _case_studies(ctx: ExamContext, exam: SourceDoc, definition: ExamDefinitionView) -> Iterator[Issue]:
    # Schema 違反のケースも ID が読めれば数える(欠落の誤報を避ける)
    files = {cid: doc for doc in ctx.of_kind(Kind.CASE, valid_only=False) if (cid := get_str(doc.data, "id")) is not None}
    for i, cid in enumerate(definition.case_study_ids):
        if cid not in files:
            yield exam.issue(RULE_ID, Severity.ERROR, f"caseStudies の '{cid}' に対応する cases/*.yaml がありません", ("caseStudies", i))
    for cid, doc in sorted(files.items()):
        if cid not in definition.case_study_ids:
            yield doc.issue(RULE_ID, Severity.ERROR, f"ケース '{cid}' が exam.yaml の caseStudies にありません", ("id",))


def _disabled_features(ctx: ExamContext, definition: ExamDefinitionView) -> Iterator[Issue]:
    """無効な機能のコンテンツを置いていないこと。ケースが無効なら、問題と模試からの参照もないこと。"""
    for feature, kind in FEATURE_KINDS.items():
        if definition.features.get(feature, False):
            continue
        for doc in ctx.of_kind(kind, valid_only=False):
            yield doc.issue(RULE_ID, Severity.ERROR, f"exam.yaml の features.{feature} が false なのに、このファイルがあります")

    if definition.features.get("caseStudies", False):
        return
    for doc in ctx.questions:
        if doc.data.get("caseStudy") is not None:
            yield doc.issue(RULE_ID, Severity.ERROR, "exam.yaml の features.caseStudies が false なので、caseStudy は null にしてください", ("caseStudy",))
    for doc, exam_sets in ctx.exam_sets:
        for i, exam_set in exam_sets:
            if get_list(exam_set, "caseStudies"):
                yield doc.issue(
                    RULE_ID, Severity.ERROR,
                    f"模試 {exam_set.get('id')}: exam.yaml の features.caseStudies が false なので、caseStudies は空にしてください",
                    ("examSets", i, "caseStudies"),
                )


def _question_kinds(ctx: ExamContext, definition: ExamDefinitionView) -> Iterator[Issue]:
    for doc in ctx.questions:
        kind = kind_of(doc.data)
        if kind is not None and kind not in definition.question_kinds:
            allowed = ", ".join(sorted(definition.question_kinds))
            yield doc.issue(
                RULE_ID, Severity.ERROR, f"type.kind '{kind}' は exam.yaml の format.questionKinds({allowed})にありません", ("type", "kind")
            )


def _guide_version(ctx: ExamContext, definition: ExamDefinitionView) -> Iterator[Issue]:
    """試験ガイドの改訂時に、見直しが必要な問題を一覧にするための warning。"""
    for doc in ctx.questions:
        version = get_str(doc.data, "examGuideVersion")
        if version is not None and version != definition.guide_version:
            yield doc.issue(
                RULE_ID, Severity.WARNING,
                f"examGuideVersion '{version}' が exam.yaml の guideVersion '{definition.guide_version}' と異なります",
                ("examGuideVersion",),
            )


def check(ctx: ExamContext) -> Iterator[Issue]:
    exam, definition = ctx.exam_doc, ctx.definition
    # exam.yaml が欠落・Schema 違反なら確認しない(原因は CI-01 が報告する)
    if exam is None or definition is None:
        return
    yield from _identity(ctx, exam, definition)
    yield from _domains(exam, definition)
    yield from _case_studies(ctx, exam, definition)
    yield from _disabled_features(ctx, definition)
    yield from _question_kinds(ctx, definition)
    yield from _guide_version(ctx, definition)


RULE = Rule(RULE_ID, "試験定義の整合", check)
