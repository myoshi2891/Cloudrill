"""CI-01: Schema 適合と、Schema では表現しにくい構造条件。"""

from __future__ import annotations

from collections.abc import Iterator

from ..context import Context, Rule, choices_of, correct_indices, kind_of
from ..model import Issue, Kind, Severity, SourceDoc, get_list, get_str

RULE_ID = "CI-01"


def _domain_matches(doc: SourceDoc, obj: object, base: tuple[str | int, ...]) -> Iterator[Issue]:
    """subObjective の先頭の数字と domain が一致するか。"""
    if not isinstance(obj, dict):
        return
    domain = obj.get("domain")
    sub = get_str(obj, "subObjective")
    if isinstance(domain, int) and sub is not None and sub.split(".")[0] != str(domain):
        yield doc.issue(RULE_ID, Severity.ERROR, f"subObjective '{sub}' が domain {domain} と一致しません", (*base, "subObjective"))


def _check_question(doc: SourceDoc) -> Iterator[Issue]:
    q = doc.data
    yield from _domain_matches(doc, q, ())

    choices = choices_of(q)
    seen: dict[str, int] = {}
    for i, choice in enumerate(choices):
        cid = get_str(choice, "id")
        if cid is not None and cid in seen:
            yield doc.issue(RULE_ID, Severity.ERROR, f"選択肢 ID '{cid}' が重複しています(choices[{seen[cid]}] と同じ)", ("choices", i, "id"))
        elif cid is not None:
            seen[cid] = i

        tags = get_list(choice, "mistakeTags")
        if choice.get("isCorrect") is True and tags:
            yield doc.issue(RULE_ID, Severity.ERROR, f"正解の選択肢 '{cid}' に mistakeTags は指定できません", ("choices", i, "mistakeTags"))
        if choice.get("isCorrect") is False and not tags:
            yield doc.issue(RULE_ID, Severity.ERROR, f"誤答の選択肢 '{cid}' には mistakeTags を 1 つ以上指定してください", ("choices", i))

    if kind_of(q) == "single":
        n = len(correct_indices(q))
        if n != 1:
            yield doc.issue(RULE_ID, Severity.ERROR, f"single の問題は正解がちょうど 1 つ必要です(現在 {n} 個)", ("choices",))


def _check_flashcards(doc: SourceDoc) -> Iterator[Issue]:
    for i, card in enumerate(get_list(doc.data, "cards")):
        yield from _domain_matches(doc, card, ("cards", i))


def _check_exam_sets(doc: SourceDoc) -> Iterator[Issue]:
    seen: set[int] = set()
    for i, exam_set in enumerate(get_list(doc.data, "examSets")):
        set_id = exam_set.get("id") if isinstance(exam_set, dict) else None
        if isinstance(set_id, int) and set_id in seen:
            yield doc.issue(RULE_ID, Severity.ERROR, f"模試 ID {set_id} が重複しています", ("examSets", i, "id"))
        if isinstance(set_id, int):
            seen.add(set_id)


def _check_decision(doc: SourceDoc) -> Iterator[Issue]:
    seen: set[str] = set()
    for i, node in enumerate(get_list(doc.data, "nodes")):
        nid = get_str(node, "id")
        if nid is not None and nid in seen:
            yield doc.issue(RULE_ID, Severity.ERROR, f"ノード ID '{nid}' が重複しています", ("nodes", i, "id"))
        if nid is not None:
            seen.add(nid)


def _check_exam(doc: SourceDoc) -> Iterator[Issue]:
    """exam.yaml の id とディレクトリ名(試験のスコープ)が一致するか。"""
    declared = get_str(doc.data, "id")
    if declared is not None and declared != doc.exam_id:
        yield doc.issue(RULE_ID, Severity.ERROR, f"id '{declared}' がディレクトリ名 '{doc.exam_id}' と一致しません", ("id",))


_CHECKERS = {
    Kind.QUESTION: _check_question,
    Kind.FLASHCARD: _check_flashcards,
    Kind.EXAM_SETS: _check_exam_sets,
    Kind.DECISION: _check_decision,
    Kind.EXAM: _check_exam,
}


def check(ctx: Context) -> Iterator[Issue]:
    yield from ctx.load_issues
    yield from ctx.schema_issues
    for doc in ctx.docs:
        checker = _CHECKERS.get(doc.kind)
        if checker is not None and doc.schema_ok:
            yield from checker(doc)


RULE = Rule(RULE_ID, "Schema 適合と構造条件", check)
