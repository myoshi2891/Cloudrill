"""CI-10: exam.yaml のドメイン比重の合計が 1.0。"""

from __future__ import annotations

from collections.abc import Iterator

from ..context import ExamContext, Rule
from ..model import Issue, Severity

RULE_ID = "CI-10"


def check(ctx: ExamContext) -> Iterator[Issue]:
    doc = ctx.exam_doc
    if doc is None or ctx.definition is None:
        return
    cfg = ctx.config.thresholds
    total = sum(ctx.definition.domain_weights.values())
    if abs(total - cfg.weights_sum) > cfg.weights_tolerance:
        yield doc.issue(
            RULE_ID, Severity.ERROR,
            f"ドメイン比重の合計が {total:.4f} です(期待値 {cfg.weights_sum} ±{cfg.weights_tolerance})",
            ("domains",),
        )


RULE = Rule(RULE_ID, "ドメイン比重の合計", check)
