"""P2-S03: カタログの生成と CI-13。"""

import json
from pathlib import Path

import pytest
import yaml

from build_catalog import main
from conftest import materialize
from contentpack.catalog import CatalogError, build_catalog
from contentvalidate.engine import run
from contentvalidate.schemas import validator_for
from test_schemas import MANIFEST


@pytest.fixture
def root(tmp_path):
    root = materialize(None, tmp_path)
    source(root)
    return root


def source(root, status="comingSoon"):
    (root / "catalog.yaml").write_text(yaml.safe_dump({"exams": [
        {"id": "test-beta", "status": "comingSoon", "productIDs": []},
        {"id": "test-alpha", "status": status, "productIDs": ["alpha.full"]}]}), encoding="utf-8")


def build(root, **kwargs):
    return build_catalog(root, epoch=1793491200, **kwargs)


def update_file(tmp_path, version="1.1.0", exam="test-alpha", min_app="1.0.1"):
    path = tmp_path / "update.json"
    path.write_text(json.dumps({**MANIFEST, "examID": exam, "packVersion": version, "minAppVersion": min_app}), encoding="utf-8")
    return path


def test_catalog_from_source(root):
    catalog = build(root)
    assert [e["id"] for e in catalog["exams"]] == ["test-alpha", "test-beta"]
    assert catalog["generatedAt"] == "2026-11-01T00:00:00Z"
    assert list(validator_for("catalog").iter_errors(catalog)) == []
    for entry in catalog["exams"]:
        exam = yaml.safe_load((root / "exams" / entry["id"] / "exam.yaml").read_text())
        assert {k: entry[k] for k in ("name", "vendor", "shortName")} == {k: exam[k] for k in ("name", "vendor", "shortName")}
        assert entry["latestPackVersion"] is None and entry["minAppVersion"] is None


def test_catalog_update_entry(root, tmp_path):
    previous = build(root, updates={"test-alpha": update_file(tmp_path, "1.0.0")})
    path = tmp_path / "previous.json"
    path.write_text(json.dumps(previous), encoding="utf-8")
    updated = build(root, previous=path, updates={"test-alpha": update_file(tmp_path)})
    expected = json.loads(json.dumps(previous))
    expected["exams"][0]["latestPackVersion"] = "1.1.0"
    assert updated == expected


def args(root, out):
    return ["--root", str(root), "--out", str(out)]


@pytest.mark.parametrize("version", ["0.9.0", "1.0.0-alpha", "1.0.0-alpha.9"])
def test_catalog_rejects_downgrade(root, tmp_path, monkeypatch, version):
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "1793491200")
    previous = tmp_path / "previous.json"
    previous.write_text(json.dumps(build(root, updates={"test-alpha": update_file(tmp_path, "1.0.0")})))
    out = tmp_path / "out.json"
    out.write_bytes(b"previous output")
    assert main(args(root, out) + ["--previous", str(previous), "--update", f"test-alpha={update_file(tmp_path, version)}"]) == 2
    assert out.read_bytes() == b"previous output"


@pytest.mark.parametrize(("version", "min_app"), [("1.0.0-01", "1.0.1"), ("1.0.0", "1.0.0-01")])
def test_first_catalog_rejects_invalid_semver(root, tmp_path, version, min_app):
    # 前回のカタログがない初回の登録でも、Schema が通す不正な SemVer を拒否する
    with pytest.raises(CatalogError, match="SemVer ではありません"):
        build(root, updates={"test-alpha": update_file(tmp_path, version, min_app=min_app)})


def test_catalog_is_deterministic(root, tmp_path, monkeypatch):
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "1793491200")
    a, b = tmp_path / "a.json", tmp_path / "b.json"
    assert main(args(root, a)) == main(args(root, b)) == 0
    assert a.read_bytes() == b.read_bytes()
    assert a.read_bytes() == json.dumps(json.loads(a.read_bytes()), ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def test_available_requires_pack(root, tmp_path, monkeypatch):
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "1793491200")
    source(root, "available")
    out = tmp_path / "catalog.json"
    assert main(args(root, out)) == 2
    assert not out.exists()
    assert main(args(root, out) + ["--update", f"test-alpha={update_file(tmp_path)}"]) == 0
    assert json.loads(out.read_bytes())["exams"][0]["status"] == "available"


@pytest.mark.parametrize("update", ["bad", "test-alpha=", "=missing", "unknown-exam=missing"])
def test_invalid_update_argument(root, tmp_path, monkeypatch, update):
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "1793491200")
    assert main(args(root, tmp_path / "out.json") + ["--update", update]) == 2


