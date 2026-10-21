# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

Google Cloud Professional Cloud Architect(PCA)試験対策 iOS アプリと、その学習コンテンツのモノレポ。

- `ExamPrepApp/` + `ExamPrepApp.xcodeproj` — iOS アプリ(SwiftUI、表示名 Cloudrill)。`packages/DomainModels` をローカルパッケージ(相対パス)として参照
- `packages/DomainModels/` — コンテンツの値型(SwiftPM、Swift 6、Swift Testing)
- `content/` — 学習コンテンツ(YAML / Markdown)、JSON Schema(Draft 2020-12)、Python の検証ツール。詳細仕様は `content/README.md`
- `Documentation.docc/` — 要件定義書(`RDD.md`)、基本設計書(`BDD.md`)

## コマンド

すべてリポジトリのルートから実行する。Python は 3.14(`requires-python >= 3.12`、`content/.python-version`)。パッケージ管理は uv で、依存は `content/pyproject.toml` と `content/uv.lock`、仮想環境は `content/.venv` に置く。

```sh
# 初回セットアップ(依存を変えたら uv lock --project content で uv.lock を更新する)
uv sync --project content

# Python テスト(pyproject.toml がある content/ で実行する)
(cd content && .venv/bin/pytest)
(cd content && .venv/bin/pytest tests/test_rules.py -k CI-03)   # 単一テスト

# コンテンツ検証(--root 省略時は content/ が対象。実行場所に依存しない)
content/.venv/bin/python content/scripts/validate.py
content/.venv/bin/python content/scripts/validate.py --only CI-02,CI-03 --format json
content/.venv/bin/python content/scripts/validate.py --check-links   # CI-06(ネットワークアクセスあり)

# fixture と Swift 用 JSON の再生成(生成物はコミット対象)
content/.venv/bin/python content/tests/fixtures/generate.py
content/.venv/bin/python content/scripts/export_json.py

# Swift テスト
swift test --package-path packages/DomainModels
swift test --package-path packages/DomainModels --filter FixtureDecodingTests   # 単一テスト
```

`swift test` が `plugin for module 'TestingMacros' not found` で失敗する場合は、`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を前に付ける。

validate.py の終了コード: `0` = error なし / `1` = error あり(`--strict` では warning も含む)/ `2` = 引数や設定の不備。

## 運用ルール: Schema と Swift 型は同じ PR で同期する

`content/schemas/*.schema.json` を変更したら、同じ PR で次の作業を行う。

1. `packages/DomainModels/Sources/DomainModels/` の型を更新する
2. 必要に応じて `content/tests/fixtures/generate.py` を更新し、fixture を再生成する
3. `export_json.py` で `content/tests/fixtures/valid-json/` を再生成する
4. `pytest` と `swift test` の両方が通ることを確認する

- fixture(`valid/`、`invalid/`、`valid-json/`)は手で編集しない。`generate.py` が固定 seed で決定論的に生成し、`tests/test_generated.py` がコミット済みの内容と生成結果の一致を確認する。
- Swift のテストは `../../content/tests/fixtures/valid-json` を直接読む(パッケージ内にはコピーしない)。
- Swift 側では未知の列挙値をデコードエラーにする(古いアプリへの配信は `manifest.minAppVersion` で制御する前提)。

## 検証ツールの構成(`content/scripts/contentvalidate/`)

- `validate.py`(CLI)→ `engine.run()` → `context.build_context()`(ロード、Schema 検証、行番号の付与)→ `rules.ALL_RULES` → `report` で text / json / github 形式に整形する。
- コンテキストは2種類。`GlobalContext`(全ファイルと全試験)は全体のルール(CI-01、CI-06、CI-11)に1回、`ExamContext`(1試験のファイル、試験ごとの設定、`exam.yaml` から作る `ExamDefinitionView`)は試験ごとのルールに試験の数だけ渡す。`definition` が `None`(`exam.yaml` が Schema 違反)の試験では、試験定義を使うルールは何も報告しない。`--exam` で対象の試験を絞れる。
- Schema の `$id` は `https://examprep-content.invalid/schemas/<name>.schema.json`。`referencing.Registry` に全 Schema を事前に登録し、オフラインで解決する。共通の定義は `common.schema.json#/$defs/...` に置く。すべてのオブジェクトに `additionalProperties: false` を付けている。
- 役割分担: 1ファイル内の構造は Schema が担当する。Schema で表しにくい条件と、ファイル間の整合(模試の構成、統計、重複、参照)はルール CI-01〜CI-11 が担当する。閾値は `content/validation.yaml`(全体)に置き、試験ごとの `exams/<examID>/validation.yaml` を深いマージで重ねる(模試の構成 `examSet` は試験側にだけ書ける。サブ項目と模試の問題数は `exam.yaml` が正)。
- Schema に違反したファイルは、ファイル間ルールの対象から外す(違反の連鎖を防ぐため)。`--only` で CI-01 を外しても、Schema 検証自体は常に行う。
- 例外として、`choices[*].rationale` に関する Schema 違反は CI-01 では報告せず、CI-05 だけが報告する。
- ルールを追加する手順: `rules/ciNN_xxx.py` に `check(ctx) -> Iterable[Issue]` と `RULE = Rule("CI-NN", ..., check)`(全体のルールは `check_global=check`)を定義する → `rules/__init__.py` の `ALL_RULES` に追加する → `generate.py` の `INVALID_CASES` に違反ケースを追加し、fixture を再生成する。
- invalid fixture は valid に対する差分(overlay)。`expected.yaml` に、検出されるべきルール ID と深刻度を書く。`_delete.txt` に列挙したファイルは valid から削除される。

## コンテンツの規約

- 問題・ケース・ツリーは 1ファイル1件(`questions/domain{1..6}/<id>.yaml`)。カードとドリルは配列のラッパー(`{ cards: [...] }` / `{ drills: [...] }`)で 1ファイルに複数件を持つ。
- 利用者に表示する文章は `LocalizedText`(`ja` は必須、`en` の欠落は CI-11 の warning)。サービス名や `Reference.title` はプレーン文字列。
- YAML のキーはすべて文字列に正規化される。`examGuideVersion: 6.1` のように引用符を付け忘れると数値として読まれ、CI-01 になる。

## CI

変更されたパスに応じて、必要なワークフローだけが動く。

- `content-validate.yml` — `pytest -q` と `validate.py --format github`(Ubuntu、`content/` で実行)
- `domainmodels-test.yml` — `swift test`(macOS。`packages/DomainModels/**`、`content/schemas/**`、`content/tests/fixtures/**` の変更時)
- `content-link-check.yml` — 毎週、`--only CI-06 --check-links --strict`

## 命名とリリース

- Xcode のプロジェクト・ターゲット・フォルダは PascalCase で、スペースを含めない(`ExamPrepApp`)。識別子は表示名と切り離した中立な名前にする。表示名「Cloudrill」は `INFOPLIST_KEY_CFBundleDisplayName` だけで設定する(名前を変えるときはここだけを変更する)。
- パッケージを追加するときは `project.pbxproj` を手で編集せず、Xcode の **File > Add Package Dependencies… > Add Local…** から追加する。
- リリースタグは `content-vX.Y.Z`(`manifest.json` の `packVersion` と一致させる)と `app-vX.Y.Z`。
