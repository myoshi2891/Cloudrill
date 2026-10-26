"""コミット済みの生成物(fixture と Swift 用 JSON)が、生成スクリプトの出力と一致すること。"""

from __future__ import annotations

from pathlib import Path

import base64
import json

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from conftest import FIXTURES, VALID
from export_json import DEFAULT_OUT, export
from generate import generate
from generate_packs import generate_packs
from contentpack.verify import VerificationError, verify_pack


def _tree(base: Path) -> dict[str, bytes]:
    return {p.relative_to(base).as_posix(): p.read_bytes() for p in sorted(base.rglob("*")) if p.is_file()}


def test_fixtures_are_up_to_date(tmp_path: Path) -> None:
    generate(tmp_path)
    for name in ("valid", "invalid"):
        assert _tree(tmp_path / name) == _tree(FIXTURES / name), (
            f"content/tests/fixtures/{name} が古くなっています。python content/tests/fixtures/generate.py を実行してください"
        )


def test_swift_fixtures_are_up_to_date(tmp_path: Path) -> None:
    export(VALID, tmp_path / "out")
    assert _tree(tmp_path / "out") == _tree(DEFAULT_OUT), (
        "Swift 用 JSON が古くなっています。python content/scripts/export_json.py を実行してください"
    )
    assert DEFAULT_OUT == FIXTURES / "valid-json"


def test_export_skips_validation_yaml(tmp_path: Path) -> None:
    # Arrange: valid には試験ごとの validation.yaml がある
    assert (VALID / "exams/test-alpha/validation.yaml").is_file()
    # Act
    written = export(VALID, tmp_path / "out")
    # Assert: 検証ツールの設定はアプリ向けの JSON に出力しない
    assert all(p.name != "validation.json" for p in written)


def test_export_includes_exam_and_vendors(tmp_path: Path) -> None:
    # Arrange
    out = tmp_path / "out"
    # Act
    export(VALID, out)
    # Assert: 全体のファイルと試験ごとの試験定義が、valid と同じ構成(exams/<examID>/…)で出力される
    assert (out / "vendors.json").is_file()
    assert (out / "exams/test-alpha/exam.json").is_file()
    assert (out / "exams/test-beta/exam.json").is_file()


PACKS = FIXTURES / "packs"
VALID_PACKS = [("test-alpha", "1.0.0"), ("test-alpha", "1.1.0"), ("test-beta", "1.0.0")]
TAMPERED = {
    "bad-signature": "signature_invalid",
    "unknown-key": "signature_invalid",
    "hash-mismatch": "hash_mismatch",
    "size-mismatch": "size_mismatch",
    "missing-file": "file_missing",
    "app-too-old": "app_too_old",
    "unsupported-format": "unsupported_format",
    "exam-mismatch": "exam_mismatch",
    "path-traversal": "unsafe_path",
}


def _key_ring():
    data = json.loads((PACKS / "test-keys.json").read_bytes())
    assert set(data) == {"test-2026", "test-next"}
    return {key_id: Ed25519PublicKey.from_public_bytes(base64.b64decode(value, validate=True)) for key_id, value in data.items()}


def test_packs_match_generator(tmp_path: Path) -> None:
    out = tmp_path / "packs"
    generate_packs(out)
    assert _tree(out)  # 生成処理が何もしない仮実装で通らないこと。
    assert _tree(out) == _tree(PACKS)
    (out / "obsolete.txt").write_text("stale output", encoding="utf-8")
    generate_packs(out)  # 再生成も同じ結果で、古い出力を残さない。
    assert _tree(out) == _tree(PACKS)


@pytest.mark.parametrize("exam,version", VALID_PACKS)
def test_valid_packs_verify(exam: str, version: str) -> None:
    manifest = verify_pack(PACKS / "valid" / exam / version, key_ring=_key_ring(), expected_exam_id=exam)
    assert manifest["packVersion"] == version
    assert manifest["createdAt"] == "2026-11-01T00:00:00Z"


@pytest.mark.parametrize("case,code", TAMPERED.items())
def test_tampered_packs_fail_with_expected_error(case: str, code: str) -> None:
    expected = json.loads((PACKS / "tampered/expected.json").read_bytes())
    assert {row["directory"]: row["error"] for row in expected} == TAMPERED
    row = next(row for row in expected if row["directory"] == case)
    with pytest.raises(VerificationError) as caught:
        verify_pack(PACKS / "tampered" / case, key_ring=_key_ring(), expected_exam_id=row["expectedExamID"])
    assert caught.value.code == code


def test_revised_pack_changes_one_question() -> None:
    def questions(version):
        return {q["id"]: q for file in (PACKS / "valid/test-alpha" / version / "questions").glob("domain*.json")
                for q in json.loads(file.read_bytes())}
    before, after = questions("1.0.0"), questions("1.1.0")
    assert before and before.keys() == after.keys()
    changed = [key for key in before if before[key] != after[key]]
    assert len(changed) == 1
    key = changed[0]
    assert after[key]["revision"] == before[key]["revision"] + 1


def test_pack_catalog_describes_both_exams() -> None:
    from contentvalidate.schemas import validator_for
    catalog = json.loads((PACKS / "catalog.json").read_bytes())
    assert validator_for("catalog").is_valid(catalog)
    assert [entry["id"] for entry in catalog["exams"]] == ["test-alpha", "test-beta"]
    assert all(entry["status"] == "available" for entry in catalog["exams"])
    assert [entry["latestPackVersion"] for entry in catalog["exams"]] == ["1.1.0", "1.0.0"]
