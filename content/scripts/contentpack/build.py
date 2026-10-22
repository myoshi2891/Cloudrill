"""YAML のコンテンツから、1つの試験の配信パック(DDD-P2 3.1、formatVersion 1)を作る。

署名(manifest.sig)は作らない。署名は sign_manifest.py が行う(P2-S03)。
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import re
import shutil
import tempfile
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from contentvalidate.config import ConfigError, load_config, resolve_config_path
from contentvalidate.engine import run
from contentvalidate.loader import exam_dirs, load_content, strip_frontmatter
from contentvalidate.model import Issue, Kind, Severity, SourceDoc, get_list, get_str
from contentvalidate.schemas import registry, schema_uri, validator_for

FORMAT_VERSION = 1
MANIFEST = "manifest.json"
_SEMVER = re.compile(registry().contents(schema_uri("common"))["$defs"]["SemVer"]["pattern"])


class BuildError(Exception):
    """引数・環境の不備、または出力先がすでにある。CLI は終了コード 2 で終了する。"""


class ContentInvalid(Exception):
    """コンテンツの検証で error がある。CLI は終了コード 1 で終了する。"""

    def __init__(self, issues: list[Issue]) -> None:
        super().__init__(f"コンテンツの検証で error が {sum(i.severity is Severity.ERROR for i in issues)} 件あります")
        self.issues = issues


@dataclass(frozen=True)
class BuiltPack:
    path: Path
    # error でない検出結果(warning)。ビルドは止めない
    warnings: list[Issue]


def canonical_json(data: Any) -> bytes:
    """パックの JSON の書式: キーを並べ替え、空白なし、UTF-8、末尾に改行なし。"""
    return json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


# ---- 種別ごとの変換 ---------------------------------------------------------


@dataclass(frozen=True)
class _Source:
    """ビルドに使う、1つの試験のロード済みコンテンツ(検証済み)。"""

    root: Path
    exam: dict[str, Any]
    docs: list[SourceDoc]

    def of_kind(self, kind: Kind) -> list[SourceDoc]:
        return [d for d in self.docs if d.kind is kind]


def _by_id(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(items, key=lambda item: str(item["id"]))


def _items(docs: list[SourceDoc], key: str) -> list[dict[str, Any]]:
    """配列のラッパー({ cards: [...] } など)を、ファイルをまたいで1つにまとめる。"""
    return _by_id([item for doc in docs for item in get_list(doc.data, key)])


def _questions(source: _Source, docs: list[SourceDoc]) -> dict[str, Any]:
    questions = _by_id([doc.data for doc in docs])
    index = [
        {
            "id": q["id"],
            "revision": q["revision"],
            "domain": q["domain"],
            "subObjective": q["subObjective"],
            "caseStudy": q["caseStudy"],
            "difficulty": q["difficulty"],
            "kind": q["type"]["kind"],
            "examSets": q["examSets"],
        }
        for q in questions
    ]
    # 問題のないドメインも空の配列で出す(読み込み側がドメインのファイルの有無で分岐しなくて済むように)
    files: dict[str, Any] = {"questions/index.json": index}
    for domain in source.exam["domains"]:
        files[f"questions/domain{domain['id']}.json"] = [q for q in questions if q["domain"] == domain["id"]]
    return files


def _docs(source: _Source, docs: list[SourceDoc]) -> dict[str, Any]:
    # docs/index.json は起動時に読むので、features.docs が false でも空の配列で出す
    if not source.exam["features"]["docs"]:
        return {"docs/index.json": []}
    files: dict[str, Any] = {}
    index: list[dict[str, Any]] = []
    for doc in sorted(docs, key=lambda d: d.data["subObjective"]):
        path = f"docs/{doc.data['subObjective']}.md"
        if path in files:
            raise BuildError(f"{doc.path}: subObjective {doc.data['subObjective']} の docs が複数あります")
        body = strip_frontmatter((source.root / doc.path).read_text(encoding="utf-8"))
        if body is None:  # 検証(CI-01)を通っていればここには来ない
            raise BuildError(f"{doc.path}: フロントマターがありません")
        files[path] = body.encode("utf-8")
        index.append({**doc.data, "path": path})
    files["docs/index.json"] = index
    return files


@dataclass(frozen=True)
class _Artifact:
    """種別ごとの変換。feature が None でなければ、exam.yaml の features[feature] が true のときだけ出力する。"""

    kind: Kind
    feature: str | None
    convert: Callable[[_Source, list[SourceDoc]], dict[str, Any]]


# 新しい種別を追加するときは、ここに1行足す
_ARTIFACTS: tuple[_Artifact, ...] = (
    _Artifact(Kind.EXAM_SETS, None, lambda _, docs: {"exam-sets.json": docs[0].data}),
    _Artifact(Kind.QUESTION, None, _questions),
    _Artifact(Kind.FLASHCARD, "flashcards", lambda _, docs: {"flashcards.json": {"cards": _items(docs, "cards")}}),
    _Artifact(Kind.CASE, "caseStudies", lambda _, docs: {"cases.json": _by_id([d.data for d in docs])}),
    _Artifact(Kind.DECISION, "decisionTrees", lambda _, docs: {"decisions.json": _by_id([d.data for d in docs])}),
    _Artifact(Kind.DRILL, "keywordDrills", lambda _, docs: {"drills.json": {"drills": _items(docs, "drills")}}),
    _Artifact(Kind.DOCS, None, _docs),
)


def _pack_files(source: _Source, vendors: list[SourceDoc]) -> dict[str, bytes]:
    vendor_id = source.exam["vendor"]
    vendor = next(v for doc in vendors for v in get_list(doc.data, "vendors") if get_str(v, "id") == vendor_id)
    files: dict[str, Any] = {"exam.json": source.exam, "vendor.json": vendor}
    for artifact in _ARTIFACTS:
        if artifact.feature is not None and not source.exam["features"][artifact.feature]:
            continue
        files.update(artifact.convert(source, source.of_kind(artifact.kind)))
    return {path: data if isinstance(data, bytes) else canonical_json(data) for path, data in files.items()}


# ---- ビルド -----------------------------------------------------------------


def _check_arguments(root: Path, exam_id: str, version: str, min_app_version: str, key_id: str, epoch: int) -> None:
    if exam_id not in {d.name for d in exam_dirs(root)}:
        raise BuildError(f"試験 {exam_id} がありません({root}/exams/)")
    for name, value in (("--version", version), ("--min-app-version", min_app_version)):
        if not _SEMVER.fullmatch(value):
            raise BuildError(f"{name} {value} は SemVer(X.Y.Z)ではありません")
    if not key_id:
        raise BuildError("--key-id が空です")
    if epoch < 0:
        raise BuildError(f"SOURCE_DATE_EPOCH {epoch} は 0 以上にしてください")


def _validate(root: Path, exam_id: str, config_path: Path | None) -> list[Issue]:
    """validate.py と同じ検証を、この試験だけについて行う。error があれば ContentInvalid。"""
    try:
        issues = run(root, load_config(resolve_config_path(root, config_path)), exam_ids=frozenset({exam_id}))
    except ConfigError as e:
        raise BuildError(str(e)) from e
    if any(i.severity is Severity.ERROR for i in issues):
        raise ContentInvalid(issues)
    return issues


def _manifest(exam: dict[str, Any], version: str, min_app_version: str, key_id: str, epoch: int, files: dict[str, bytes]) -> dict[str, Any]:
    manifest = {
        "formatVersion": FORMAT_VERSION,
        "examID": exam["id"],
        "packVersion": version,
        "examGuideVersion": exam["guideVersion"],
        "minAppVersion": min_app_version,
        "createdAt": dt.datetime.fromtimestamp(epoch, dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "keyID": key_id,
        "files": [
            {"path": path, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
            for path, data in sorted(files.items())
        ],
    }
    errors = [e.message for e in validator_for("manifest").iter_errors(manifest)]
    if errors:  # パスの形などは Schema が正。ここで違反するのはビルドの不具合
        raise BuildError(f"manifest が Schema に適合しません: {errors[0]}")
    return manifest


def _write(target: Path, files: dict[str, bytes]) -> None:
    """一時ディレクトリに書いてから rename する(途中で失敗しても、不完全なパックを残さない)。"""
    target.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{target.name}.", dir=target.parent))
    try:
        for path, data in files.items():
            file = staging / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(data)
        staging.rename(target)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def build_pack(
    root: Path,
    exam_id: str,
    version: str,
    min_app_version: str,
    key_id: str,
    out: Path,
    epoch: int,
    *,
    config_path: Path | None = None,
) -> BuiltPack:
    """<out>/<examID>/<version>/ にパックを作る。出力先がすでにあれば BuildError(上書きしない)。"""
    _check_arguments(root, exam_id, version, min_app_version, key_id, epoch)
    target = out / exam_id / version
    if target.exists():
        raise BuildError(f"出力先 {target} がすでにあります")
    warnings = _validate(root, exam_id, config_path)

    loaded = load_content(root, frozenset({exam_id}))
    exam_doc = next(d for d in loaded.docs if d.kind is Kind.EXAM)
    source = _Source(root, exam_doc.data, [d for d in loaded.docs if d.exam_id == exam_id])
    files = _pack_files(source, [d for d in loaded.docs if d.kind is Kind.VENDORS])
    manifest = _manifest(source.exam, version, min_app_version, key_id, epoch, files)
    # manifest.json だけは読みやすさのため indent=2(署名はバイト列に対して行うので、書式は検証に影響しない)
    files[MANIFEST] = json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2).encode("utf-8")
    _write(target, files)
    return BuiltPack(target, warnings)
