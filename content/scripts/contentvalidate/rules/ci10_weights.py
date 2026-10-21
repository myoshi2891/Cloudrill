"""CI-10: weights.yaml の合計が 1.0。"""

from __future__ import annotations

from collections.abc import Iterator

from ..context import Context, Rule
from ..model import Issue, Kind, Severity

RULE_ID = "CI-10"


def check(ctx: Context) -> Iterator[Issue]:
    cfg = ctx.config
    for doc in ctx.of_kind(Kind.WEIGHTS):
        total = sum(doc.data["weights"].values())
        if abs(total - cfg.weights_sum) > cfg.weights_tolerance:
            yield doc.issue(
                RULE_ID, Severity.ERROR,
                f"ドメイン比重の合計が {total:.4f} です(期待値 {cfg.weights_sum} ±{cfg.weights_tolerance})",
                ("weights",),
            )


RULE = Rule(RULE_ID, "ドメイン比重の合計", check)
