# E2E-07 コンテンツの制作からアプリでの表示まで

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | E2E |
| 対応要件 | AC-06、NFR-05、FR-CONT-01、FR-CONT-04、RDD 10 章、BDD 10 章、[DDD-P2](../DDD/DDD-P2-ContentPack.md)、[DDD-P5](../DDD/DDD-P5-Delivery.md) P5-S01 |
| 対象 | 原稿(YAML・Markdown)→ `validate.py` → `build_pack.py` → `sign_manifest.py` → `build_catalog.py` → 同梱(`bundle_packs.sh`)→ アプリでの表示。CI のワークフロー |
| 既存のテスト | [content/tests/](../../content/tests/)、[AppEnvironmentTests](../../packages/AppComposition/Tests/AppCompositionTests/AppEnvironmentTests.swift)、`.github/workflows/` の 7 件 |

---

## 1. シナリオと観点

コンテンツの担当者が原稿を書いてから、利用者の画面に出るまでの経路を、端から端まで通す。アプリの E2E(E2E-01〜06)が「利用者の操作」を通すのに対し、ここでは「コンテンツの流れ」を通す。

- **正常の経路**: 原稿 → 検証 → ビルド → 署名 → カタログ → 同梱 → 表示。
- **修正の経路**: 問題を 1 問直す → 版を上げる → 変わるのがその問題だけである。
- **止まるべき場所**: 検証の error、Schema の変更の漏れ、fixture の再生成の漏れ。
- **CI**: 変更したパスに応じて、必要なワークフローが動く。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| E2E-07-01 | リポジトリのコンテンツの検証(AC-06) | `content/.venv/bin/python content/scripts/validate.py` を実行する | error が 0 件で、終了コードが 0 である | 自動: `test_cli.test_repository_content_has_no_errors`、CI の `content-validate.yml` | 現在 | 未実施 |
| E2E-07-02 | 原稿から署名付きパックまで | fixture の原稿から、パックをビルドし、署名し、検証する | 検証に通るパックができる。同じ入力なら、同じバイト列になる | 自動: `test_build_pack.test_build_is_deterministic`、`test_sign.test_sign_and_verify`、`test_generated.test_packs_match_generator` | 現在 | 未実施 |
| E2E-07-03 | パックからアプリの起動まで | 開発用の同梱パックで、アプリの構成を作る | 期待する試験がカタログにあり、そのパックがそろっている。署名の検証に通り、試験を読み込める | 署名の検証と起動は 自動: `AppEnvironmentTests.bundledPacksArePresentAndSignaturesVerify`(カタログに載っている `available` の試験の `latestPackVersion` だけを検証する。カタログから試験が欠けていても成功する)、`uiTestingParsesArgumentsAndBootstrapsFixture`(`test-alpha` の 1.0.0 で起動する)。期待する試験とパックがそろっていることは自動(追加) | 現在 | 未実施 |
| E2E-07-04 | 同梱パックの再生成 | `scripts/bundle_packs.sh --development --out <新しいディレクトリ>` を実行し、コミット済みの `ExamPrepApp/Resources/Packs` と比べる | 内容が一致する。既存の出力先を指定すると、上書きせずに失敗する | 手動 | 現在 | 未実施 |
| E2E-07-05 | 問題の修正の流れ | 問題を 1 問直し、改訂番号と版を上げてビルドする | 問題のオブジェクトのうち、変わるのが直した 1 問だけで、その改訂番号が 1 つ上がる。ビルドの出力で、変わるファイルが、その問題を含むものと、索引・manifest だけである | 問題のオブジェクトの比較は 自動: `test_generated.test_revised_pack_changes_one_question`(生成済みの fixture のパックの問題を比べる。ビルドの出力のファイルは比べない)。2 つの版をビルドしてファイルを比べることは自動(追加) | 現在 | 未実施 |
| E2E-07-06 | 検証の error での停止 | error のあるコンテンツで、パックをビルドする | ビルドが止まり、出力先に何も残らない | 自動: `test_build_pack.test_build_aborts_on_validation_error` | 現在 | 未実施 |
| E2E-07-07 | Schema の変更の流れ | Schema を変え、CLAUDE.md の手順(Swift の型 → fixture の再生成 → JSON の再生成 → 両方のテスト)を通す | fixture の再生成を抜かすと `test_generated.test_fixtures_are_up_to_date`、JSON の再生成を抜かすと `test_generated.test_swift_fixtures_are_up_to_date` が失敗する。Swift の型の更新を抜かした場合に失敗するかは、Swift のデコードが未知のキーをどう扱うかに依存するので、IT-01-14 の実施結果を記録してから期待結果を確定する | 手動。fixture の鮮度は IT-01-01 | 現在 | 未実施 |
| E2E-07-08 | CI のワークフローの起動 | コンテンツだけ、Schema、Swift のパッケージ、アプリを、それぞれ変えたプルリクエストを作る | 変更したパスに対応するワークフローだけが動く。Schema と fixture の変更では、Python と Swift の両方が動く | 手動 | 現在 | 未実施 |
| E2E-07-09 | 修正した原稿の、アプリでの表示 | 作業は、コミット済みの状態から作った別の worktree(`git worktree add <パス> HEAD`)で行う。`content/.venv` は worktree に含まれないので、worktree のルートで `uv sync --project content` を実行し、Python の依存をそろえてから、次の生成と `scripts/bundle_packs.sh` を実行する(どちらも worktree の `content/.venv/bin/python` を使う)。fixture の生成器(`content/tests/fixtures/generate.py`)で問題文を直し、fixture を再生成する(`valid/` の YAML を直接直しても、再生成で消える)。`scripts/bundle_packs.sh --development --out <新しいディレクトリ>` で同梱パックを作り直す(内部で `generate_packs.py` が fixture からパックを作る)。Xcode のターゲットが同梱するのは `ExamPrepApp/Resources/Packs` なので、その内容を `--out` の出力で置き換えてから、アプリをビルドし直して入れる。前に入れた同じ版のパックが使われないよう、アプリを削除してから入れ直す(またはシミュレータを初期化し、空のコンテンツの保存先で起動する)か、パックの版を上げる。そのうえで、アプリで該当の問題を開く。確認のあとは、worktree ごと捨てる(`git worktree remove --force <パス>`)。生成器・再生成した fixture(`content/tests/fixtures/` の `valid/`・`valid-json/`・`packs/`)・同梱パックの変更をまとめて捨てるので、元の作業ツリーの生成器・fixture・同梱パックは一致したままで、`test_generated.test_packs_match_generator` は通る。同梱パックだけを戻すと、生成器と fixture の変更が残り、一致が崩れる | 直した文面が表示される | 手動 | 現在 | 未実施 |
| E2E-07-10 | 本番のパックの作成 | 本番のコンテンツ(`gcp-pca`)を、本番の鍵でビルド・署名し、Release のアプリに同梱して起動する | 検証に error がない。アプリが起動し、全機能で PCA の内容が出る。開発用のパックとテスト用の鍵が入っていない | 手動 | リリース前 | 未実施 |
| E2E-07-11 | 本番の規模での所要時間 | 本番の量のコンテンツ(RDD 6.1 の総量)で、検証とビルドを実行する | CI で待てる時間内に終わる | 手動 | リリース前 | 未実施 |
| E2E-07-12 | リリースのタグからの配信 | リリースのタグを作る | ワークフローがパックを公開する(E2E-05-01 と同じ) | 手動 | P5 | 未実施 |
| E2E-07-13 | リンク切れの定期の確認 | `content-link-check.yml` を手動で実行する | 出典の URL にアクセスし、切れているリンクがあればジョブが失敗する | 手動 | 現在 | 未実施 |
| E2E-07-14 | 試験ガイドの改訂への対応(FR-CONT-04) | 試験定義の試験ガイドの版を上げて、検証を実行する | 版の合わない問題が、CI-12 の warning として一覧できる | 手動。ルールの検出は FT-09-15 | 現在 | 未実施 |

