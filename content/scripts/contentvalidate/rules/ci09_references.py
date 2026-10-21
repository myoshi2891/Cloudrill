"""CI-09: 参照の整合性(問題 ID・ノード ID・subObjective の実在)。"""

from __future__ import annotations

from collections.abc import Iterator

from ..context import Context, Rule
from ..model import Issue, Kind, Severity, SourceDoc, get_list, get_str

RULE_ID = "CI-09"


def _sub_objective(ctx: Context, doc: SourceDoc, obj: object, path: tuple[str | int, ...]) -> Iterator[Issue]:
    sub = get_str(obj, "subObjective")
    if sub is not None and sub not in ctx.config.sub_objectives:
        yield doc.issue(RULE_ID, Severity.ERROR, f"subObjective '{sub}' は試験ガイドの一覧(validation.yaml)にありません", (*path, "subObjective"))


def _flashcards(ctx: Context) -> Iterator[Issue]:
    known = ctx.known_question_ids
    for doc in ctx.of_kind(Kind.FLASHCARD):
        for i, card in enumerate(get_list(doc.data, "cards")):
            yield from _sub_objective(ctx, doc, card, ("cards", i))
            for j, qid in enumerate(get_list(card, "relatedQuestionIDs")):
                if qid not in known:
                    yield doc.issue(RULE_ID, Severity.ERROR, f"relatedQuestionIDs の {qid} は存在しません", ("cards", i, "relatedQuestionIDs", j))


def _exam_sets(ctx: Context) -> Iterator[Issue]:
    doc, exam_sets = ctx.exam_sets
    if doc is None:
        return
    known = ctx.known_question_ids
    for i, exam_set in exam_sets:
        for j, qid in enumerate(get_list(exam_set, "questionIDs")):
            if qid not in known:
                yield doc.issue(
                    RULE_ID, Severity.ERROR,
                    f"模試 {exam_set.get('id')} の questionIDs の {qid} は存在しません",
                    ("examSets", i, "questionIDs", j),
                )


def _decisions(ctx: Context) -> Iterator[Issue]:
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


def _sub_objectives(ctx: Context) -> Iterator[Issue]:
    for doc in ctx.of_kind(Kind.DOCS):
        yield from _sub_objective(ctx, doc, doc.data, ())
    for doc in ctx.questions:
        yield from _sub_objective(ctx, doc, doc.data, ())


def check(ctx: Context) -> Iterator[Issue]:
    yield from _flashcards(ctx)
    yield from _exam_sets(ctx)
    yield from _decisions(ctx)
    yield from _sub_objectives(ctx)


RULE = Rule(RULE_ID, "参照の整合性", check)
