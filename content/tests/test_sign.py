"""P2-S03: Ed25519 の署名と、Swift と共有する検証の順序。"""

import base64
import hashlib
import json
import shutil
from pathlib import Path

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from conftest import VALID
from contentpack.build import build_pack
from contentpack.sign import sign_manifest
from contentpack.testing import test_signing_key as signing_key
from contentpack.verify import VerificationError, verify_pack
from sign_manifest import main


@pytest.fixture(scope="module")
def unsigned(tmp_path_factory):
    return build_pack(VALID, "test-alpha", "1.0.0", "1.0.0", "test-2026",
                      tmp_path_factory.mktemp("unsigned"), 1793491200).path


@pytest.fixture
def pack(unsigned, tmp_path):
    result = tmp_path / "pack"
    shutil.copytree(unsigned, result)
    sign_manifest(result / "manifest.json", "test-2026", signing_key("test-2026"))
    return result


def verify(pack, **kwargs):
    return verify_pack(pack, key_ring={"test-2026": signing_key("test-2026").public_key()},
                       expected_exam_id="test-alpha", **kwargs)


def rewrite(pack, **changes):
    path = pack / "manifest.json"
    manifest = json.loads(path.read_bytes())
    manifest.update(changes)
    path.write_text(json.dumps(manifest), encoding="utf-8")
    sign_manifest(path, manifest["keyID"], signing_key("test-2026"))


def test_test_key_uses_specified_seed():
    expected = Ed25519PrivateKey.from_private_bytes(hashlib.sha256(b"examprep-test-key:test-2026").digest())
    assert signing_key("test-2026").public_key().public_bytes_raw() == expected.public_key().public_bytes_raw()


def test_sign_and_verify(pack):
    assert verify(pack)["packVersion"] == "1.0.0"


def test_signature_is_deterministic(pack):
    before = (pack / "manifest.sig").read_bytes()
    sign_manifest(pack / "manifest.json", "test-2026", signing_key("test-2026"))
    assert (pack / "manifest.sig").read_bytes() == before


def test_sig_format(pack):
    raw = (pack / "manifest.sig").read_bytes()
    assert b"\n" not in raw
    assert len(base64.b64decode(raw, validate=True)) == 64
    signing_key("test-2026").public_key().verify(base64.b64decode(raw), (pack / "manifest.json").read_bytes())


def test_sign_preserves_manifest_bytes(pack):
    before = (pack / "manifest.json").read_bytes()
    assert main(["--manifest", str(pack / "manifest.json"), "--key-id", "test-2026", "--test-key", "test-2026"]) == 0
    assert (pack / "manifest.json").read_bytes() == before


def test_key_id_mismatch_exits_2(pack):
    before = (pack / "manifest.sig").read_bytes()
    assert main(["--manifest", str(pack / "manifest.json"), "--key-id", "wrong", "--test-key", "test-2026"]) == 2
    assert (pack / "manifest.sig").read_bytes() == before


def test_key_env(pack, monkeypatch):
    monkeypatch.setenv("PACK_TEST_SEED", base64.b64encode(signing_key("test-2026").private_bytes_raw()).decode())
    assert main(["--manifest", str(pack / "manifest.json"), "--key-id", "test-2026", "--key-env", "PACK_TEST_SEED"]) == 0
    assert verify(pack)["keyID"] == "test-2026"


@pytest.mark.parametrize("seed", [None, "secret-not-base64", base64.b64encode(b"too short").decode()])
def test_invalid_key_env_is_not_disclosed(pack, monkeypatch, capsys, seed):
    if seed is None:
        monkeypatch.delenv("PACK_TEST_SEED", raising=False)
    else:
        monkeypatch.setenv("PACK_TEST_SEED", seed)
    assert main(["--manifest", str(pack / "manifest.json"), "--key-id", "test-2026", "--key-env", "PACK_TEST_SEED"]) == 2
    output = capsys.readouterr()
    assert "Traceback" not in output.err
    if seed:
        assert seed not in output.err + output.out


@pytest.mark.parametrize("raw", [b"{", b"[]", b'{}'])
def test_sign_rejects_invalid_manifest(pack, raw):
    (pack / "manifest.json").write_bytes(raw)
    assert main(["--manifest", str(pack / "manifest.json"), "--key-id", "test-2026", "--test-key", "test-2026"]) == 2


@pytest.mark.parametrize("raw", [b"{", b" " ])
def test_tampered_manifest_fails_before_decode(pack, raw):
    (pack / "manifest.json").write_bytes(raw)
    with pytest.raises(VerificationError, match="signature_invalid"):
        verify(pack)


def test_valid_signature_with_invalid_json(pack):
    (pack / "manifest.json").write_bytes(b"{")
    (pack / "manifest.sig").write_bytes(base64.b64encode(signing_key("test-2026").sign(b"{")))
    with pytest.raises(VerificationError, match="manifest_undecodable"):
        verify(pack)


