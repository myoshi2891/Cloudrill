"""ルールの実行。"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import replace
from pathlib import Path

import httpx

from .config import GlobalConfig
from .context import Scope, build_context
from .model import Issue, Severity
from .rules import ALL_RULES


def run(
    root: Path,
    config: GlobalConfig,
    *,
    exam_ids: frozenset[str] | None = None,
    only: Iterable[str] | None = None,
    check_links: bool = False,
    strict: bool = False,
    transport: httpx.BaseTransport | None = None,
) -> list[Issue]:
    """全ルール(または only で指定したルール)を実行し、重複を除いて決定論的な順序で返す。

    全体のルールは1回、試験ごとのルールは試験の数だけ実行する。exam_ids を指定すると、その試験だけを対象にする。
    --only で CI-01 を除外しても Schema 検証は行う(ファイル間ルールの対象判定に必要なため)。
    """
    selected = set(only) if only is not None else None
    ctx = build_context(root, config, exam_ids=exam_ids, check_links=check_links, transport=transport)
    issues: set[Issue] = set()
    for rule in ALL_RULES:
        if selected is not None and rule.id not in selected:
            continue
        if rule.scope is Scope.GLOBAL and rule.check_global is not None:
            issues.update(rule.check_global(ctx))
        elif rule.check is not None:
            for exam in ctx.exams:
                issues.update(rule.check(exam))
    if strict:
        issues = {replace(i, severity=Severity.ERROR) for i in issues}
    return sorted(issues)


def exit_code(issues: Iterable[Issue]) -> int:
    return 1 if any(i.severity is Severity.ERROR for i in issues) else 0
