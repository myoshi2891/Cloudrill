"""検証結果とロード済みコンテンツのデータモデル。"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any

# JSON Pointer 相当のパス(例: ("choices", 0, "rationale"))
JsonPath = tuple[str | int, ...]


class Severity(StrEnum):
    ERROR = "error"
    WARNING = "warning"


class Kind(StrEnum):
    """コンテンツ種別。値は対応する Schema ファイル名の接頭辞。"""

    QUESTION = "question"
    FLASHCARD = "flashcard"
    CASE = "case"
    DECISION = "decision"
    DRILL = "drill"
    EXAM_SETS = "exam-sets"
    WEIGHTS = "weights"
    DOCS = "docs-frontmatter"


@dataclass(frozen=True, order=True)
class Issue:
    """1件の検出結果。並び順は (file, line, rule, ...) で決定論的にする。"""

    file: str
    line: int | None
    rule: str
    severity: Severity
    message: str

    def to_json(self) -> dict[str, Any]:
        return {
            "rule": self.rule,
            "severity": str(self.severity),
            "file": self.file,
            "line": self.line,
            "message": self.message,
        }


@dataclass
class SourceDoc:
    """1ファイル分のロード結果。

    data は JSON 相当(dict のキーは str、日付は ISO 文字列)に正規化済み。
    lines はパス → 1 始まりの行番号。
    """

    path: str
    kind: Kind
    data: Any
    lines: dict[JsonPath, int] = field(default_factory=dict)
    # Schema 違反(CI-01 に分類されたもの)がなければ True。ファイル間ルールは True のものだけを対象にする
    schema_ok: bool = False

    def line_of(self, path: JsonPath = ()) -> int | None:
        """パスに対応する行番号。見つからなければ親をさかのぼる。"""
        current = path
        while True:
            line = self.lines.get(current)
            if line is not None:
                return line
            if not current:
                return None
            current = current[:-1]

    def issue(self, rule: str, severity: Severity, message: str, path: JsonPath = ()) -> Issue:
        return Issue(self.path, self.line_of(path), rule, severity, message)


def get_str(obj: object, key: str) -> str | None:
    """dict から str 値を安全に取り出す(型が違えば None)。"""
    if not isinstance(obj, dict):
        return None
    value = obj.get(key)
    return value if isinstance(value, str) else None


def get_list(obj: object, key: str) -> list[Any]:
    """dict から list 値を安全に取り出す(型が違えば空リスト)。"""
    if not isinstance(obj, dict):
        return []
    value = obj.get(key)
    return value if isinstance(value, list) else []


def format_path(path: JsonPath) -> str:
    """("choices", 0, "text") → "choices[0].text" """
    out = ""
    for part in path:
        if isinstance(part, int):
            out += f"[{part}]"
        else:
            out += f".{part}" if out else part
    return out or "(root)"
