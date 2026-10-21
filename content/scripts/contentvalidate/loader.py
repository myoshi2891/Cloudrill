"""行番号を保持した YAML / フロントマターの読み込みと、JSON 相当への正規化。"""

from __future__ import annotations

import datetime as dt
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from .model import Issue, JsonPath, Kind, Severity, SourceDoc

# libyaml があれば C 実装を使う(500 ファイル規模での速度確保)
_Loader: type = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

LOAD_RULE = "CI-01"

# 種別ごとの探索パターン(root からの相対)。上から順に評価する
_SOURCES: tuple[tuple[Kind, str], ...] = (
    (Kind.QUESTION, "questions/**/*.y*ml"),
    (Kind.FLASHCARD, "flashcards/**/*.y*ml"),
    (Kind.CASE, "cases/**/*.y*ml"),
    (Kind.DECISION, "decisions/**/*.y*ml"),
    (Kind.DRILL, "drills/**/*.y*ml"),
    (Kind.DOCS, "docs/**/*.md"),
)
# 必須の単一ファイル
_REQUIRED_FILES: tuple[tuple[Kind, str], ...] = (
    (Kind.EXAM_SETS, "exam-sets.yaml"),
    (Kind.WEIGHTS, "weights.yaml"),
)


@dataclass
class LoadResult:
    docs: list[SourceDoc]
    issues: list[Issue]


class YamlLoadError(Exception):
    def __init__(self, message: str, line: int | None) -> None:
        super().__init__(message)
        self.line = line


def normalize(value: Any) -> Any:
    """YAML の値を JSON 相当に変換する(キーは str、日付は ISO 文字列)。"""
    if isinstance(value, dict):
        return {str(k): normalize(v) for k, v in value.items()}
    if isinstance(value, list):
        return [normalize(v) for v in value]
    if isinstance(value, (dt.date, dt.datetime)):
        return value.isoformat()
    return value


def _index(node: yaml.Node, path: JsonPath, lines: dict[JsonPath, int], offset: int, dups: list[tuple[str, int]]) -> None:
    """ノードを走査して パス → 行番号 を記録する。重複キーも検出する。"""
    lines.setdefault(path, node.start_mark.line + 1 + offset)
    if isinstance(node, yaml.MappingNode):
        seen: set[str] = set()
        for key_node, value_node in node.value:
            key = str(key_node.value)
            if key in seen:
                dups.append((key, key_node.start_mark.line + 1 + offset))
            seen.add(key)
            child = (*path, key)
            # マッピング要素はキーの行を指す方が読みやすい
            lines[child] = key_node.start_mark.line + 1 + offset
            _index(value_node, child, lines, offset, dups)
    elif isinstance(node, yaml.SequenceNode):
        for i, item in enumerate(node.value):
            _index(item, (*path, i), lines, offset, dups)


def parse_yaml(text: str, line_offset: int = 0) -> tuple[Any, dict[JsonPath, int], list[tuple[str, int]]]:
    """YAML を1回だけ compose し、データ・行マップ・重複キーを返す。"""
    loader = _Loader(text)
    try:
        node = loader.get_single_node()
        if node is None:
            return None, {}, []
        data = loader.construct_document(node)
    except yaml.MarkedYAMLError as e:
        mark = e.problem_mark or e.context_mark
        line = mark.line + 1 + line_offset if mark is not None else None
        raise YamlLoadError(f"YAML の構文エラー: {e.problem or e}", line) from e
    except yaml.YAMLError as e:
        raise YamlLoadError(f"YAML の読み込みエラー: {e}", None) from e
    finally:
        loader.dispose()
    lines: dict[JsonPath, int] = {}
    dups: list[tuple[str, int]] = []
    _index(node, (), lines, line_offset, dups)
    return normalize(data), lines, dups


def split_frontmatter(text: str) -> tuple[str, int] | None:
    """Markdown 先頭の `---` で囲まれたフロントマターを返す。(本文, 先頭行オフセット)。"""
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        return None
    for i in range(1, len(lines)):
        if lines[i].rstrip("\r\n") in ("---", "..."):
            return "".join(lines[1:i]), 1
    return None


def _load_file(root: Path, file: Path, kind: Kind) -> tuple[SourceDoc | None, list[Issue]]:
    rel = file.relative_to(root).as_posix()
    try:
        text = file.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        return None, [Issue(rel, None, LOAD_RULE, Severity.ERROR, f"ファイルを読み込めません: {e}")]

    offset = 0
    if kind is Kind.DOCS:
        front = split_frontmatter(text)
        if front is None:
            return None, [Issue(rel, 1, LOAD_RULE, Severity.ERROR, "YAML フロントマター(--- で囲まれた先頭ブロック)がありません")]
        text, offset = front

    try:
        data, lines, dups = parse_yaml(text, offset)
    except YamlLoadError as e:
        return None, [Issue(rel, e.line, LOAD_RULE, Severity.ERROR, str(e))]

    issues = [Issue(rel, line, LOAD_RULE, Severity.ERROR, f"キー '{key}' が重複しています") for key, line in dups]
    return SourceDoc(rel, kind, data, lines), issues


def iter_sources(root: Path) -> Iterator[tuple[Kind, Path]]:
    for kind, pattern in _SOURCES:
        for file in sorted(root.glob(pattern)):
            if file.is_file():
                yield kind, file


def load_content(root: Path) -> LoadResult:
    docs: list[SourceDoc] = []
    issues: list[Issue] = []

    for kind, name in _REQUIRED_FILES:
        file = root / name
        if not file.is_file():
            issues.append(Issue(name, None, LOAD_RULE, Severity.ERROR, f"必須ファイル {name} がありません"))
            continue
        doc, errs = _load_file(root, file, kind)
        issues.extend(errs)
        if doc is not None:
            docs.append(doc)

    for kind, file in iter_sources(root):
        doc, errs = _load_file(root, file, kind)
        issues.extend(errs)
        if doc is not None:
            docs.append(doc)

    return LoadResult(docs, issues)
