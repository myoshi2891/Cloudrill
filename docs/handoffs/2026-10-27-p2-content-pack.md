# P2 コンテンツパック 引き継ぎ（2026-10-27）

## 利用者の指示と停止位置

- 対象：`Documentation.docc/DDD/DDD-P2-ContentPack.md`。
- **TDD を厳守し、ステップ単位でコミットする。**
- **ブランチを変更しない。`dev` のまま作業する。** 設計書のブランチ指定より利用者の指示を優先する。
- 最新の指示：「次のコミットで、区切りの良いところで、引き継ぎを行って」。
- P2-S08 の Green と検証を完了し、本書を同じコミットに含めて停止する。**P2-S09 は未着手。P2全体は未完了。**
- 以前の未コミット引き継ぎメモ（2026-10-26）は、作業再開時に削除済み。

## 完了状況とコミット

作業開始前に P2-S01・S02 は実装済み。今回のステップは以下。

| ステップ | コミット | 内容 |
|---|---|---|
| P2-S03 | `dd76ef0` | Python の署名・検証・カタログ生成、CI-13 |
| P2-S04 | `8d84578` | 署名付き契約 fixture（正常3パック・改ざん9種類） |
| P2-S05 | `25509ec` | Data パッケージ、Swift PackVerifier、SemVer、公開鍵リング、CI |
| P2-S06 | `426cd71` | DomainInterfaces、索引読み込み、問題本文の遅延キャッシュ |
| P2-S07 | `6f056a3` | 試験語彙・模試参照・本文の整合チェック |
| P2-S08 | 本書を含むコミット | PackStore、状態保存、固定版保護、ロールバック |

全ステップで先にテストを追加し、未定義型のエラー後に仮実装で assertion の Red を確認してから実装した。失敗中の変更はコミットしていない。

## 検証結果

| 確認 | 結果 |
|---|---|
| Python 全体 | 345 passed（P2-S04 完了時。以降 Python の変更なし） |
| `validate.py` | error 0、warning 7（既存の CI-02、draft 模試に関する警告） |
| Data | 48 tests / 6 suites passed（P2-S08 完了時） |
| Domain | 全テスト通過、行カバレッジ **97.54%**（基準80%以上） |
| DomainModels | 38 tests / 6 suites passed |
| 実コンテンツ smoke | gcp-pca の build → sign → verify → catalog 成功（16ファイル） |

Swift Testing の件数は parameterized test のメソッド単位の表記。今回のローカル実行には Xcode のツールチェーンを使用した。

```sh
(cd content && .venv/bin/pytest -q)
content/.venv/bin/python content/scripts/validate.py
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/Data
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/DomainModels
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/coverage.sh packages/Domain 80
```

push・PR作成・リモートCIの確認は行っていない。`data-test.yml` は追加済みなので、PR作成後に実行結果を確認する。

## 再開時に読むファイル

- `CLAUDE.md`
- `Documentation.docc/DDD.md` 7章（TDDとコミット規約）
- `Documentation.docc/DDD/DDD-P2-ContentPack.md` P2-S09、および各ステップの実装メモ
- `packages/Data/Sources/ContentKit/`
- `packages/Domain/Sources/DomainInterfaces/`
- `packages/Data/Tests/ContentKitTests/PackFixtures.swift`

規約は **1ステップ＝1コミット、Green・Refactor・完了条件の確認後にコミット**。fixture は手編集せず生成スクリプトから作る。サブエージェントは使用していない。

## 実装済み API の注意点

### Python / 契約 fixture

- `cryptography==50.0.2` を直接依存として固定。uv.lock と仮想環境は更新済み。
- `build_pack(...)` は `BuiltPack(path, warnings)` を返す。
- `sign_manifest(path, key_id, key)` は Schema と keyID を確認し、元の manifest のバイト列を署名する。
- `verify_pack(directory, key_ring={ID: Ed25519PublicKey}, expected_exam_id=..., app_version="1.0.0", current_version=None)`。
- 検証エラーの対応は `VerificationError.code` の snake_case。
- `generate_packs.py` は固定 epoch `1793491200` で再生成する。秘密鍵は保存せず、公開鍵だけを `test-keys.json` に置く。
- `packs/tampered/expected.json` は `{directory, error, expectedExamID}` の配列。Swift のテストも同じ表を使う。
- `packs/valid/test-alpha` は **1.0.0 と 1.1.0 の両方**がある。beta は1.0.0。カタログの alpha 最新版は1.1.0。
- `content/catalog.yaml` の実コンテンツは未配信なので comingSoon。available には版情報が必須。

