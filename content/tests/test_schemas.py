"""JSON Schema 自体のテスト。"""

from __future__ import annotations

import json
from typing import Any

import pytest
from jsonschema import Draft202012Validator

from pcavalidate.schemas import SCHEMA_DIR, validator_for


def _errors(name: str, data: Any) -> list[str]:
    return [e.message for e in validator_for(name).iter_errors(data)]


@pytest.mark.parametrize("file", sorted(SCHEMA_DIR.glob("*.schema.json")), ids=lambda p: p.name)
def test_schema_is_valid_draft_2020_12(file) -> None:
    schema = json.loads(file.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"].endswith(file.name)


MANIFEST = {
    "packVersion": "1.2.0",
    "examGuideVersion": "6.1",
    "minAppVersion": "1.0.0",
    "createdAt": "2026-11-01T00:00:00Z",
    "files": [{"path": "questions/domain1.json", "sha256": "a" * 64, "size": 182334}],
    "signature": "c2lnbmF0dXJl",
}


def test_manifest_accepts_valid_example() -> None:
    assert _errors("manifest", MANIFEST) == []


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("packVersion", "1.2"),
        ("minAppVersion", "v1.0.0"),
        ("files", [{"path": "a.json", "sha256": "XYZ", "size": 1}]),
        ("files", [{"path": "../etc/passwd", "sha256": "a" * 64, "size": 1}]),
        ("files", []),
        ("signature", "not base64!"),
    ],
)
def test_manifest_rejects_invalid_values(field: str, value: Any) -> None:
    assert _errors("manifest", {**MANIFEST, field: value})


@pytest.mark.parametrize(
    ("qtype", "ok"),
    [
        ({"kind": "single"}, True),
        ({"kind": "single", "count": 2}, False),
        ({"kind": "multiple", "count": 2}, True),
        ({"kind": "multiple"}, False),
        ({"kind": "multiple", "count": 1}, False),
        ({"kind": "ordering"}, False),
    ],
)
def test_question_type(qtype: dict[str, Any], ok: bool) -> None:
    schema = validator_for("question").schema["$defs"]["QuestionType"]
    errors = list(validator_for("question").evolve(schema=schema).iter_errors(qtype))
    assert (not errors) is ok


def test_decision_option_requires_exactly_one_of_next_or_result() -> None:
    schema = validator_for("decision").schema["$defs"]["Option"]
    validator = validator_for("decision").evolve(schema=schema)
    label = {"ja": "はい", "en": "Yes"}
    result = {"service": "GKE", "rationale": {"ja": "理由"}}
    assert not list(validator.iter_errors({"label": label, "next": "n2"}))
    assert not list(validator.iter_errors({"label": label, "result": result}))
    assert list(validator.iter_errors({"label": label, "next": "n2", "result": result}))
    assert list(validator.iter_errors({"label": label}))


@pytest.mark.parametrize("url", ["http://example.com", "ftp://example.com/x", "https://", "https://exa mple.com"])
def test_reference_requires_https_url(url: str) -> None:
    schema = validator_for("common").schema["$defs"]["Reference"]
    validator = validator_for("common").evolve(schema=schema)
    assert list(validator.iter_errors({"title": "t", "url": url, "license": "link-only"}))


def test_localized_text_requires_non_empty_ja() -> None:
    schema = validator_for("common").schema["$defs"]["LocalizedText"]
    validator = validator_for("common").evolve(schema=schema)
    assert not list(validator.iter_errors({"ja": "あ"}))
    assert list(validator.iter_errors({"ja": ""}))
    assert list(validator.iter_errors({"en": "only en"}))
    assert list(validator.iter_errors({"ja": "あ", "fr": "x"}))