@pytest.mark.parametrize("file,code", [("manifest.json", "manifest_missing"), ("manifest.sig", "signature_missing"),
                                        ("exam-sets.json", "file_missing")])
def test_missing_files(pack, file, code):
    (pack / file).unlink()
    with pytest.raises(VerificationError, match=code):
        verify(pack)


@pytest.mark.parametrize("raw", [b"invalid", base64.b64encode(b"short"), b"\n"])
def test_bad_signature_encoding(pack, raw):
    (pack / "manifest.sig").write_bytes(raw)
    with pytest.raises(VerificationError, match="signature_invalid"):
        verify(pack)


def test_unknown_key(pack):
    sign_manifest(pack / "manifest.json", "test-2026", signing_key("outsider"))
    with pytest.raises(VerificationError, match="signature_invalid"):
        verify(pack)


def test_verified_key_id_must_match(pack):
    rewrite(pack, keyID="test-next")
    with pytest.raises(VerificationError, match="signature_invalid"):
        verify(pack)


def test_key_rotation_tries_all_keys(pack):
    manifest = verify_pack(pack, expected_exam_id="test-alpha", key_ring={
        "test-next": signing_key("test-next").public_key(), "test-2026": signing_key("test-2026").public_key()})
    assert manifest["keyID"] == "test-2026"


def test_verify_detects_hash_mismatch(pack):
    path = pack / "exam.json"
    data = path.read_bytes()
    path.write_bytes(b" " + data[1:])
    with pytest.raises(VerificationError, match="hash_mismatch"):
        verify(pack)


def test_verify_detects_size_mismatch(pack):
    with (pack / "exam.json").open("ab") as stream:
        stream.write(b" ")
    with pytest.raises(VerificationError, match="size_mismatch"):
        verify(pack)


@pytest.mark.parametrize("changes,code", [({"formatVersion": 2}, "unsupported_format"),
    ({"minAppVersion": "99.0.0"}, "app_too_old"), ({"examID": "test-beta"}, "exam_mismatch")])
def test_versions_and_exam(pack, changes, code):
    rewrite(pack, **changes)
    with pytest.raises(VerificationError, match=code):
        verify(pack)


@pytest.mark.parametrize("current", ["1.0.0", "1.0.0+build", "1.1.0"])
def test_not_newer_is_rejected(pack, current):
    with pytest.raises(VerificationError, match="not_newer"):
        verify(pack, current_version=current)


def test_first_install_and_prerelease(pack):
    assert verify(pack, current_version=None)
    assert verify(pack, current_version="1.0.0-rc.1")


@pytest.mark.parametrize("path", ["../outside.json", "/tmp/outside.json", "docs/../../outside.json", "a\\b.json"])
def test_unsafe_paths(pack, path):
    manifest = json.loads((pack / "manifest.json").read_bytes())
    manifest["files"][0]["path"] = path
    # 意図的な不正パック。sign_manifest の Schema 検証を迂回する。
    raw = json.dumps(manifest).encode()
    (pack / "manifest.json").write_bytes(raw)
    (pack / "manifest.sig").write_bytes(base64.b64encode(signing_key("test-2026").sign(raw)))
    with pytest.raises(VerificationError, match="unsafe_path"):
        verify(pack)


@pytest.mark.parametrize("directory", [False, True])
def test_symlink_is_rejected(pack, tmp_path, directory):
    path = pack / ("questions" if directory else "exam.json")
    target = tmp_path / "outside"
    path.rename(target)
    path.symlink_to(target, target_is_directory=directory)
    with pytest.raises(VerificationError, match="unsafe_path"):
        verify(pack)


def test_verification_order(pack):
    rewrite(pack, formatVersion=2, minAppVersion="99.0.0", examID="test-beta")
    (pack / "exam.json").unlink()
    with pytest.raises(VerificationError, match="unsupported_format"):
        verify(pack, current_version="2.0.0")


def test_symlink_cycle_is_rejected(pack):
    path = pack / "exam.json"
    path.unlink()
    path.symlink_to(path.name)
    with pytest.raises(VerificationError, match="unsafe_path"):
        verify(pack)


def test_sign_write_failure_preserves_signature(pack, monkeypatch):
    import contentpack.files as file_io
    before = (pack / "manifest.sig").read_bytes()
    paths = {p.name for p in pack.iterdir()}
    def fail(*args):
        raise OSError("write failed")
    monkeypatch.setattr(file_io.os, "replace", fail)
    assert main(["--manifest", str(pack / "manifest.json"), "--key-id", "test-2026", "--test-key", "test-2026"]) == 2
    assert (pack / "manifest.sig").read_bytes() == before
    assert {p.name for p in pack.iterdir()} == paths


@pytest.mark.parametrize("field", ["packVersion", "minAppVersion"])
def test_invalid_semver_in_signed_manifest(pack, field):
    rewrite(pack, **{field: "1.0.0-01"})
    with pytest.raises(VerificationError, match="manifest_undecodable"):
        verify(pack)
