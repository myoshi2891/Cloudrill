# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

クラウド認定試験対策 iOS アプリ「Cloudrill」と、その学習コンテンツのモノレポ。初期リリースの対象は Google Cloud Professional Cloud Architect(PCA、`examID: gcp-pca`)だが、コンテンツの構造と検証ツールは複数の試験(他ベンダーを含む)に対応している。試験の追加はコンテンツの追加だけで済む(コードを変えない)。

- `ExamPrepApp/` + `ExamPrepApp.xcodeproj` — iOS アプリ(SwiftUI、表示名 Cloudrill)。`packages/DomainModels` と `packages/AppComposition` をローカルパッケージ(相対パス)として参照
- `packages/DomainModels/` — コンテンツの値型(SwiftPM、Swift 6、Swift Testing)
- `packages/Domain/` — 学習・採点ロジックと `DomainInterfaces`（コンテンツ提供・永続化リポジトリのプロトコル、エラー、受験スナップショットなどの値型）
- `packages/Presentation/` — P4 の基盤。`AppCore` は `AppDependencies`・`ActiveExamContext`・`AppRouter`、`HomeFeature` は `ExamPickerViewModel`・`HomeViewModel`・`HomeView`、`ExamFeature` は模試開始・解答の View/ViewModel、`ExamSessionController`、`QuestionRendererRegistry`。Data には依存しない。選択設定と中断スナップショットの保存が成功してから試験と経路を切り替え、await 中の重複操作を拒否する。進捗は DDD-P4 第2節を参照
- `Presentation` の `DesignSystem` は P4-S04 の共通部品と日本語 `.strings` リソースを提供する。ドメインの並び順から配色・記号を決め、ライト／ダークの専用背景でコントラストを保証する。`QuestionRendererRegistry` は共通 `ChoiceRow` を使う。S05 のホーム（今日の学習・弱点・復習期限・再開）と5タブの接続まで実装済み。S06 の試験トップ・開始確認・保存とパック固定・再開／破棄も実装済み。S07 の解答画面・即時保存・中断復元・時間切れ提出も実装済み。S08 の見直し一覧・手動提出・共通の提出処理と誤答カード化も実装済み。S09 の結果・全問の解説・カード追加も実装済み。次は S10 の練習モード。関連ドキュメント本文は S12、報告フォームと保存キューは S15（S09 は経路・版付きコンテキストのシートまで）。引き継ぎは `docs/handoffs/2026-10-30-p4-s09-results-explanations.md`。本番 App Group ID は未定のため保留し、Debug の開発用ストアで作業を継続する。
- `packages/AppComposition/` — アプリ専用の Composition root と起動View。Data と Presentation を接続する。`live` は呼び出し元で解決した保存先URLを受け取り、開発用パックを拒否する。`development`・`uiTesting` は DEBUG のみ。`AppRootView` は起動状態・試験選択・ホーム（`HomeViewModel`・`HomeView`）・5タブシェルを接続済み。試験タブの模試一覧・開始確認・解答画面と時間切れの提出確認まで接続済み。見直し一覧と手動提出も接続済み。解答と見直しは `ExamSessionStore` で同じ ViewModel を共有する。S09 の結果・解説も接続済み。`ExamResultViewModel` と `ExplanationViewModel` は `SubmittedExamContent` で受験時の版・出題順を復元する。検証済みの読み込み結果は `MainTabView` が試験ごとに持つ `SubmittedExamContentCache` で共有する。Xcodeへ接続済み。今回は利用者の明示承認によりproject.pbxprojをパッチ更新した
- `packages/Data/` — `ContentKit` と `Persistence` を提供する。`ContentKit` は署名検証、索引と本文の読み込み、整合チェック、パック保存、同梱カタログと起動処理を担当し、テストは `content/tests/fixtures/packs/` を直接参照する。`Persistence` は SwiftData による学習履歴・設定の永続化を担当する
- `packages/Data` の `Persistence` は P3-S01〜S09 の実装・ローカル検証完了（リモート CI は未確認）。10モデル、コンテナ、`SwiftDataExamAttemptRepository`・`SwiftDataAnswerHistoryRepository` を含む各 ModelActor リポジトリ、重複統合、エクスポート／削除、V1 の移行計画を実装済み。`Storage.write` が保存の1回再試行と rollback を共用する。App Group の URL は `storeDirectory` に渡し、インメモリでは CloudKit を無効にする。詳細と最終検証は `Documentation.docc/DDD/DDD-P3-Persistence.md` の各節・第5節を参照
- `SyncDeduplicator.run()` は値型の計画を返し、`notifyUser` が true なら受験統合の通知が必要。`DataManagement.export(examID:)`・`deleteAll(examID:)` は nil なら全体、試験指定なら UserSettings を除く当該試験のみを扱う。エクスポートは版付き JSON（Date は Unix 秒、Data は Base64、リレーションは UUID）。内部の `PersistenceRows` が取得を共用する。`ModelContainerFactory` は `ExamPrepMigrationPlan` を指定し、移行計画導入前の V1 ストアを開き直すテストを備える
- `content/` — 学習コンテンツ(YAML / Markdown)、JSON Schema(Draft 2020-12)、Python の検証ツール。詳細仕様は `content/README.md`
  - `content/vendors.yaml`(全試験で共通のベンダー定義)と `content/validation.yaml`(検証の閾値、全体)
  - `content/exams/<examID>/` — 試験ごとのディレクトリ。`exam.yaml`(試験定義)、`validation.yaml`(試験ごとの検証設定)、`exam-sets.yaml`、問題などのコンテンツ
