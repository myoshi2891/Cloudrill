"""CI-05: 全選択肢の rationale.ja が空でない。

Schema 上の rationale エラーは CI-01 から委譲されるため、Schema 違反のファイルも対象にする。
"""

from __future__ import annotations

from collections.abc import Iterator

from ..context import ExamContext, Rule, choices_of
from ..model import Issue, Kind, Severity, get_str

RULE_ID = "CI-05"


def check(ctx: ExamContext) -> Iterator[Issue]:
    for doc in ctx.of_kind(Kind.QUESTION, valid_only=False):
        for i, choice in enumerate(choices_of(doc.data)):
            rationale = choice.get("rationale")
            ja = get_str(rationale, "ja")
            if ja is None or not ja.strip():
                cid = get_str(choice, "id") or f"#{i}"
                what = "rationale がありません" if rationale is None else "rationale.ja が空です"
                yield doc.issue(RULE_ID, Severity.ERROR, f"選択肢 '{cid}' の {what}", ("choices", i, "rationale"))


RULE = Rule(RULE_ID, "解説(rationale)の記載", check)
