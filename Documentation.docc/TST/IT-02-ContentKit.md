# IT-02 ContentKit(パックの読み込み・版の選択・保存・起動)

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 結合テスト |
| 対応要件 | FR-CONT-01、NFR-01、NFR-02、NFR-03、E-01、E-07、BDD 6.8、[DDD-P2](../DDD/DDD-P2-ContentPack.md) P2-S06〜S09 |
| 対象 | `PackLoader`、`ContentIntegrityChecker`、`PackStore`、`BundledPacks`、`ExamCatalogService`、`ContentBootstrapper`、`ExamContentResolver` と、実際のファイルシステム・署名付きの fixture |
| 既存のテスト | [ContentKitTests](../../packages/Data/Tests/ContentKitTests/)(10 ファイル) |

---

## 1. テストの観点

実際のファイルと署名付きの fixture を使い、パックの読み込みから起動までをつないで確認する。

- **版の選び方**: 同梱版とインストール版のどちらを使うか。アプリの更新で同梱版が新しくなった場合。インストール版のディレクトリが消えている場合。
- **起動時の処理**: 初回の起動、2 回目以降、本文を読まないこと、1 つの試験の破損がほかの試験を止めないこと、全試験が使えない場合。
- **遅延の読み込み**: 起動時は索引だけ、必要なドメインだけ、同時の要求でのキャッシュの共有。
- **保存の状態の遷移**: インストール → 有効化 → 版戻し、受験中の版の固定と解除、保持する件数、不要な版の削除、再起動後の保持。
- **異常**: ファイルの欠落・破損、試験 ID と版の不一致、安全でない保存先。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| IT-02-01 | 初回の起動(FR-CONT-01) | 保存先が空の状態で、同梱パックから起動する | 同梱版を複製せずに有効化する。問題の本文を読まない | 自動: `ContentBootstrapperTests.firstLaunchActivatesBundledWithoutCopyOrBodyReads`、`ExamCatalogServiceTests.firstLaunchUsesBundledWithoutCopy` | 現在 | 未実施 |
| IT-02-02 | 版の選択 | インストール版が同梱版より新しい。同梱版がインストール版より新しい(アプリの更新後)。同じ版 | 新しい方を使う。同じ版ならインストール版を保つ。入出力をしない純粋な関数と、サービスの結果が一致する | 自動: `ActiveLocationTests.resolvesWithoutIO`、`serviceSelectsVersion`、`ExamCatalogServiceTests.newerInstalledWins`、`newerBundledWinsAfterAppUpdate` | 現在 | 未実施 |
| IT-02-03 | アプリの更新後の有効化 | 新しい同梱版を持つアプリで起動する | 新しい同梱版を有効化し、それまでのインストール版を「前の版」として残す | 自動: `ContentBootstrapperTests.newerBundledActivationKeepsInstalledAsPrevious` | 現在 | 未実施 |
| IT-02-04 | 状態と実体のずれ | 状態ファイルはインストール版を指すが、ディレクトリがない。状態ファイルが古い同梱版を指す | 同梱版へ切り替える。実際にある同梱版を使う | 自動: `ActiveLocationTests.missingInstalledDirectoryFallsBackToBundle`、`ExamCatalogServiceTests.staleBundledStateUsesActualBundle` | 現在 | 未実施 |
| IT-02-05 | 起動時の整合の確認 | 索引と試験定義が合わないパックで起動する | そのパックを有効化せず、前の状態を保つ。試験 ID・版の合わないパックを拒否する | 自動: `ContentBootstrapperTests.bootstrapVerifiesIntegrityAndPreservesPreviousStateOnFailure`、`rejectsMismatchedPackIdentity` | 現在 | 未実施 |
| IT-02-06 | 試験ごとの独立 | 2 つの試験のうち、片方の状態ファイルを壊す | 壊れていない試験は使える。壊れた試験は失敗として報告する | 自動: `ContentBootstrapperTests.brokenStateDoesNotBlockOtherExams`、`ExamCatalogServiceTests.brokenStateIsIsolatedPerEntry` | 現在 | 未実施 |
| IT-02-07 | 使える試験がない(E-01) | 全試験が読み込めない。カタログが空 | 致命的なエラーとして報告する | 自動: `ContentBootstrapperTests.bootstrapFailsWhenNoUsableExam`、`emptyCatalogReportsFatalError` | 現在 | 未実施 |
| IT-02-08 | カタログの状態 | 近日公開、公開終了(インストール済み・未インストール)の試験を含むカタログ | 近日公開は一覧に出るが読み込まない。公開終了は、インストール済みのときだけ出す | 自動: `ContentBootstrapperTests.comingSoonIsNotLoadable`、`ExamCatalogServiceTests.comingSoonIsListedButNotAvailable`、`retiredHiddenUnlessInstalled` | 現在 | 未実施 |
| IT-02-09 | 遅延の読み込み(NFR-01) | パックを読み込み、問題を要求する。同時に複数の要求を出す | 読み込み時は索引などの軽い部分だけを読む。問題は必要なドメインだけを読み、キャッシュを共有する。要求した順で返す | 自動: `PackLoaderTests.loadsEagerParts`、`doesNotReadQuestionBodiesAtLoad`、`questionsReadOnlyNeededDomainsAndAreCached`、`concurrentRequestsShareCache`、`questionsKeepRequestedOrder` | 現在 | 未実施 |
| IT-02-10 | 模試 1 回分の読み込み(NFR-02) | 模試 1 回分の全問を読み込む | 決めた時間内に終わる | 自動: `PackLoaderTests.loadAllQuestionsForExamSetUnderBudget`(55 問を読めることだけを確認し、所要時間は出力するだけで判定しない)。時間の判定は手動(出力の確認、または Instruments) | 現在 | 未実施 |
| IT-02-11 | ファイルの欠落と破損 | 問題のファイルを消す、壊す。存在しない問題 ID を要求する。別の試験のドキュメントの項目を渡す | 欠落・破損・不明な ID を区別して報告する。別の試験の項目を拒否する | 自動: `PackLoaderTests.missingAndUndecodableFiles`、`unknownQuestionID`、`rejectsForeignDocEntry`(索引にない項目 `../outside.md` を拒否する。パスの外出しの確認であり、別の試験の項目の確認ではない)。別の試験のドキュメントの項目を拒否することは自動(追加) | 現在 | 未実施 |
| IT-02-12 | 機能の有無 | 機能が無効な試験で、その機能のコンテンツを要求する | 無効な機能のコンテンツは読み込まない | 自動: `PackLoaderTests.disabledFeature`、`enabledFeatures` | 現在 | 未実施 |
| IT-02-13 | インストール・有効化・版戻し | staging からインストールし、有効化し、版戻しする。保存先を開き直す | staging が版のディレクトリへ移る。有効化で「前の版」が入れ替わり、開き直しても保たれる。既存の版への上書きは拒否する | 自動: `PackStoreTests.installMovesStagingIntoVersions`、`installRefusesExistingVersion`、`activateShiftsPreviousAndSurvivesReopen`、`activateIsAtomic`、`bundledIsNeverDeletedAndRollback` | 現在 | 未実施 |
| IT-02-14 | 受験中の版の固定(E-07) | 版を固定し、不要な版の削除を実行する。固定を外して、もう一度実行する。同梱にしかない版を固定する | 固定した版は消えない。外すと消せる。同梱にしかない版は、保存先へ複製してから固定する | 自動: `PackStoreTests.pinKeepsVersionAndUnpinAllowsRemoval`、`pinCopiesBundledVersionIntoStore`、`pinRejectsUnavailableOrMismatchedVersion` | 現在 | 未実施 |
| IT-02-15 | 提出後の版の保持 | 保持の上限を超える件数の受験を、順に提出する | 新しい受験から上限の件数だけ、固定を残す。古い形式の状態ファイルも読める | 自動: `PackStoreTests.retainKeepsLatestSubmittedAttempts`、`stateWithoutRetainedDecodes` | 現在 | 未実施 |
| IT-02-16 | 古い版の解決 | 受験で固定した古い版を、有効化せずに読む。同梱版が入れ替わったあとで読む | 固定した版の内容を返す。現在の版を変えない。試験 ID・版の合わないパックを拒否する | 自動: `ExamContentResolverTests.resolvesOldBundledVersionWithoutActivatingIt`、`pinnedBundledVersionResolvesAfterBundleChanges`、`resolvesInstalledVersionAndRejectsIdentityMismatch` | 現在 | 未実施 |
| IT-02-17 | 保存先の独立と安全性 | 2 つの試験を同じ保存先で使う。試験 ID や版に `../` を含む値を渡す | 試験ごとに状態が分かれる。安全でない値を拒否し、保存先の外に何も作らない | 自動: `PackStoreTests.perExamIsolation`、`refusesUnsafeLocations`、`refusesMissingInstalledVersion` | 現在 | 未実施 |
| IT-02-18 | 内容の整合の違反 | 不明なドメイン・サブ項目・ケース、対応していない問題の種類、模試が指す問題の欠落などを含むパック | それぞれを違反として報告する。正常なパックでは違反がない。起動時の確認は本文を読まない | 自動: `ContentIntegrityCheckerTests.validPacksHaveNoViolations`、`unknownDomain`、`unsupportedKind`、`examSetReferencesMissingQuestion`、`startupDoesNotReadBodies` ほか | 現在 | 未実施 |
| IT-02-19 | 容量の不足と途中の中断 | 複製や移動の途中で、書き込みを失敗させる(容量の不足、強制終了を模す) | 中途半端な版を有効化しない。staging の残りを次回に片づける | 自動(追加) | P5 | 未実施 |

## 3. 既存のテストで覆われていない点

- **IT-02-19**: 状態ファイルの書き込みがアトミックであることは `activateIsAtomic` が確認する。複製の途中での失敗と、残った staging の片づけを確認するテストは、テスト名からは特定できなかった。差分更新(P5-S03)で staging を多く使うようになるため、そのときに追加する。
- 本番の規模のパック(約 330 問)での読み込み時間は、実際のパックができてから確認する(E2E-06-02)。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 残った staging を片づけるタイミング(起動時か、更新の確認時か) | P5-S03 |
