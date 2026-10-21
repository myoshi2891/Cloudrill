"""CI-11: LocalizedText の en 欠落(warning)。"""

from __future__ import annotations

from collections.abc import Iterator

from ..context import Context, Rule, walk
from ..model import Issue, Severity, format_path

RULE_ID = "CI-11"
_LOCALIZED_KEYS = frozenset({"ja", "en"})


def _is_localized(value: object) -> bool:
    return isinstance(value, dict) and "ja" in value and set(value) <= _LOCALIZED_KEYS


def check(ctx: Context) -> Iterator[Issue]:
    for doc in ctx.docs:
        if not doc.schema_ok:
            continue
        for path, value in walk(doc.data):
            if not _is_localized(value):
                continue
            en = value.get("en")
            if not isinstance(en, str) or not en.strip():
                yield doc.issue(RULE_ID, Severity.WARNING, f"英語訳(en)がありません: {format_path(path)}", path)


RULE = Rule(RULE_ID, "英語訳の欠落", check)
