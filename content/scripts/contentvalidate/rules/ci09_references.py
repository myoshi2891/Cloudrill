"""CI-09: 参照の整合性(問題 ID・ノード ID の実在と、subObjective・domain・caseStudy・wafPillars が exam.yaml にあること)。"""

from __future__ import annotations

from collections.abc import Iterator

from ..context import ExamContext, ExamDefinitionView, Rule
from ..model import Issue, JsonPath, Kind, Severity, SourceDoc, get_list, get_str

RULE_ID = "CI-09"


def _sub_objective(ctx: ExamContext, doc: SourceDoc, obj: object, path: JsonPath) -> Iterator[Issue]:
    # exam.yaml が Schema 違反の試験は確認しない(原因は CI-01 が報告する)。以下の語彙の確認も同じ
    if ctx.definition is None:
        return
    sub = get_str(obj, "subObjective")
    if sub is not None and sub not in ctx.definition.sub_objective_domain:
        yield doc.issue(RULE_ID, Severity.ERROR, f"subObjective '{sub}' は exam.yaml のサブ項目にありません", (*path, "subObjective"))


def _domain(definition: ExamDefinitionView, doc: SourceDoc, obj: object, path: JsonPath) -> Iterator[Issue]:
    domain = obj.get("domain") if isinstance(obj, dict) else None
    if isinstance(domain, int) and domain not in definition.domain_ids:
        yield doc.issue(RULE_ID, Severity.ERROR, f"domain {domain} は exam.yaml の domains にありません", (*path, "domain"))


def _vocabulary(ctx: ExamContext) -> Iterator[Issue]:
    """domain・caseStudy・wafPillars・模試の caseStudies(試験語彙)が exam.yaml にあること。"""
    definition = ctx.definition
    if definition is None:
        return
    for doc in ctx.questions:
        yield from _domain(definition, doc, doc.data, ())
        case = get_str(doc.data, "caseStudy")
        if case is not None and case not in definition.case_study_ids:
            yield doc.issue(RULE_ID, Severity.ERROR, f"caseStudy '{case}' は exam.yaml の caseStudies にありません", ("caseStudy",))
        for i, pillar in enumerate(get_list(doc.data, "wafPillars")):
            if pillar not in definition.waf_pillar_ids:
                yield doc.issue(
                    RULE_ID, Severity.ERROR, f"wafPillars の '{pillar}' は exam.yaml の taxonomies.wafPillars にありません", ("wafPillars", i)
                )
    for doc in ctx.of_kind(Kind.FLASHCARD):
        for i, card in enumerate(get_list(doc.data, "cards")):
            yield from _domain(definition, doc, card, ("cards", i))
    for doc, exam_sets in ctx.exam_sets:
        for i, exam_set in exam_sets:
            for j, case in enumerate(get_list(exam_set, "caseStudies")):
                if case not in definition.case_study_ids:
                    yield doc.issue(
                        RULE_ID, Severity.ERROR,
                        f"模試 {exam_set.get('id')} の caseStudies の '{case}' は exam.yaml の caseStudies にありません",
                        ("examSets", i, "caseStudies", j),
                    )


def _flashcards(ctx: ExamContext) -> Iterator[Issue]:
    for doc in ctx.of_kind(Kind.FLASHCARD):
        known = ctx.known_question_ids
        for i, card in enumerate(get_list(doc.data, "cards")):
            yield from _sub_objective(ctx, doc, card, ("cards", i))
            for j, qid in enumerate(get_list(card, "relatedQuestionIDs")):
                if qid not in known:
                    yield doc.issue(RULE_ID, Severity.ERROR, f"relatedQuestionIDs の {qid} は存在しません", ("cards", i, "relatedQuestionIDs", j))


def _exam_sets(ctx: ExamContext) -> Iterator[Issue]:
    for doc, exam_sets in ctx.exam_sets:
        known = ctx.known_question_ids
        for i, exam_set in exam_sets:
            for j, qid in enumerate(get_list(exam_set, "questionIDs")):
                if qid not in known:
                    yield doc.issue(
                        RULE_ID, Severity.ERROR,
                        f"模試 {exam_set.get('id')} の questionIDs の {qid} は存在しません",
                        ("examSets", i, "questionIDs", j),
                    )


def _decisions(ctx: ExamContext) -> Iterator[Issue]:
    for doc in ctx.of_kind(Kind.DECISION):
        nodes = get_list(doc.data, "nodes")
        node_ids = {nid for n in nodes if (nid := get_str(n, "id")) is not None}
        root = get_str(doc.data, "rootNodeID")
        if root not in node_ids:
            yield doc.issue(RULE_ID, Severity.ERROR, f"rootNodeID '{root}' に対応するノードがありません", ("rootNodeID",))
        for i, node in enumerate(nodes):
            for j, option in enumerate(get_list(node, "options")):
                target = get_str(option, "next")
                if target is not None and target not in node_ids:
                    yield doc.issue(RULE_ID, Severity.ERROR, f"next '{target}' に対応するノードがありません", ("nodes", i, "options", j, "next"))


def _sub_objectives(ctx: ExamContext) -> Iterator[Issue]:
    for doc in ctx.of_kind(Kind.DOCS):
        yield from _sub_objective(ctx, doc, doc.data, ())
    for doc in ctx.questions:
        yield from _sub_objective(ctx, doc, doc.data, ())


def check(ctx: ExamContext) -> Iterator[Issue]:
    yield from _flashcards(ctx)
    yield from _exam_sets(ctx)
    yield from _decisions(ctx)
    yield from _sub_objectives(ctx)
    yield from _vocabulary(ctx)


RULE = Rule(RULE_ID, "参照の整合性", check)
