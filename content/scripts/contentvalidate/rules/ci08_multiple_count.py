"""CI-08: multiple の問題で type.count と正解数が一致する。"""

from __future__ import annotations

from collections.abc import Iterator

from ..context import ExamContext, Rule, correct_indices, kind_of
from ..model import Issue, Severity

RULE_ID = "CI-08"


def check(ctx: ExamContext) -> Iterator[Issue]:
    for doc in ctx.questions:
        if kind_of(doc.data) != "multiple":
            continue
        count = doc.data["type"].get("count")
        actual = len(correct_indices(doc.data))
        if count != actual:
            yield doc.issue(RULE_ID, Severity.ERROR, f"type.count は {count} ですが、正解の選択肢は {actual} 個です", ("type", "count"))


RULE = Rule(RULE_ID, "複数選択の正解数", check)
