"""CI-10: ドメイン比重の合計が 1.0(weights.yaml と exam.yaml)、および両者の一致。"""

from __future__ import annotations

from collections.abc import Iterator

from ..context import Context, Rule
from ..model import Issue, JsonPath, Kind, Severity, SourceDoc

RULE_ID = "CI-10"


def _check_sum(ctx: Context, doc: SourceDoc, total: float, path: JsonPath) -> Iterator[Issue]:
    cfg = ctx.config
    if abs(total - cfg.weights_sum) > cfg.weights_tolerance:
        yield doc.issue(
            RULE_ID, Severity.ERROR,
            f"ドメイン比重の合計が {total:.4f} です(期待値 {cfg.weights_sum} ±{cfg.weights_tolerance})",
            path,
        )


def check(ctx: Context) -> Iterator[Issue]:
    weights_by_exam: dict[str | None, dict[str, float]] = {}
    for doc in ctx.of_kind(Kind.WEIGHTS):
        weights: dict[str, float] = doc.data["weights"]
        weights_by_exam[doc.exam_id] = weights
        yield from _check_sum(ctx, doc, sum(weights.values()), ("weights",))

    for exam_id, doc in ctx.exam_by_id.items():
        domains = doc.data["domains"]
        yield from _check_sum(ctx, doc, sum(d["weight"] for d in domains), ("domains",))

        expected = weights_by_exam.get(exam_id)
        if expected is None:
            continue
        # weights.yaml のキーは文字列に正規化されている("1")
        actual = {str(d["id"]): (i, d["weight"]) for i, d in enumerate(domains)}
        for key in sorted(actual.keys() | expected.keys()):
            if key not in actual:
                yield doc.issue(RULE_ID, Severity.ERROR, f"weights.yaml にあるドメイン {key} が domains にありません", ("domains",))
                continue
            i, weight = actual[key]
            if key not in expected:
                yield doc.issue(RULE_ID, Severity.ERROR, f"ドメイン {key} が weights.yaml にありません", ("domains", i))
            elif weight != expected[key]:
                yield doc.issue(
                    RULE_ID, Severity.ERROR,
                    f"ドメイン {key} の比重 {weight} が weights.yaml の値 {expected[key]} と異なります",
                    ("domains", i, "weight"),
                )


RULE = Rule(RULE_ID, "ドメイン比重の合計", check)