- `Documentation.docc/` — 要件定義書(`RDD.md`)、基本設計書(`BDD.md`)、詳細設計書(`DDD.md` と `DDD/DDD-P0〜P6`)

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
content/.venv/bin/python content/scripts/validate.py --exam gcp-pca   # 試験を絞る(カンマ区切り。存在しない ID は終了コード 2)
content/.venv/bin/python content/scripts/validate.py --check-links   # CI-06(ネットワークアクセスあり)

# 配信パックのビルド(SOURCE_DATE_EPOCH は必須。終了コード 0 = 成功 / 1 = 検証 error / 2 = 引数の不備・出力先がすでにある)
SOURCE_DATE_EPOCH=<リリース時刻の epoch> content/.venv/bin/python content/scripts/build_pack.py --exam gcp-pca --version 1.0.0 --min-app-version 1.0.0 --key-id <本番鍵 ID> --out <出力先>

# 署名とカタログ生成(成功 0 / 入力・I/O の不備 2)
content/.venv/bin/python content/scripts/sign_manifest.py --manifest <manifest.json> --key-id <本番鍵 ID> --key-env <環境変数名>
content/.venv/bin/python content/scripts/sign_manifest.py --manifest <manifest.json> --key-id test-2026 --test-key test-2026   # テスト署名
SOURCE_DATE_EPOCH=<リリース時刻の epoch> content/.venv/bin/python content/scripts/build_catalog.py --out <catalog.json> [--previous <catalog.json>] [--update <examID>=<manifest.json> ...]

# fixture と Swift 用 JSON の再生成(生成物はコミット対象)
content/.venv/bin/python content/tests/fixtures/generate.py
content/.venv/bin/python content/scripts/export_json.py
content/.venv/bin/python content/tests/fixtures/generate_packs.py  # Python / Swift 共通の署名付き契約パック

# FSRS のテストベクタの再生成(開発時のみ。py-fsrs は依存グループ fsrs。生成物はコミット対象)
uv sync --project content --group fsrs
content/.venv/bin/python content/scripts/fsrs_vectors.py --out packages/Domain/Tests/FSRSTests/Vectors/fsrs-vectors.json

# Swift テスト
swift test --package-path packages/DomainModels
swift test --package-path packages/Domain
swift test --package-path packages/Data
swift test --package-path packages/Presentation
swift test --package-path packages/AppComposition
swift test --package-path packages/DomainModels --filter FixtureDecodingTests   # 単一テスト

