"""catalog.yaml と試験定義・配信済みの版から、決定論的にカタログを作る。"""

import datetime as dt
import json
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from contentvalidate.loader import YamlLoadError, exam_dirs, parse_yaml
from contentvalidate.schemas import validator_for
from .build import _MAX_EPOCH
from .versions import version_key


class CatalogError(ValueError):
    """カタログの入力が不正。CLI は終了コード 2 を返す。"""


def _read(path: Path, schema: str, *, yaml: bool = False) -> dict[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
        if yaml:
            data, _, duplicates = parse_yaml(raw)
            if duplicates:
                raise CatalogError(f"{path}: YAML キーが重複しています")
        else:
            data = json.loads(raw)
    except (OSError, ValueError, UnicodeError, YamlLoadError) as error:
        raise CatalogError(f"{path}: 読み込めません") from error
    if not validator_for(schema).is_valid(data):
        raise CatalogError(f"{path}: {schema} Schema に適合しません")
    return data


def _by_id(entries: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    result = {}
    for entry in entries:
        if entry["id"] in result:
            raise CatalogError(f"試験 {entry['id']} が重複しています")
        result[entry["id"]] = entry
    return result


def build_catalog(
    root: Path,
    *,
    epoch: int,
    previous: Path | None = None,
    updates: Mapping[str, Path] | None = None,
) -> dict[str, Any]:
    if not 0 <= epoch <= _MAX_EPOCH:
        raise CatalogError("SOURCE_DATE_EPOCH が範囲外です")
    source = _by_id(_read(root / "catalog.yaml", "catalog-source", yaml=True)["exams"])
    known = {path.name for path in exam_dirs(root)}
    if missing := source.keys() - known:
        raise CatalogError(f"試験がありません: {', '.join(sorted(missing))}")
    old = _by_id(_read(previous, "catalog")["exams"]) if previous is not None else {}
    updates = updates or {}
    if unknown := updates.keys() - source.keys():
        raise CatalogError(f"カタログにない試験の更新です: {', '.join(sorted(unknown))}")
    entries = []
    for exam_id, entry in sorted(source.items()):
        definition = _read(root / "exams" / exam_id / "exam.yaml", "exam", yaml=True)
        if definition["id"] != exam_id:
            raise CatalogError(f"試験定義の ID が一致しません: {exam_id}")
        prior = old.get(exam_id, {})
        version, minimum = prior.get("latestPackVersion"), prior.get("minAppVersion")
        if exam_id in updates:
            manifest = _read(updates[exam_id], "manifest")
            if manifest["examID"] != exam_id:
                raise CatalogError(f"manifest の試験 ID が一致しません: {exam_id}")
            if version is not None and version_key(manifest["packVersion"]) < version_key(version):
                raise CatalogError(f"パックの版を巻き戻せません: {exam_id}")
            version, minimum = manifest["packVersion"], manifest["minAppVersion"]
        entries.append({**entry, **{k: definition[k] for k in ("name", "shortName", "vendor")},
                        "latestPackVersion": version, "minAppVersion": minimum})
    result = {"formatVersion": 1, "generatedAt": dt.datetime.fromtimestamp(epoch, dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
              "exams": entries}
    if not validator_for("catalog").is_valid(result):
        raise CatalogError("カタログが Schema に適合しません。available の試験にはパックの版が必要です")
    return result
