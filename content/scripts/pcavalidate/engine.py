"""ルールの実行。"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import replace
from pathlib import Path

import httpx

from .config import Config
from .context import build_context
from .model import Issue, Severity
from .rules import ALL_RULES


def run(
    root: Path,
    config: Config,
    *,
    only: Iterable[str] | None = None,
    check_links: bool = False,
    strict: bool = False,
    transport: httpx.BaseTransport | None = None,
) -> list[Issue]:
    """全ルール(または only で指定したルール)を実行し、重複を除いて決定論的な順序で返す。

    --only で CI-01 を除外しても Schema 検証は行う(ファイル間ルールの対象判定に必要なため)。
    """
    selected = set(only) if only is not None else None
    ctx = build_context(root, config, check_links=check_links, transport=transport)
    issues: set[Issue] = set()
    for rule in ALL_RULES:
        if selected is not None and rule.id not in selected:
            continue
        issues.update(rule.check(ctx))
    if strict:
        issues = {replace(i, severity=Severity.ERROR) for i in issues}
    return sorted(issues)


def exit_code(issues: Iterable[Issue]) -> int:
    return 1 if any(i.severity is Severity.ERROR for i in issues) else 0