# 行カバレッジ(Sources の *TestSupport/ を除く。最低値を下回ると終了コード 1)
scripts/coverage.sh packages/Domain 80
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
- コンテキストは2種類。`GlobalContext`(全ファイルと全試験)は全体のルール(CI-01、CI-06、CI-11、CI-13)に1回、`ExamContext`(1試験のファイル、試験ごとの設定、`exam.yaml` から作る `ExamDefinitionView`)は試験ごとのルールに試験の数だけ渡す。`definition` が `None`(`exam.yaml` が Schema 違反)の試験では、試験定義を使うルールは何も報告しない。`--exam` で対象の試験を絞れる。
- Schema の `$id` は `https://examprep-content.invalid/schemas/<name>.schema.json`。`referencing.Registry` に全 Schema を事前に登録し、オフラインで解決する。共通の定義は `common.schema.json#/$defs/...` に置く。すべてのオブジェクトに `additionalProperties: false` を付けている。
- 役割分担: 1ファイル内の構造は Schema が担当する。Schema で表しにくい条件と、ファイル間の整合(模試の構成、統計、重複、参照)はルール CI-01〜CI-13 が担当する(CI-12 は試験定義と、ディレクトリ名・vendors.yaml・試験のコンテンツとの整合)。閾値は `content/validation.yaml`(全体)に置き、試験ごとの `exams/<examID>/validation.yaml` を深いマージで重ねる(模試の構成 `examSet` は試験側にだけ書ける。サブ項目と模試の問題数は `exam.yaml` が正)。
- Schema に違反したファイルは、ファイル間ルールの対象から外す(違反の連鎖を防ぐため)。`--only` で CI-01 を外しても、Schema 検証自体は常に行う。
- 例外として、`choices[*].rationale` に関する Schema 違反は CI-01 では報告せず、CI-05 だけが報告する。
- ルールを追加する手順: `rules/ciNN_xxx.py` に `check(ctx) -> Iterable[Issue]` と `RULE = Rule("CI-NN", ..., check)`(全体のルールは `check_global=check`)を定義する → `rules/__init__.py` の `ALL_RULES` に追加する → `generate.py` の `INVALID_CASES`(`test-beta` の上で作るケースは `BETA_INVALID_CASES`)に違反ケースを追加し、fixture を再生成する。
- valid fixture は形の違う2試験(`test-alpha` は PCA と同じ形、`test-beta` はケースなし・single のみ・ドメイン 4)を持つ。試験ごとの値は `generate.py` の `ExamSpec` に置く。検証ツールに試験ごとの分岐や試験固有の値を書かない(`test_extensibility.py` が確認する)。
- invalid fixture は valid に対する差分(overlay)。`expected.yaml` に、検出されるべきルール ID と深刻度を書く。`_delete.txt` に列挙したファイルは valid から削除される。
- CI-13 は任意の全体ファイル `catalog.yaml` の試験 ID の実在・重複を確認する。構文・Schema は CI-01。`--exam` で絞っても、実在の確認には全試験ディレクトリを使う。
- `contentpack/` はビルド・署名・検証・カタログ生成を担当する。署名は `cryptography` の Ed25519。検証は署名の成功後にだけ JSON を解析する。鍵リングは鍵 ID → `Ed25519PublicKey`。テスト用 seed は `contentpack.testing.test_signing_key(label)` で導出し、ファイルに保存しない。
- `fixtures/packs/` は `generate_packs.py` で再生成する。epoch は固定の `1793491200`。正常3パックと改ざん9種類を持ち、`tampered/expected.json` の `directory`・`error`・`expectedExamID` を Python / Swift の両方が使う。生成済みパックは手編集しない。
- `PackStore(root:)` の root は Content 保存先。インストール元は `<root>/<examID>/staging/<UUID>/` に置き、検証・整合チェック後に `install` → `activate` を呼ぶ。受験中の版は `pin` で保持し(同梱にしかない版は `bundledRoot` から `versions/` へ複製してから固定する)、提出時は `retain` で直近 `retainedLimit` 件だけ固定を残す。`garbageCollect` は current・previous・pins にないインストール版だけを削除する。`directory(...)` は `throws(ContentError)`。
- `BundledPacks(root:)` はアプリの `Packs/` と `catalog.json` を読む。`ContentBootstrapper(catalogService:loader:integrityChecker:)` を起動時に呼び、`available` を利用する。`failures` は試験ごとの失敗、`fatalError` は全試験が利用不可の場合の E-01 用。起動時には本文や署名を全再検証せず、manifest・試験定義・ベンダーの一致と索引の整合を確認してから有効化する。`ExamCatalogService.activeLocation(for:)` は選択だけ、`load(for:loader:integrityChecker:)` は整合確認と有効化まで行う。
- 版の選択は `ActiveLocation.swift` の内部純粋関数 `resolveActiveLocation(bundled:installed:)` に集約する。サービスが存在・パス・版を確認した候補を渡し、SemVer で新しい方を選ぶ。同順位（build metadata だけの差を含む）なら installed を維持する。`ActiveLocationTests` の表でサービスと純粋関数の両方を確認する。

