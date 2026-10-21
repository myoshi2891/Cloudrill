"""CI-04: 「最も長い選択肢が正解」の問題の割合。"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

from ..context import Context, Rule, choices_of, ja_of, set_questions, status_severity
from ..model import Issue, SourceDoc

RULE_ID = "CI-04"


def longest_is_correct(question: object, count_ties: bool) -> bool:
    lengths = [(len(ja_of(c.get("text"))), c.get("isCorrect") is True) for c in choices_of(question)]
    if not lengths:
        return False
    longest = max(n for n, _ in lengths)
    top = [correct for n, correct in lengths if n == longest]
    if len(top) > 1 and not count_ties:
        return False
    return any(top)


def check(ctx: Context) -> Iterator[Issue]:
    for doc, exam_sets in ctx.exam_sets:
        yield from _check_exam(ctx, doc, exam_sets)


def _check_exam(ctx: Context, doc: SourceDoc, exam_sets: list[tuple[int, dict[str, Any]]]) -> Iterator[Issue]:
    cfg = ctx.exam_config(doc.exam_id).thresholds
    for i, exam_set in exam_sets:
        questions = set_questions(ctx, doc.exam_id, exam_set)
        total = len(questions)
        if total == 0:
            continue
        if exam_set.get("status") != "complete" and total < cfg.draft_min_sample:
            continue
        hits = sum(1 for q in questions if longest_is_correct(q.data, cfg.longest_count_ties))
        ratio = hits / total
        if ratio > cfg.longest_max:
            yield doc.issue(
                RULE_ID, status_severity(exam_set),
                f"模試 {exam_set.get('id')}: 最長の選択肢が正解の問題が {hits}/{total}({ratio:.1%})で、上限 {cfg.longest_max:.0%} を超えています",
                ("examSets", i),
            )


RULE = Rule(RULE_ID, "最長選択肢の偏り", check)
