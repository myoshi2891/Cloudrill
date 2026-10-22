"""CI-03: 単一選択問題の正解位置の偏り。"""

from __future__ import annotations

from collections import Counter
from collections.abc import Iterator
from typing import Any

from ..context import ExamContext, Rule, correct_indices, kind_of, set_questions, status_severity
from ..model import Issue, SourceDoc

RULE_ID = "CI-03"


def check(ctx: ExamContext) -> Iterator[Issue]:
    for doc, exam_sets in ctx.exam_sets:
        yield from _check_exam(ctx, doc, exam_sets)


def _check_exam(ctx: ExamContext, doc: SourceDoc, exam_sets: list[tuple[int, dict[str, Any]]]) -> Iterator[Issue]:
    cfg = ctx.config.thresholds
    for i, exam_set in exam_sets:
        singles = [q for q in set_questions(ctx, exam_set) if kind_of(q.data) == "single"]
        positions = [idx[0] for q in singles if len(idx := correct_indices(q.data)) == 1]
        total = len(positions)
        if total == 0:
            continue
        if exam_set.get("status") != "complete" and total < cfg.draft_min_sample:
            continue
        counts = Counter(positions)
        ratios = {p: counts.get(p, 0) / total for p in range(cfg.position_count)}
        out = [p for p, r in ratios.items() if not cfg.position_min <= r <= cfg.position_max]
        if not out:
            continue
        dist = ", ".join(f"{chr(ord('A') + p)}={counts.get(p, 0)}({r:.1%})" for p, r in ratios.items())
        bad = ", ".join(chr(ord("A") + p) for p in out)
        yield doc.issue(
            RULE_ID, status_severity(exam_set),
            f"模試 {exam_set.get('id')}: 正解位置 {bad} が {cfg.position_min:.0%}〜{cfg.position_max:.0%} の範囲外です"
            f"(単一選択 {total} 問: {dist})",
            ("examSets", i),
        )


RULE = Rule(RULE_ID, "正解位置の分布", check)