## コンテンツの規約

- コンテンツは試験ごとに `exams/<examID>/` の下に置く。試験のドメイン、サブ項目、比重、模試の形式、有効な機能、語彙(ケース ID、WAF の柱)は `exam.yaml` が正で、コードには書かない。
- 問題・ケース・ツリーは 1ファイル1件(`exams/<examID>/questions/domain<N>/<id>.yaml`)。カードとドリルは配列のラッパー(`{ cards: [...] }` / `{ drills: [...] }`)で 1ファイルに複数件を持つ。
- 利用者に表示する文章は `LocalizedText`(`ja` は必須、`en` の欠落は CI-11 の warning)。サービス名や `Reference.title` はプレーン文字列。
- YAML のキーはすべて文字列に正規化される。`examGuideVersion: 6.1` のように引用符を付け忘れると数値として読まれ、CI-01 になる。

## CI

変更されたパスに応じて、必要なワークフローだけが動く。

- `content-validate.yml` — `pytest -q` と `validate.py --format github`(Ubuntu、`content/` で実行)
- `domainmodels-test.yml` — `swift test --package-path packages/DomainModels`(macOS。`packages/DomainModels/**`、`content/schemas/**`、`content/tests/fixtures/**` の変更時)
- `domain-test.yml` — `scripts/coverage.sh packages/Domain 80`(macOS。`swift test` と行カバレッジ 80% の確認。`packages/Domain/**`、`packages/DomainModels/**` の変更時。Domain は DomainModels に依存するので、DomainModels の変更でも実行する)
- `content-link-check.yml` — 毎週、`--only CI-06 --check-links --strict`
- `data-test.yml` — `swift test --package-path packages/Data`。Data・Domain・DomainModels・契約 fixture の変更時に、Python が生成した署名付きパックを CryptoKit で検証する。
- `presentation-test.yml` — `swift test --package-path packages/Presentation`。Presentation・Domain・DomainModels・JSON fixture の変更時に試験選択・画面遷移を検証する。
- `app-test.yml` — AppComposition のテストとReleaseビルド。PRではSimulator向けビルド、mainへのpush・手動実行では起動UIテストを実行する。`scripts/bundle_packs.sh --development --out <新規ディレクトリ>` で同梱用の署名付きfixtureを再生成できる。既存出力は上書きしない

## 命名とリリース

- Xcode のプロジェクト・ターゲット・フォルダは PascalCase で、スペースを含めない(`ExamPrepApp`)。識別子は表示名と切り離した中立な名前にする。表示名「Cloudrill」は `INFOPLIST_KEY_CFBundleDisplayName` だけで設定する(名前を変えるときはここだけを変更する)。
- パッケージを追加するときは `project.pbxproj` を手で編集せず、Xcode の **File > Add Package Dependencies… > Add Local…** から追加する。
- 試験 ID(`examID`)は `<ベンダー略称>-<試験略称>`(例: `gcp-pca`)。表示名と同じく、識別子は製品名やブランド名に依存させない。
- リリースタグは `content/<examID>/vX.Y.Z`(試験ごとのパック。`manifest.json` の `packVersion` と一致させる)と `app-vX.Y.Z`。
