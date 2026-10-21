"""検証結果の出力(text / json / github)。"""

from __future__ import annotations

import json
from collections import Counter
from collections.abc import Sequence

from .model import Issue, Severity


def format_text(issues: Sequence[Issue]) -> str:
    lines = []
    for i in issues:
        location = f"{i.file}:{i.line}" if i.line is not None else i.file
        lines.append(f"{location}: [{i.rule}] {i.severity}: {i.message}")

    errors = sum(1 for i in issues if i.severity is Severity.ERROR)
    warnings = len(issues) - errors
    if lines:
        lines.append("")
    lines.append(f"集計: error {errors} 件, warning {warnings} 件")
    by_rule = Counter((i.rule, str(i.severity)) for i in issues)
    for (rule, severity), n in sorted(by_rule.items()):
        lines.append(f"  {rule} {severity}: {n}")
    return "\n".join(lines) + "\n"


def format_json(issues: Sequence[Issue]) -> str:
    return json.dumps([i.to_json() for i in issues], ensure_ascii=False, indent=2) + "\n"


def _escape_data(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _escape_property(value: str) -> str:
    return _escape_data(value).replace(":", "%3A").replace(",", "%2C")


def format_github(issues: Sequence[Issue], path_prefix: str = "") -> str:
    """GitHub Actions のワークフローコマンド形式。file はリポジトリルートからの相対パスにする。"""
    out = []
    for i in issues:
        props = [f"file={_escape_property(path_prefix + i.file)}"]
        if i.line is not None:
            props.append(f"line={i.line}")
        props.append(f"title={_escape_property(i.rule)}")
        out.append(f"::{i.severity} {','.join(props)}::{_escape_data(f'[{i.rule}] {i.message}')}")
    return "\n".join(out) + ("\n" if out else "")
