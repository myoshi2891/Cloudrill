# IT-01 Python と Swift の契約(Schema・JSON・署名付きパック)

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 結合テスト |
| 対応要件 | NFR-05、NFR-10、AC-05、[DDD](../DDD.md) 2 章(C-06)、[DDD-P2](../DDD/DDD-P2-ContentPack.md) P2-S04・S05、CLAUDE.md の「Schema と Swift 型は同じ PR で同期する」 |
| 対象 | `content/schemas/`、`content/tests/fixtures/valid-json/`、`content/tests/fixtures/packs/`、`packages/DomainModels`、`packages/Data` の `PackVerifier` |
| 既存のテスト | [DomainModelsTests](../../packages/DomainModels/Tests/DomainModelsTests/)、[PackVerifierTests](../../packages/Data/Tests/ContentKitTests/PackVerifierTests.swift)、[test_generated.py](../../content/tests/test_generated.py)、[test_sign.py](../../content/tests/test_sign.py) |

---

## 1. テストの観点

Python のツールが作るもの(JSON、パック、署名、カタログ)を、Swift のアプリがそのまま読めることを確認する。両者は別の言語で同じ規則を実装しているので、規則のずれを検出するのが目的である。

- **データの形**: Schema に合う JSON を、Swift の型がすべてデコードでき、往復しても情報が落ちないこと。未知の値をエラーにすること。
- **署名と検証**: Python が署名したパックを Swift が検証できること。改ざんしたパックを、両者が同じエラーで拒否すること。検証の順序が同じであること。
- **版の比較**: SemVer の大小の規則が同じであること。
- **生成物の鮮度**: コミットされた fixture が、生成器の今の出力と一致していること。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| IT-01-01 | fixture の鮮度 | 生成器(`generate.py`、`export_json.py`、`generate_packs.py`)を実行し、コミット済みの fixture と比べる | YAML・JSON・パックのすべてが一致する | 自動: `test_generated.test_fixtures_are_up_to_date`、`test_swift_fixtures_are_up_to_date`、`test_packs_match_generator` | 現在 | 未実施 |
| IT-01-02 | 全ファイルのデコード | `valid-json/` の全試験・全ファイルを、Swift の型でデコードする | すべてデコードできる。試験定義のディレクトリ名と ID が一致する | 自動: `FixtureDecodingTests.allFilesDecode`、`examDirectories`、`examDefinitionMatchesDirectory`、`vendorsDecode` | 現在 | 未実施 |
| IT-01-03 | 往復 | デコードした値をエンコードし、もう一度デコードする | 元の値と一致する。`null` のキーを落とさない | 自動: `FixtureDecodingTests.roundTrip`、`PackIndexTests.indexEntryRoundTripKeepsNull`、`CatalogTests.roundTripKeepsNull` | 現在 | 未実施 |
| IT-01-04 | 未知の値 | 未知の列挙値(問題の種類、カタログの状態、採点の方式)を含む JSON をデコードする | デコードのエラーにする | 自動: `CustomDecodingTests.unknownEnum`、`PackIndexTests.unknownKindFails`、`CatalogTests.unknownStatusFails`、`ExamDefinitionTests.unknownScoringPolicyFails` | 現在 | 未実施 |
| IT-01-05 | 必須のキー | 必須のキー(manifest の `examID`、索引の `caseStudy`、カタログの版)を欠いた JSON | デコードのエラーにする。Schema も同じものを拒否する | 自動: `CustomDecodingTests.manifestRequiresExamID`、`PackIndexTests.missingCaseStudyKeyFails`、`CatalogTests.missingVersionKeyFails`、`test_schemas.test_manifest_schema_requires_exam_id_and_format_version` | 現在 | 未実施 |
| IT-01-06 | 形の違う試験 | PCA と同じ形の試験(`test-alpha`)と、ケースなし・単一選択だけ・4 ドメインの試験(`test-beta`) | 両方を同じ型でデコードできる | 自動: `ExamDefinitionTests.betaShape`、`test_extensibility.test_valid_fixture_has_two_differently_shaped_exams` | 現在 | 未実施 |
| IT-01-07 | 署名付きパックの検証 | Python が作って署名した正常なパック(3 件)を、Swift の `PackVerifier` で検証する | すべて検証に通る。Python の `verify_pack` でも通る | 自動: `PackVerifierTests.validPacks`、`test_generated.test_valid_packs_verify` | 現在 | 未実施 |
| IT-01-08 | 改ざんしたパック(AC-05) | 改ざんした 9 種類のパックを、Python と Swift の両方で検証する | 両方が、`tampered/expected.json` に書いた同じエラーで拒否する | 自動: `PackVerifierTests.tamperedPacks`、`test_generated.test_tampered_packs_fail_with_expected_error` | 現在 | 未実施 |
| IT-01-09 | 検証の順序 | 署名が不正で、かつ JSON としても壊れている manifest | 両方が、署名のエラーを先に返す(署名の確認の前に JSON を解析しない) | 自動: `PackVerifierTests.signatureCheckedBeforeDecode`、`test_sign.test_tampered_manifest_fails_before_decode`、`test_verification_order` | 現在 | 未実施 |
| IT-01-10 | 版の比較の規則 | 同じ版の組(プレリリース、build metadata を含む)を、Python と Swift で比べる | 大小の判定が一致する。build metadata だけの差は同じ版として扱う | 自動: `SemanticVersionTests.ordering`、`buildMetadataDoesNotChangePrecedence`、`test_catalog.test_semver_precedence`、`test_sign.test_not_newer_is_rejected` | 現在 | 未実施 |
| IT-01-11 | 鍵の形式 | Python が出力した公開鍵の一覧(`test-keys.json`)を、Swift の `PublicKeyRing` で読む | 読み込めて、その鍵で検証できる。複数の鍵があれば、すべてを試す | 自動: `PackVerifierTests.loadsTestKeys`、`test_sign.test_key_rotation_tries_all_keys` | 現在 | 未実施 |
| IT-01-12 | パックのファイルと Schema | ビルドしたパックの全 JSON を、対応する Schema で検証する | すべて Schema に合う | 自動: `test_build_pack.test_pack_files_validate_against_schema`、`test_manifest_validates_against_schema` | 現在 | 未実施 |
| IT-01-13 | カタログの形式 | Python が作ったカタログを、Swift でデコードする。未公開の試験を含める | デコードでき、未公開の試験の版は `null` である | 自動: `CatalogTests.decodeCatalog`、`unreleasedExam`、`test_generated.test_pack_catalog_describes_both_exams` | 現在 | 未実施 |
| IT-01-14 | Schema の変更の追随 | Schema にキーを 1 つ足し、Swift の型を更新しない | CI のどれかが失敗する(fixture の再生成の漏れ、または Swift のデコードの不一致) | 手動 | 現在 | 未実施 |
| IT-01-15 | 同じ文字列の規則 | パスと ID の正規表現を、Schema・Python・Swift で比べる | 3 か所の規則が一致する([SEC-01-08](../SEC/SEC-01-ContentPackIntegrity.md) と同じ) | 手動 | 現在 | 未実施 |

## 3. 既存のテストで覆われていない点

- **IT-01-14**: Schema にキーを足しても、Swift の型が未知のキーを無視する設定なら、テストは失敗しない。変更の漏れをどこまで自動で検出できるかを、実際に試して記録する。CI は、Schema と fixture の変更で `domainmodels-test.yml` と `data-test.yml` を動かす。
- **IT-01-15**: 正規表現の一致は、同じ fixture(`path-traversal` など)で間接的に確認している。規則そのものを比べるテストは見当たらない。
- エクスポートした JSON(学習データ)を読む側の契約は、読み込む機能がないため対象外である。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | Swift の型が、未知のキーをエラーにするか無視するか(古いアプリに新しいパックを配る場合の互換性と、変更の漏れの検出のどちらを優先するか) | P5 の着手前 |
