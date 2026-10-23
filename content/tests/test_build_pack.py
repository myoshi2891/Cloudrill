"""パックのビルド(build_pack.py、contentpack.build)のテスト。"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import pytest

from build_pack import main
from conftest import CONTENT_ROOT, VALID, materialize
from contentpack.build import BuildError, _write
from contentvalidate.schemas import validator_for
from test_extensibility import EXAM_SPECIFIC, _string_constants

EPOCH = "1793491200"  # 2026-11-01T00:00:00Z
CONTENTPACK = CONTENT_ROOT / "scripts" / "contentpack"


def _args(root: Path, exam: str, out: Path, version: str = "1.0.0") -> list[str]:
    return [
        "--root", str(root), "--exam", exam, "--version", version,
        "--min-app-version", "1.0.0", "--key-id", "test-2026", "--out", str(out),
    ]  # fmt: skip


def _files(pack: Path) -> dict[str, bytes]:
    return {p.relative_to(pack).as_posix(): p.read_bytes() for p in sorted(pack.rglob("*")) if p.is_file()}


def _json(pack: Path, path: str) -> Any:
    return json.loads((pack / path).read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def packs(tmp_path_factory: pytest.TempPathFactory) -> dict[str, Path]:
    out = tmp_path_factory.mktemp("packs")
    with pytest.MonkeyPatch.context() as mp:
        mp.setenv("SOURCE_DATE_EPOCH", EPOCH)
        for exam in ("test-alpha", "test-beta"):
            assert main(_args(VALID, exam, out)) == 0
    return {exam: out / exam / "1.0.0" for exam in ("test-alpha", "test-beta")}


# ---- CLI(終了コード) --------------------------------------------------------


def test_build_is_deterministic(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, packs: dict[str, Path]) -> None:
    # Arrange
    monkeypatch.setenv("SOURCE_DATE_EPOCH", EPOCH)
    # Act
    assert main(_args(VALID, "test-alpha", tmp_path)) == 0
    # Assert
    assert _files(tmp_path / "test-alpha" / "1.0.0") == _files(packs["test-alpha"])


def test_build_aborts_on_validation_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    # Arrange
    root = materialize("CI-08-count-mismatch", tmp_path)
    out = tmp_path / "out"
    monkeypatch.setenv("SOURCE_DATE_EPOCH", EPOCH)
    # Act
    code = main(_args(root, "test-alpha", out))
    # Assert
    assert code == 1
    assert not out.exists()
    assert "[CI-08] error" in capsys.readouterr().err


def test_build_allows_warnings(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    # Arrange
    root = materialize("CI-11-missing-en", tmp_path)
    out = tmp_path / "out"
    monkeypatch.setenv("SOURCE_DATE_EPOCH", EPOCH)
    # Act
    code = main(_args(root, "test-alpha", out))
    # Assert
    assert code == 0
    assert "[CI-11] warning" in capsys.readouterr().err
    assert (out / "test-alpha" / "1.0.0" / "manifest.json").is_file()


@pytest.mark.parametrize("epoch", [None, "", "abc", "-1", "253402300800", "9" * 30])
def test_build_requires_source_date_epoch(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, epoch: str | None) -> None:
    # Arrange
    if epoch is None:
        monkeypatch.delenv("SOURCE_DATE_EPOCH", raising=False)
    else:
        monkeypatch.setenv("SOURCE_DATE_EPOCH", epoch)
    # Act / Assert
    assert main(_args(VALID, "test-alpha", tmp_path / "out")) == 2
    assert not (tmp_path / "out").exists()


def test_build_refuses_existing_output(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    # Arrange
    monkeypatch.setenv("SOURCE_DATE_EPOCH", EPOCH)
    existing = tmp_path / "test-alpha" / "1.0.0"
    existing.mkdir(parents=True)
    (existing / "keep.txt").write_text("keep", encoding="utf-8")
    # Act / Assert: 上書きしない
    assert main(_args(VALID, "test-alpha", tmp_path)) == 2
    assert _files(existing) == {"keep.txt": b"keep"}


@pytest.mark.parametrize("dangling", [True, False])
def test_build_refuses_symlinked_output(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, dangling: bool) -> None:
    # Arrange: 出力先がシンボリックリンク(リンク先なし / 空のディレクトリ)
    monkeypatch.setenv("SOURCE_DATE_EPOCH", EPOCH)
    link_target = tmp_path / "elsewhere"
    if not dangling:
        link_target.mkdir()
    link = tmp_path / "test-alpha" / "1.0.0"
    link.parent.mkdir()
    link.symlink_to(link_target, target_is_directory=True)
    # Act / Assert: 終了コード 2 で、リンクもリンク先も変えない
    assert main(_args(VALID, "test-alpha", tmp_path)) == 2
    assert link.is_symlink()
    assert dangling or list(link_target.iterdir()) == []


def test_build_reports_output_os_error(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    # Arrange: --out が通常のファイル(その下にディレクトリを作れない)
    monkeypatch.setenv("SOURCE_DATE_EPOCH", EPOCH)
    out = tmp_path / "out"
    out.write_text("file", encoding="utf-8")
    # Act / Assert: OSError をトレースバックにせず、終了コード 2
    assert main(_args(VALID, "test-alpha", out)) == 2
    assert out.read_text(encoding="utf-8") == "file"


def test_write_refuses_output_created_after_check(tmp_path: Path) -> None:
    # Arrange: 最初の確認の後(検証中)に、空のディレクトリができた場合
    target = tmp_path / "pack"
    target.mkdir()
    # Act / Assert: rename で上書きせず、一時ディレクトリも残さない
    with pytest.raises(BuildError):
        _write(target, {"manifest.json": b"{}"})
    assert list(target.iterdir()) == []
    assert [p.name for p in tmp_path.iterdir()] == ["pack"]


@pytest.mark.parametrize(
    ("exam", "version"),
    [("no-such-exam", "1.0.0"), ("test-alpha", "1.0"), ("test-alpha", "v1.0.0")],
)
def test_build_rejects_bad_arguments(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, exam: str, version: str) -> None:
    monkeypatch.setenv("SOURCE_DATE_EPOCH", EPOCH)
    assert main(_args(VALID, exam, tmp_path, version)) == 2
    assert list(tmp_path.iterdir()) == []


# ---- パックの内容 -----------------------------------------------------------


def test_manifest_lists_all_files_sorted(packs: dict[str, Path]) -> None:
    pack = packs["test-alpha"]
    paths = [f["path"] for f in _json(pack, "manifest.json")["files"]]
    assert paths == sorted(paths)
    assert set(paths) == set(_files(pack)) - {"manifest.json"}


def test_manifest_hashes_match(packs: dict[str, Path]) -> None:
    pack = packs["test-alpha"]
    for entry in _json(pack, "manifest.json")["files"]:
        data = (pack / entry["path"]).read_bytes()
        assert entry["sha256"] == hashlib.sha256(data).hexdigest(), entry["path"]
        assert entry["size"] == len(data), entry["path"]


@pytest.mark.parametrize("exam", ["test-alpha", "test-beta"])
def test_manifest_validates_against_schema(packs: dict[str, Path], exam: str) -> None:
    manifest = _json(packs[exam], "manifest.json")
    assert list(validator_for("manifest").iter_errors(manifest)) == []
    assert manifest["examID"] == exam
    assert manifest["createdAt"] == "2026-11-01T00:00:00Z"
    assert manifest["keyID"] == "test-2026"


@pytest.mark.parametrize(
    ("path", "schema"),
    [
        ("questions/index.json", "pack-question-index"),
        ("docs/index.json", "pack-docs-index"),
        ("exam.json", "exam"),
        ("exam-sets.json", "exam-sets"),
        ("flashcards.json", "flashcard"),
    ],
)
@pytest.mark.parametrize("exam", ["test-alpha", "test-beta"])
def test_pack_files_validate_against_schema(packs: dict[str, Path], exam: str, path: str, schema: str) -> None:
    assert list(validator_for(schema).iter_errors(_json(packs[exam], path))) == []


def test_json_is_compact_and_sorted(packs: dict[str, Path]) -> None:
    raw = (packs["test-alpha"] / "exam.json").read_text(encoding="utf-8")
    data = json.loads(raw)
    assert raw == json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def test_beta_pack_has_no_disabled_features(packs: dict[str, Path]) -> None:
    files = _files(packs["test-beta"])
    assert {"cases.json", "decisions.json", "drills.json"}.isdisjoint(files)
    assert "flashcards.json" in files


def test_alpha_pack_has_enabled_features(packs: dict[str, Path]) -> None:
    pack = packs["test-alpha"]
    assert [c["id"] for c in _json(pack, "cases.json")] == ["altostrat", "ehr"]
    assert len(_json(pack, "decisions.json")) == 1
    assert _json(pack, "drills.json")["drills"]


def test_questions_split_by_domain(packs: dict[str, Path]) -> None:
    pack = packs["test-alpha"]
    for domain in range(1, 7):
        questions = _json(pack, f"questions/domain{domain}.json")
        assert questions, domain
        assert {q["domain"] for q in questions} == {domain}
        ids = [q["id"] for q in questions]
        assert ids == sorted(ids)
        assert list(validator_for("question").iter_errors(questions[0])) == []


def test_index_matches_questions(packs: dict[str, Path]) -> None:
    pack = packs["test-alpha"]
    index = _json(pack, "questions/index.json")
    bodies = [q for p in sorted(pack.glob("questions/domain*.json")) for q in _json(pack, p.relative_to(pack).as_posix())]
    assert [e["id"] for e in index] == sorted(q["id"] for q in bodies)
    by_id = {q["id"]: q for q in bodies}
    for entry in index:
        question = by_id[entry["id"]]
        assert entry["kind"] == question["type"]["kind"]
        assert {k: question[k] for k in entry if k != "kind"} == {k: v for k, v in entry.items() if k != "kind"}


def test_docs_frontmatter_removed(packs: dict[str, Path]) -> None:
    pack = packs["test-alpha"]
    [entry] = _json(pack, "docs/index.json")
    assert entry["subObjective"] == "1.1"
    assert entry["title"] == "ダミーのドキュメント"
    assert entry["references"]
    body = (pack / entry["path"]).read_text(encoding="utf-8")
    assert not body.startswith("---")
    assert body.startswith("# ダミーのドキュメント")


def test_vendor_embedded(packs: dict[str, Path]) -> None:
    assert _json(packs["test-beta"], "vendor.json")["id"] == "example-cloud"


def test_pack_has_no_exam_specific_code_paths() -> None:
    # Arrange
    sources = sorted(CONTENTPACK.rglob("*.py"))
    assert sources
    # Act
    found = [
        (path.relative_to(CONTENTPACK).as_posix(), word)
        for path in sources
        for value in _string_constants(path)
        for word in EXAM_SPECIFIC
        if word in value
    ]
    # Assert
    assert found == []
