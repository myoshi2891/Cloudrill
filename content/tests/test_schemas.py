"""JSON Schema 自体のテスト。"""

from __future__ import annotations

import json
from typing import Any

import pytest
import yaml
from jsonschema import Draft202012Validator

from conftest import VALID
from generate import ALPHA
from contentvalidate.schemas import SCHEMA_DIR, validator_for


def _errors(name: str, data: Any) -> list[str]:
    return [e.message for e in validator_for(name).iter_errors(data)]


@pytest.mark.parametrize("file", sorted(SCHEMA_DIR.glob("*.schema.json")), ids=lambda p: p.name)
def test_schema_is_valid_draft_2020_12(file) -> None:
    schema = json.loads(file.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["$id"].endswith(file.name)


def test_schema_ids_use_examprep_domain() -> None:
    ids = [json.loads(f.read_text(encoding="utf-8"))["$id"] for f in sorted(SCHEMA_DIR.glob("*.schema.json"))]
    assert ids
    assert all(i.startswith("https://examprep-content.invalid/schemas/") for i in ids), ids


MANIFEST = {
    "formatVersion": 1,
    "examID": "gcp-pca",
    "keyID": "content-2026",
    "packVersion": "1.2.0",
    "examGuideVersion": "6.1",
    "minAppVersion": "1.0.0",
    "createdAt": "2026-11-01T00:00:00Z",
    "files": [{"path": "questions/domain1.json", "sha256": "a" * 64, "size": 182334}],
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
        ("formatVersion", 0),
        ("examID", "GCP_PCA"),
        ("keyID", ""),
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


# --- exam.schema.json / vendors.schema.json(P0-S01) ---


def _named(id_: object, ja: str) -> dict[str, Any]:
    return {"id": id_, "name": {"ja": ja, "en": ja}}


def _exam(**overrides: Any) -> dict[str, Any]:
    """最小の試験定義(ドメイン1つ、サブ項目1つ、機能はすべて無効)。"""
    exam: dict[str, Any] = {
        "id": "test-exam",
        "vendor": "example-cloud",
        "name": {"ja": "テスト試験", "en": "Test exam"},
        "shortName": "TE",
        "guideVersion": "1.0",
        "guideURL": "https://example.com/guide",
        "format": {
            "durationMinutes": 60,
            "officialQuestionCount": {"min": 10, "max": 20},
            "questionKinds": ["single"],
            "mockExam": {"questionCount": 10, "setCount": 1, "caseStudiesPerSet": 0},
        },
        "scoring": {"policy": "allOrNothing"},
        "domains": [{**_named(1, "ドメイン1"), "weight": 1.0, "subObjectives": [_named("1.1", "サブ項目")]}],
        "features": {
            "caseStudies": False,
            "docs": False,
            "flashcards": False,
            "decisionTrees": False,
            "keywordDrills": False,
        },
        "taxonomies": {"wafPillars": []},
        "caseStudies": [],
    }
    exam.update(overrides)
    return exam


def _pca_exam() -> dict[str, Any]:
    weights = [0.25, 0.15, 0.18, 0.18, 0.12, 0.12]
    domains = [
        {**_named(d, f"ドメイン{d}"), "weight": w, "subObjectives": [_named(f"{d}.{s}", "サブ項目") for s in (1, 2)]}
        for d, w in enumerate(weights, start=1)
    ]
    pillars = ["operationalExcellence", "security", "reliability", "costOptimization", "performance", "sustainability"]
    return _exam(
        id="gcp-pca",
        vendor="google-cloud",
        shortName="PCA",
        guideVersion="6.1",
        guideURL="https://cloud.google.com/learn/certification/cloud-architect",
        format={
            "durationMinutes": 120,
            "officialQuestionCount": {"min": 50, "max": 60},
            "questionKinds": ["single", "multiple"],
            "mockExam": {"questionCount": 55, "setCount": 6, "caseStudiesPerSet": 2},
        },
        domains=domains,
        features=dict.fromkeys(("caseStudies", "docs", "flashcards", "decisionTrees", "keywordDrills"), True),
        taxonomies={"wafPillars": [_named(p, p) for p in pillars]},
        caseStudies=["ehr", "altostrat", "cymbal", "knightMotives"],
    )


def _with_format(**mock_or_kinds: Any) -> dict[str, Any]:
    exam = _exam()
    fmt = json.loads(json.dumps(exam["format"]))
    if "questionKinds" in mock_or_kinds:
        fmt["questionKinds"] = mock_or_kinds.pop("questionKinds")
    fmt["mockExam"].update(mock_or_kinds)
    exam["format"] = fmt
    return exam


def _with_domain(**fields: Any) -> dict[str, Any]:
    exam = _exam()
    exam["domains"] = [{**exam["domains"][0], **fields}]
    return exam


def test_exam_schema_accepts_minimal_definition() -> None:
    assert _errors("exam", _exam()) == []


def test_exam_schema_accepts_pca_definition() -> None:
    assert _errors("exam", _pca_exam()) == []


@pytest.mark.parametrize(
    "exam",
    [
        pytest.param(_exam(guideVersion=6.1), id="numeric_guide_version"),
        pytest.param(_with_domain(wieght=0.5), id="unknown_key"),
        pytest.param(_exam(id="GCP_PCA"), id="bad_exam_id"),
        pytest.param(_with_format(questionKinds=["single", "ordering"]), id="unknown_question_kind"),
        pytest.param(_with_domain(weight=1.5), id="weight_out_of_range"),
        pytest.param(_with_format(caseStudiesPerSet=-1), id="negative_cases_per_set"),
    ],
)
def test_exam_schema_rejects(exam: dict[str, Any]) -> None:
    assert _errors("exam", exam)


VENDOR = {
    "id": "google-cloud",
    "name": "Google Cloud",
    "trademarkNotice": {
        "ja": "本アプリは Google LLC とは関係のない非公式の学習教材です。Google Cloud は Google LLC の商標です。",
        "en": "This app is unofficial study material and is not affiliated with Google LLC. "
        "Google Cloud is a trademark of Google LLC.",
    },
    "defaultReferenceLicense": "CC-BY-4.0",
}


def test_vendors_schema_accepts_vendor() -> None:
    assert _errors("vendors", {"vendors": [VENDOR]}) == []


def test_vendors_schema_requires_trademark_notice_ja() -> None:
    vendor = {**VENDOR, "trademarkNotice": {"en": "only en"}}
    assert _errors("vendors", {"vendors": [vendor]})


def test_vendors_schema_rejects_empty_list() -> None:
    assert _errors("vendors", {"vendors": []})


# --- 共通 Schema の汎用化と manifest の変更(P0-S02) ---


def _sample_question() -> dict[str, Any]:
    """valid fixture の問題を1つ読み、テストごとに値を差し替える土台にする。"""
    file = sorted((VALID / ALPHA / "questions").rglob("*.yaml"))[0]
    return yaml.safe_load(file.read_text(encoding="utf-8"))


def test_sample_question_is_valid() -> None:
    # 以降のテストの前提(土台そのものが Schema に適合している)
    assert _errors("question", _sample_question()) == []


@pytest.mark.parametrize(
    "fields",
    [
        pytest.param({"subObjective": "NET.1", "id": "Q-NET.1-0001"}, id="non_numeric_sub_objective"),
        pytest.param({"domain": 7}, id="domain_above_six"),
        pytest.param({"caseStudy": "acmeBank"}, id="custom_case_study_id"),
        pytest.param({"wafPillars": ["resilience"]}, id="custom_waf_pillar"),
    ],
)
def test_question_schema_accepts(fields: dict[str, Any]) -> None:
    # 試験語彙の実在(domain・caseStudy・wafPillars)は Schema ではなく CI-09・CI-12 が確認する
    assert _errors("question", {**_sample_question(), **fields}) == []


@pytest.mark.parametrize(
    "fields",
    [
        pytest.param({"domain": 0}, id="domain_zero"),
        pytest.param({"caseStudy": "Acme Bank"}, id="bad_case_study_id"),
        pytest.param({"wafPillars": ["Resilience"]}, id="bad_waf_pillar_id"),
    ],
)
def test_question_schema_rejects_bad_vocabulary_format(fields: dict[str, Any]) -> None:
    assert _errors("question", {**_sample_question(), **fields})


def test_exam_sets_schema_accepts_zero_case_studies() -> None:
    exam_set = {"id": 1, "status": "draft", "level": "standard", "caseStudies": [], "questionIDs": []}
    assert _errors("exam-sets", {"examSets": [exam_set]}) == []


@pytest.mark.parametrize("field", ["examID", "formatVersion", "keyID"])
def test_manifest_schema_requires_exam_id_and_format_version(field: str) -> None:
    assert _errors("manifest", {k: v for k, v in MANIFEST.items() if k != field})


def test_manifest_schema_rejects_signature_field() -> None:
    # 署名は manifest.sig に分離した(DDD C-06)
    assert _errors("manifest", {**MANIFEST, "signature": "c2lnbmF0dXJl"})
