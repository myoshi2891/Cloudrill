# FT-09 コンテンツのツール(検証・ビルド・署名・カタログ)

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 機能テスト |
| 対応要件 | FR-CONT-04、AC-06、NFR-05、RDD 10.3、BDD 10 章、[DDD-P0](../DDD/DDD-P0-MultiExamContent.md)、[DDD-P2](../DDD/DDD-P2-ContentPack.md) P2-S02・S03 |
| 対象 | `content/scripts/validate.py`、`build_pack.py`、`sign_manifest.py`、`build_catalog.py`、`contentvalidate/`、`contentpack/` |
| 既存のテスト | [content/tests/](../../content/tests/) の `test_cli.py`、`test_rules.py`、`test_config.py`、`test_loader.py`、`test_schemas.py`、`test_build_pack.py`、`test_sign.py`、`test_catalog.py`、`test_extensibility.py`、`test_perf.py` |

---

## 1. テストの観点

- **コマンドの契約**: 終了コード(0・1・2)、オプション(`--only`、`--exam`、`--strict`、`--format`、`--check-links`)、出力の形式。
- **ルールの検出**: 各ルール(CI-01〜CI-13)が、違反を検出し、違反のないものを誤って報告しないこと。
- **決定論**: 同じ入力から、同じバイト列のパック・署名・カタログができること。
- **安全な失敗**: 検証に error がある、出力先がすでにある、鍵や引数に不備がある場合に、途中の生成物を残さずに止まること。
- **拡張性**: 検証ツールに、試験ごとの分岐や固有の値がないこと。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| FT-09-01 | 検証の終了コード | 違反のないコンテンツ、error のあるコンテンツ、存在しないルートや壊れた設定を渡す | 順に 0・1・2 で終了する | 自動: `test_cli.test_exit_code_zero_for_valid`、`test_exit_code_one_on_error`、`test_missing_root_exits_two`、`test_broken_config_exits_two` | 現在 | 未実施 |
| FT-09-02 | warning の扱い | warning だけのコンテンツを、`--strict` なし・ありで検証する | なしでは 0、ありでは 1 で終了する | 自動: `test_cli.test_warning_only_exits_zero_unless_strict`、`test_rules.test_strict_promotes_warnings` | 現在 | 未実施 |
| FT-09-03 | ルールと試験の絞り込み | `--only CI-02,CI-03`、`--exam <ID>`、存在しないルール、存在しない試験 ID を指定する | 指定したルール・試験だけを検証する。存在しない指定は 2 で終了する | 自動: `test_cli.test_only_option`、`test_unknown_rule_in_only_exits_two`、`test_cli_exam_option_limits_exams`、`test_cli_unknown_exam_exits_2` | 現在 | 未実施 |
| FT-09-04 | 出力の形式 | `--format json`、`--format github` で出力する。メッセージに改行や `%` を含める | JSON は配列(違反なしなら空)。GitHub 形式はエスケープされ、パスはワークスペースからの相対になる | 自動: `test_cli.test_json_format`、`test_json_format_empty_list_for_valid`、`test_github_format`、`test_github_escaping`、`test_github_paths_are_relative_to_workspace` | 現在 | 未実施 |
| FT-09-05 | 各ルールの検出 | 違反ケースの fixture(valid との差分)を、ルールごとに検証する | 全ルールに違反ケースがあり、`expected.yaml` に書いたルールと深刻度だけを検出する。valid の fixture では何も検出しない | 自動: `test_rules.test_every_rule_has_an_invalid_case`、`test_invalid_case_detects_only_expected_rules`、`test_valid_fixture_passes_all_rules` | 現在 | 未実施 |
| FT-09-06 | 違反の連鎖の防止 | Schema に違反したファイルを含むコンテンツを検証する。`--only` で CI-01 を外す | Schema 違反のファイルを、ファイル間のルールの対象から外す。試験定義が違反なら、それを使うルールは何も報告しない | 自動: `test_rules.test_only_without_ci01_still_skips_schema_invalid_files`、`test_rules_skip_when_exam_definition_invalid`、`test_ci05_delegation_does_not_report_ci01` | 現在 | 未実施 |
| FT-09-07 | 行番号と重複キー | 違反のある行、YAML の構文エラー、重複したキーを含むファイル | 違反に行番号を付ける。重複したキーをエラーにする | 自動: `test_rules.test_issue_reports_line_number`、`test_yaml_syntax_error_has_line`、`test_duplicate_yaml_key_is_reported` | 現在 | 未実施 |
| FT-09-08 | 設定の重ね合わせ | 全体の `validation.yaml` に、試験ごとの設定を重ねる。未知のキー・型の違う値を入れる | 試験ごとの値で上書きする(入れ子は深くマージ、リストは置き換え)。不備は 2 で終了する | 自動: `test_config.test_exam_config_overrides_global_threshold`、`test_exam_config_merges_nested_mapping`、`test_exam_config_replaces_list`、`test_exam_config_rejects_unknown_key`、`test_cli_bad_exam_config_exits_2` | 現在 | 未実施 |
| FT-09-09 | リポジトリのコンテンツ(AC-06) | リポジトリの `content/` を検証する | error が 0 件である | 自動: `test_cli.test_repository_content_has_no_errors` | 現在 | 未実施 |
| FT-09-10 | 試験ごとの分岐がないこと | 検証ツールのソースを調べる。形の違う 2 つの試験を検証する | 試験固有の値や分岐がない。別の試験で同じ ID を使える | 自動: `test_extensibility.test_validator_has_no_exam_specific_literals`、`test_each_exam_fixture_is_validated`、`test_same_id_in_other_exam_is_allowed` | 現在 | 未実施 |
| FT-09-11 | パックのビルド | `build_pack.py` を、正しい引数、`SOURCE_DATE_EPOCH` なし、既存の出力先、検証 error のあるコンテンツで実行する | 順に、成功(0)、引数の不備(2)、出力先の不備(2)、検証 error(1)。warning だけならビルドする | 自動: `test_build_pack.test_build_requires_source_date_epoch`、`test_build_refuses_existing_output`、`test_build_aborts_on_validation_error`、`test_build_allows_warnings`、`test_build_rejects_bad_arguments` | 現在 | 未実施 |
| FT-09-12 | パックの決定論と内容 | 同じ入力で 2 回ビルドする | バイト列が一致する。manifest が、`manifest.json` と `manifest.sig` を除く全ファイルを、パスの順で持ち、ハッシュが一致する。問題はドメインごとに分かれ、索引と一致する | 自動: `test_build_pack.test_build_is_deterministic`、`test_manifest_lists_all_files_sorted`、`test_manifest_hashes_match`、`test_questions_split_by_domain`、`test_index_matches_questions` | 現在 | 未実施 |
| FT-09-13 | 署名 | `sign_manifest.py` を、正しい鍵、manifest の `keyID` と違う `--key-id`、不正な環境変数、Schema に合わない manifest で実行する | 成功時は manifest のバイト列を変えずに `manifest.sig` を作る。不備は 2 で終了し、鍵の内容を出力しない | 自動: `test_sign.test_sign_and_verify`、`test_sign_preserves_manifest_bytes`、`test_key_id_mismatch_exits_2`(`--key-id` の引数が manifest の `keyID` と違う場合だけを確認する)、`test_invalid_key_env_is_not_disclosed`、`test_sign_rejects_invalid_manifest` | 現在 | 未実施 |
| FT-09-18 | 鍵 ID と合わない署名鍵 | `--key-id` と manifest の `keyID` は一致させ、その鍵 ID の鍵とは別の秘密鍵で署名する | 署名ツールが拒否する(終了コード 2)か、拒否しない場合は、その署名のパックを検証が `signature_invalid` で拒否する | 検証側は 自動: `test_sign.test_unknown_key`(鍵リングに無い鍵の署名を拒否する)。署名ツールで拒否するかの確認は自動(追加) | 現在 | 未実施 |
| FT-09-14 | カタログの生成 | `build_catalog.py` を、初回、更新、版戻し、パックのない `available` で実行する | 初回と更新は成功し、同じ入力で同じ出力になる。版戻しと、パックのない `available` は拒否する。失敗時に既存の出力を壊さない | 自動: `test_catalog.test_catalog_from_source`、`test_catalog_update_entry`、`test_catalog_is_deterministic`、`test_catalog_rejects_downgrade`、`test_available_requires_pack`、`test_catalog_write_failure_preserves_output` | 現在 | 未実施 |
| FT-09-15 | 試験ガイドの版(FR-CONT-04) | 問題の試験ガイドの版が、試験定義と合わないコンテンツを検証する | CI-12 の warning を出し、該当する問題を特定できる | 自動: `test_rules.test_invalid_case_detects_only_expected_rules`(CI-12 のケース。ルール ID と深刻度だけを確認する)。版の合わない問題が複数あるときに、報告のファイルと全問の ID が正しいことは自動(追加) | 現在 | 未実施 |
| FT-09-16 | リンク切れの確認 | `--check-links` なし・ありで検証する。405 と、タイムアウトを返すサーバー | なしではネットワークにアクセスしない。405 は GET でやり直す。タイムアウトを報告する。同じ URL は 1 回だけ確認する | 自動: `test_rules.test_link_check_is_skipped_without_flag`、`test_link_check_retries_get_on_405_and_reports_timeout`(タイムアウトの報告を確認する。GET でのやり直しは、HEAD に 405 を返す URL が報告されないことで間接に確認する)、`test_link_check_dedupes_across_exams`。GET の要求を実際に送ったことの確認は自動(追加) | 現在 | 未実施 |
| FT-09-17 | 検証の所要時間 | 500 問のコンテンツを検証する | 決めた時間内に終わる | 自動: `test_perf.test_500_questions_within_time_limit` | 現在 | 未実施 |

## 3. 既存のテストで覆われていない点

- この観点の項目は、すべて既存の自動テストに対応づけられた。
- **FT-09-15**: CI-12 の違反ケースが fixture にあることは、`test_every_rule_has_an_invalid_case` が確認する。「改訂時に該当する問題を一括で抽出できる」(FR-CONT-04)の操作手順(`--only CI-12 --format json` の出力を使うなど)は、文書になっているかを別に確認する。
- 本番の規模(約 330 問 + カード + ドキュメント)での検証とビルドの所要時間は、コンテンツがそろってから確認する(E2E-07)。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 試験ガイドの改訂時に、該当する問題を抽出する手順の置き場所(`content/README.md` に書くか) | 作問開始前 |
