"""JSON Schema の Registry 構築と Validator のキャッシュ。"""

from __future__ import annotations

import json
from functools import cache
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

from .model import Kind

SCHEMA_DIR = Path(__file__).resolve().parents[2] / "schemas"
SCHEMA_BASE = "https://examprep-content.invalid/schemas/"


@cache
def registry(schema_dir: Path = SCHEMA_DIR) -> Registry:
    """schemas/ 配下の全 Schema を $id で登録した Registry(外部取得は行わない)。"""
    resources: list[tuple[str, Resource]] = []
    for file in sorted(schema_dir.glob("*.schema.json")):
        contents = json.loads(file.read_text(encoding="utf-8"))
        resources.append((contents["$id"], Resource.from_contents(contents, default_specification=DRAFT202012)))
    return Registry().with_resources(resources)


def schema_uri(name: str) -> str:
    return f"{SCHEMA_BASE}{name}.schema.json"


@cache
def validator_for(name: str, schema_dir: Path = SCHEMA_DIR) -> Draft202012Validator:
    reg = registry(schema_dir)
    schema = reg.contents(schema_uri(name))
    return Draft202012Validator(schema, registry=reg, format_checker=Draft202012Validator.FORMAT_CHECKER)


def validator_for_kind(kind: Kind) -> Draft202012Validator:
    return validator_for(str(kind))
