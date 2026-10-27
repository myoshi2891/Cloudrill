"""署名 → デコード → 形式 → アプリ版 → 試験 → 版戻し → ファイルの順で検証する。"""

import base64
import hashlib
import json
import re
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from contentvalidate.schemas import validator_for
from .versions import version_key


class VerificationError(ValueError):
    """code は Swift の PackVerificationError の case に対応する snake_case。"""

    def __init__(self, code: str, detail: str = "") -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}" if detail else code)


def _check_signature(directory: Path, key_ring: Mapping[str, Ed25519PublicKey]) -> tuple[bytes, set[str]]:
    try:
        raw = (directory / "manifest.json").read_bytes()
    except OSError as error:
        raise VerificationError("manifest_missing") from error
    try:
        encoded = (directory / "manifest.sig").read_bytes()
    except OSError as error:
        raise VerificationError("signature_missing") from error
    try:
        signature = base64.b64decode(encoded, validate=True)
        if len(signature) != 64 or base64.b64encode(signature) != encoded:
            raise ValueError("non-canonical signature")
    except ValueError as error:
        raise VerificationError("signature_invalid") from error
    verified_ids = set()
    for key_id, key in key_ring.items():
        try:
            key.verify(signature, raw)
            verified_ids.add(key_id)
        except InvalidSignature:
            continue
    if not verified_ids:
        raise VerificationError("signature_invalid")
    return raw, verified_ids


def _decode(raw: bytes, verified_ids: set[str]) -> dict[str, Any]:
    # 信頼できる鍵による署名が確認できるまで JSON を解析しない。
    try:
        manifest = json.loads(raw)
    except (ValueError, UnicodeError) as error:
        raise VerificationError("manifest_undecodable") from error
    validator = validator_for("manifest")
    for error in validator.iter_errors(manifest):
        # パスの形式はファイル検証段階で unsafe_path として報告する。
        if error.validator == "pattern" and list(error.absolute_path)[:1] == ["files"] and list(error.absolute_path)[-1:] == ["path"]:
            continue
        raise VerificationError("manifest_undecodable")
    if manifest["keyID"] not in verified_ids:
        raise VerificationError("signature_invalid")
    try:
        version_key(manifest["packVersion"])
        version_key(manifest["minAppVersion"])
    except ValueError as error:
        raise VerificationError("manifest_undecodable") from error
    return manifest


def _check_versions(manifest: dict[str, Any], app_version: str, supported_format_version: int,
                    expected_exam_id: str, current_version: str | None) -> None:
    if manifest["formatVersion"] > supported_format_version:
        raise VerificationError("unsupported_format", str(manifest["formatVersion"]))
    if version_key(app_version) < version_key(manifest["minAppVersion"]):
        raise VerificationError("app_too_old", manifest["minAppVersion"])
    if manifest["examID"] != expected_exam_id:
        raise VerificationError("exam_mismatch", manifest["examID"])
    if current_version is not None and version_key(manifest["packVersion"]) <= version_key(current_version):
        raise VerificationError("not_newer", manifest["packVersion"])


def _check_files(directory: Path, manifest: dict[str, Any]) -> None:
    validator = validator_for("manifest")
    root = directory.resolve()
    pattern = validator.schema["$defs"]["FileEntry"]["properties"]["path"]["pattern"]
    for entry in manifest["files"]:
        relative = entry["path"]
        path = root / relative
        if not re.fullmatch(pattern, relative) or not path.resolve().is_relative_to(root):
            raise VerificationError("unsafe_path", relative)
        if any(parent.is_symlink() for parent in (path, *path.parents) if parent != root and parent.is_relative_to(root)):
            raise VerificationError("unsafe_path", relative)
        try:
            if not path.is_file():
                raise VerificationError("file_missing", relative)
            if path.stat().st_size != entry["size"]:
                raise VerificationError("size_mismatch", relative)
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                while chunk := stream.read(1024 * 1024):
                    digest.update(chunk)
            if digest.hexdigest() != entry["sha256"]:
                raise VerificationError("hash_mismatch", relative)
        except OSError as error:
            raise VerificationError("file_missing", relative) from error


def verify_pack(
    directory: Path,
    *,
    key_ring: Mapping[str, Ed25519PublicKey],
    expected_exam_id: str,
    app_version: str = "1.0.0",
    current_version: str | None = None,
    supported_format_version: int = 1,
) -> dict[str, Any]:
    raw, verified_ids = _check_signature(directory, key_ring)
    manifest = _decode(raw, verified_ids)
    _check_versions(manifest, app_version, supported_format_version, expected_exam_id, current_version)
    _check_files(directory, manifest)
    return manifest