### ContentKit / DomainInterfaces

- `PublicKeyRing(data:)` は鍵 ID → Base64 公開鍵の JSON を読む。
- `PackVerifier` は署名 → デコード → 形式 → アプリ版 → 試験 → 版戻し → 各ファイルを検証する。
- `SemanticVersion` は build metadata を等価性・ハッシュ・優先順位に含めない。description は元の文字列を保持する。
- `PackLoader.load(packAt:manifest:)` は exam・vendor・問題索引・模試・docs索引の5ファイルだけを読む。
- `PackContent` は不変の索引を持ち、`QuestionBodyCache` actor が必要なドメインの本文を1回だけ読む。未知のIDはエラー、要求の順序・重複は保持する。
- `ExamContentProvider`、`ContentError`、`IntegrityViolation` は **DomainInterfaces** にある。ContentError が違反型を使うので、IntegrityViolation をDataに置く設計例から変更している。
- `ContentIntegrityChecker(supportedKinds:)` は ExamEngine に依存しない。呼び出し側で `AnswerEvaluatorRegistry.standard.supports` を使って対応形式を渡す。
- 索引チェックは同期で本文を読まない。本文読み込み後の `check(questions:in:)` は WAF の柱も確認する。

### PackStore

- `PackStore(root:)` の root は Content 保存先。試験ごとのパスは `<root>/<examID>/...`。
- `install` は **同じ試験の `staging/<UUID>/`** を要求する。他の場所から直接インストールしない。
- install は移動と上書き拒否を担当する。署名・整合検証は呼び出し側で先に行う。
- `activate` は installed の実在を確認し、current を previous に移す。同じ場所の再有効化は状態を変えない。
- `PackStateFile` がアトミックに保存する。メモリ内の状態キャッシュは持たない。
- pins は Swift で `[UUID: String]`、JSON で UUID文字列 → 版のオブジェクト。
- GC は current・previous・pins のいずれにもないインストール版だけを削除。同梱パックをコピー・削除しない。
- **`directory(for:examID:bundledRoot:)` は `throws(ContentError)`**。試験ID・版・シンボリックリンクを検査するため、設計例から変更している。
- `rollback` は previous を current に移し、previous を空にする。previous がなければ storage エラー。
- 存在しないインストール版の有効化、危険なID・版は拒否する。

## 次のステップ：P2-S09

本書の作成後、`BundledPacks`、`ExamCatalogService`、`ContentBootstrapper` とテストは **Green まで実装済み**（`d2e3af1`〜`dccfeb6`）。

**残作業**：有効版の選択を純粋関数 `resolveActiveLocation(bundled:installed:)` に切り出す Refactor。SemVer の大小・同じ版・片方なしなどを表形式のテストで確認する（受け入れ条件 7）。既存の振る舞いをテストで固定してから抽出する。

設計の受け入れ条件（7 以外は実装済み）：

1. 同梱の2試験が利用可能・インストール済みとして一覧に出る。
2. 初回は同梱パックをコピーせず使う。
3. 新しい installed / アプリ更新後の新しい bundled を選び、previous を保持する。
4. comingSoon は一覧に出すが読み込み不可、retired はインストール済みだけ表示する。
5. 整合違反のある試験だけ失敗とし、他の試験は利用できる。
6. 全試験が利用不能なら E-01 につながるエラーを返す。
7. 有効版の選択を純粋関数に分け、表形式で確認する。

テストで同梱1.0.0だけの状態が必要なときは、契約 fixture から一時ディレクトリに対象版だけをコピーする。`packs/valid/` 全体には alpha 1.1.0 もあるため、そのまま使うと初回1.0.0の前提にならない。

全滅時の表現：`bootstrap() async -> ContentBootstrapResult` は例外を投げない。全試験が利用不能のときは `fatalError`（`ContentError`）に E-01 用のエラーを入れる。

## 環境・作業上の補足

- cwd：`/Users/mitsuruyoshizumi/Workspace/google-cloud-professional-cloud-architect`
- ブランチ：`dev`。切り替えない。
- 通常の sandbox では `.git/index.lock` とコンパイラキャッシュへの書き込みが失敗した。必要な git add / commit と Swift テストは `require_escalated` で実行した。
- ローカルの補助ログは各ステップの `/tmp/p2-s05-*`〜`/tmp/p2-s08-*`、最終確認は `/tmp/p2-final-domain-coverage.log`・`/tmp/p2-final-domainmodels.log`。永続的な成果物はテストと本書。
- 停止時には、実装・テスト・本書をP2-S08のコミットにまとめる。未コミットのRedや仮実装を残さない。
