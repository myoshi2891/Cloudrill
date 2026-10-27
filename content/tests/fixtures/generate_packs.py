#!/usr/bin/env python3
"""Python / Swift 共通の署名付き契約 fixture を再生成する(P2-S04)。

    content/.venv/bin/python content/tests/fixtures/generate_packs.py [--out <packs>]

秘密鍵はファイルに保存しない。出力先は生成専用ディレクトリとし、再生成時に置き換える。
"""

from __future__ import annotations

import argparse
import base64
import json
import shutil
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "scripts"))

from contentpack.build import build_pack
from contentpack.catalog import build_catalog
from contentpack.files import canonical_json
from contentpack.sign import sign_manifest
from contentpack.testing import test_signing_key
from generate import dump, generate
from contentvalidate.loader import parse_yaml

EPOCH = 1793491200
KEY_ID = "test-2026"


@dataclass(frozen=True)
class TamperedCase:
    directory: str
    error: str
    expected_exam_id: str = "test-alpha"


TAMPERED_CASES = (
    TamperedCase("bad-signature", "signature_invalid"),
    TamperedCase("unknown-key", "signature_invalid"),
    TamperedCase("hash-mismatch", "hash_mismatch"),
    TamperedCase("size-mismatch", "size_mismatch"),
    TamperedCase("missing-file", "file_missing"),
    TamperedCase("app-too-old", "app_too_old"),
    TamperedCase("unsupported-format", "unsupported_format"),
    TamperedCase("exam-mismatch", "exam_mismatch", "test-beta"),
    TamperedCase("path-traversal", "unsafe_path"),
)


def _sign_raw(pack: Path, label: str = KEY_ID) -> None:
    """意図的に Schema 違反の manifest も署名する。製品の sign_manifest の検証は迂回する。"""
    signature = test_signing_key(label).sign((pack / "manifest.json").read_bytes())
    (pack / "manifest.sig").write_bytes(base64.b64encode(signature))


def _tamper(pack: Path, case: str) -> None:
    manifest_file = pack / "manifest.json"
    manifest = json.loads(manifest_file.read_bytes())
    if case == "bad-signature":
        raw = manifest_file.read_bytes()
        # JSON としては有効なまま、先頭の改行だけを空白にする。
        manifest_file.write_bytes(raw.replace(b"\n", b" ", 1))
        return
    if case == "unknown-key":
        _sign_raw(pack, "outsider")
        return
    if case == "hash-mismatch":
        file = pack / "questions/domain1.json"
        raw = file.read_bytes()
        file.write_bytes(b" " + raw[1:])  # size は変えない。
        return
    if case == "missing-file":
        (pack / "exam-sets.json").unlink()
        return
    if case == "size-mismatch":
        manifest["files"][0]["size"] += 1
    elif case == "app-too-old":
        manifest["minAppVersion"] = "99.0.0"
    elif case == "unsupported-format":
        manifest["formatVersion"] = 2
    elif case == "exam-mismatch":
        manifest["examID"] = "test-alpha"
    elif case == "path-traversal":
        manifest["files"][0]["path"] = "../outside.json"
    else:
        raise ValueError(f"unknown tampering case: {case}")
    manifest_file.write_bytes(canonical_json(manifest))
    _sign_raw(pack)


def _build_valid(source: Path, out: Path) -> dict[tuple[str, str], Path]:
    packs = {}
    for exam, version in (("test-alpha", "1.0.0"), ("test-beta", "1.0.0"), ("test-alpha", "1.1.0")):
        if version == "1.1.0":
            file = sorted((source / "exams" / exam / "questions").rglob("*.yaml"))[0]
            question, _, _ = parse_yaml(file.read_text(encoding="utf-8"))
            question["revision"] += 1
            question["choices"][0]["rationale"]["ja"] += "。改訂版の補足説明。"
            question["choices"][0]["rationale"]["en"] += " Revised explanation."
            file.write_text(dump(question), encoding="utf-8")
        pack = build_pack(source, exam, version, "1.0.0", KEY_ID, out / "valid", EPOCH).path
        sign_manifest(pack / "manifest.json", KEY_ID, test_signing_key(KEY_ID))
        packs[(exam, version)] = pack
    return packs


def _ensure_replaceable(out: Path) -> None:
    """生成物と判別できない既存の出力先は削除しない。空のディレクトリは置き換えてよい。"""
    if not out.exists() and not out.is_symlink():
        return
    if out.is_symlink() or not out.is_dir():
        raise ValueError(f"出力先がディレクトリではありません: {out}")
    if any(out.iterdir()) and not (out / "test-keys.json").is_file():
        raise ValueError(f"生成済みの契約パックではないため置き換えません: {out}")


def generate_packs(out: Path = HERE / "packs") -> None:
    _ensure_replaceable(out)
    with tempfile.TemporaryDirectory(prefix="content-contract-") as temporary:
        working = Path(temporary)
        generate(working / "fixtures")
        source = working / "fixtures/valid"
        generated = working / "packs"
        packs = _build_valid(source, generated)
        keys = {label: base64.b64encode(test_signing_key(label).public_key().public_bytes_raw()).decode("ascii")
                for label in (KEY_ID, "test-next")}
        (generated / "test-keys.json").write_bytes(canonical_json(keys))
        (source / "catalog.yaml").write_text(dump({"exams": [
            {"id": exam, "status": "available", "productIDs": []} for exam in ("test-alpha", "test-beta")
        ]}), encoding="utf-8")
        catalog = build_catalog(source, epoch=EPOCH, updates={
            exam: packs[(exam, version)] / "manifest.json"
            for exam, version in (("test-alpha", "1.1.0"), ("test-beta", "1.0.0"))
        })
        (generated / "catalog.json").write_bytes(canonical_json(catalog))
        for case in TAMPERED_CASES:
            target = generated / "tampered" / case.directory
            shutil.copytree(packs[(case.expected_exam_id, "1.0.0")], target)
            _tamper(target, case.directory)
        expected = [{"directory": case.directory, "error": case.error, "expectedExamID": case.expected_exam_id}
                    for case in TAMPERED_CASES]
        (generated / "tampered/expected.json").write_bytes(canonical_json(expected))
        if out.exists():
            shutil.rmtree(out)
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(generated, out)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=HERE / "packs")
    args = parser.parse_args()
    try:
        generate_packs(args.out)
    except ValueError as error:
        parser.error(str(error))
    print(f"generated: {args.out}")
