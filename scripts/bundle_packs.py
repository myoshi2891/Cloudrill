"""開発用署名パックを生成し、フォルダ構造を保ったまま同梱用に配置する。"""
import argparse
import json
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "content/tests/fixtures"))
from generate_packs import generate_packs  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--development", action="store_true", required=True)
    parser.add_argument("--out", type=Path, default=ROOT / "ExamPrepApp/Resources/Packs")
    args = parser.parse_args()
    if args.out.exists() or args.out.is_symlink():
        parser.error("出力先は既存データを上書きしないよう、新規ディレクトリを指定してください")
    with tempfile.TemporaryDirectory(prefix="cloudrill-bundle-") as temporary:
        work = Path(temporary)
        # 既存のビルド・署名・カタログ生成処理を再利用する。秘密鍵は保存しない。
        generate_packs(work / "generated")
        shutil.copytree(work / "generated/valid", work / "Packs")
        for name in ("catalog.json", "test-keys.json"):
            shutil.copy2(work / "generated" / name, work / "Packs" / name)
        (work / "Packs/development.json").write_text(json.dumps({"developmentOnly": True}) + "\n")
        args.out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(work / "Packs", args.out)
    print(args.out)


if __name__ == "__main__":
    main()
