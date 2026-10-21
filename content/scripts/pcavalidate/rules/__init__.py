"""検証ルールの一覧。ルールを追加するときは、モジュールを作成してここに1行追加する。"""

from __future__ import annotations

from ..context import Rule
from . import (
    ci01_schema,
    ci02_exam_sets,
    ci03_answer_position,
    ci04_longest_choice,
    ci05_rationale,
    ci06_links,
    ci07_duplicates,
    ci08_multiple_count,
    ci09_references,
    ci10_weights,
    ci11_english,
)

ALL_RULES: tuple[Rule, ...] = (
    ci01_schema.RULE,
    ci02_exam_sets.RULE,
    ci03_answer_position.RULE,
    ci04_longest_choice.RULE,
    ci05_rationale.RULE,
    ci06_links.RULE,
    ci07_duplicates.RULE,
    ci08_multiple_count.RULE,
    ci09_references.RULE,
    ci10_weights.RULE,
    ci11_english.RULE,
)

RULE_IDS: frozenset[str] = frozenset(rule.id for rule in ALL_RULES)