def test_update_exam_must_match(root, tmp_path, monkeypatch):
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "1793491200")
    path = update_file(tmp_path, exam="test-beta")
    assert main(args(root, tmp_path / "out.json") + ["--update", f"test-alpha={path}"]) == 2


@pytest.mark.parametrize("epoch", [None, "", "invalid", "-1", "253402300800"])
def test_catalog_requires_valid_epoch(root, tmp_path, monkeypatch, epoch):
    if epoch is None:
        monkeypatch.delenv("SOURCE_DATE_EPOCH", raising=False)
    else:
        monkeypatch.setenv("SOURCE_DATE_EPOCH", epoch)
    assert main(args(root, tmp_path / "out.json")) == 2


def test_catalog_rejects_duplicate_yaml_keys(root):
    (root / "catalog.yaml").write_text("exams: []\nexams: []\n", encoding="utf-8")
    with pytest.raises(CatalogError, match="YAML キーが重複しています"):
        build(root)


def test_catalog_source_is_required(root, tmp_path, monkeypatch):
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "1793491200")
    (root / "catalog.yaml").unlink()
    assert main(args(root, tmp_path / "out.json")) == 2


@pytest.mark.parametrize("text,rule", [
    ("exams: [{id: unknown-exam, status: comingSoon, productIDs: []}]", "CI-13"),
    ("exams: [{id: test-alpha, status: comingSoon, productIDs: []}, {id: test-alpha, status: comingSoon, productIDs: []}]", "CI-13"),
    ("exams: [{id: test-alpha, status: beta, productIDs: []}]", "CI-01"),
    ("exams: [", "CI-01"),
    ("exams: []\nexams: []", "CI-01"),
])
def test_ci13_catalog_validation(root, config, text, rule):
    (root / "catalog.yaml").write_text(text, encoding="utf-8")
    issues = run(root, config)
    assert {i.rule for i in issues} == {rule}
    assert all(i.file == "catalog.yaml" and i.line is not None and i.severity == "error" for i in issues)


def test_ci13_is_global_with_exam_filter(root, config):
    # 一部の試験だけをビルドしても、他の実在する試験を unknown としない。
    assert run(root, config, exam_ids=frozenset({"test-alpha"}), only={"CI-13"}) == []


def test_ci13_source_is_optional(root, config):
    (root / "catalog.yaml").unlink()
    assert run(root, config, only={"CI-13"}) == []


@pytest.mark.parametrize("left,right", [
    ("1.0.0-alpha", "1.0.0-alpha.1"), ("1.0.0-alpha.1", "1.0.0-alpha.beta"),
    ("1.0.0-alpha.beta", "1.0.0-beta"), ("1.0.0-beta.2", "1.0.0-beta.11"),
    ("1.0.0-beta.11", "1.0.0-rc.1"), ("1.0.0-rc.1", "1.0.0"),
    ("1.0.9", "1.0.10"), ("1.9.0", "1.10.0"), ("1.0.0-1", "1.0.0-a"),
])
def test_semver_precedence(left, right):
    from contentpack.versions import version_key
    assert version_key(left) < version_key(right)
    assert version_key("1.0.0+first") == version_key("1.0.0+second")


def test_catalog_reads_only_source_and_definitions(root):
    import shutil
    for path in root.glob("exams/*/*"):
        if path.is_dir():
            shutil.rmtree(path)
        elif path.name != "exam.yaml":
            path.unlink()
    assert len(build(root)["exams"]) == 2


@pytest.mark.parametrize("kind", ["previous", "update"])
@pytest.mark.parametrize("raw", ["{", "[]", "{}"])
def test_invalid_json_input(root, tmp_path, monkeypatch, kind, raw):
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "1793491200")
    path = tmp_path / "input.json"
    path.write_text(raw)
    option = ["--previous", str(path)] if kind == "previous" else ["--update", f"test-alpha={path}"]
    assert main(args(root, tmp_path / "out.json") + option) == 2


def test_catalog_write_failure_preserves_output(root, tmp_path, monkeypatch):
    import contentpack.files as file_io
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "1793491200")
    out = tmp_path / "out.json"
    out.write_bytes(b"previous output")
    paths = {p.name for p in tmp_path.iterdir()}

    def fail(*args):
        raise OSError("write failed")

    monkeypatch.setattr(file_io.os, "replace", fail)
    assert main(args(root, out)) == 2
    assert out.read_bytes() == b"previous output"
    assert {p.name for p in tmp_path.iterdir()} == paths


@pytest.mark.parametrize("version", ["1.0", "01.0.0", "v1.0.0", "1.0.0-01", "1.0.0-a..b", "1.0.0+a..b", "1.0.0-."])
def test_semver_rejects_invalid(version):
    from contentpack.versions import version_key
    with pytest.raises(ValueError):
        version_key(version)