## 3. 既存のテストで覆われていない点

- **E2E-07-03**: 期待する試験(`test-alpha`・`test-beta`)とそのパックがそろっていること。既存のテストはカタログの内容を基準にするので、試験の欠落と、最新でない同梱版(`test-alpha` の 1.0.0)の署名を確認しない。
- **経路の各区間**は、自動テストで確認している(E2E-07-01〜03、05、06。E2E-07-03 のパックの完全性と、E2E-07-05 のビルドの出力の比較を除く)。**区間をつないだ全体**(原稿を直してから、アプリの画面に出るまで。E2E-07-09)を通す自動テストは見当たらない。
- **E2E-07-04**: DDD-P4 に、52 ファイルの再生成が一致したという記録がある。コミット済みの同梱パックと、生成器の出力の一致を、CI で確認しているかは特定できなかった。
- **E2E-07-08**: ワークフローの `paths` の設定は目視できるが、実際のプルリクエストでの動作と、リモートの CI の結果は未確認である(CLAUDE.md の記載)。
- **E2E-07-10、11**: 本番のコンテンツがまだない(`content/catalog.yaml` の `gcp-pca` は `comingSoon`)。
- コンテンツの内容の正しさ(問題と解説が正確か)は、この文書群の対象外である。作問とレビューの体制(TBD-06)で扱う。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | コミット済みの同梱パックと、生成器の出力の一致を、CI で確認するか | P4-S18 |
| 2 | 本番のパックを同梱する手順([SEC-03](../SEC/SEC-03-DebugIsolation.md) の未決事項 2 と同じ) | P5-S01 |
