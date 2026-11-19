# IT-03 Persistence(SwiftData での保存・移行・統合・削除)

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 結合テスト |
| 対応要件 | NFR-04、NFR-09、FR-ACCT-01、FR-ACCT-03、E-05、BDD 5.3、BDD 6.9、[DDD-P3](../DDD/DDD-P3-Persistence.md) P3-S01〜S09 |
| 対象 | `ModelContainerFactory`、各リポジトリ(受験、解答履歴、カード、ブックマーク、設定)、`SyncDeduplicator`、`DataManagement`、`SwiftDataReportQueue` と、実際の SwiftData のストア(インメモリとディスク) |
| 既存のテスト | [PersistenceTests](../../packages/Data/Tests/PersistenceTests/)(11 ファイル) |

---

## 1. テストの観点

リポジトリを、実際の SwiftData のストアにつないで確認する。

- **保存と読み出し**: 保存した値が、そのまま読めること。コンテナを作り直しても(アプリの再起動に相当)残ること。
- **まとめての保存**: 解答とスナップショットなど、同時に変わるものを 1 回で保存すること。失敗時に 1 回だけ再試行し、だめなら元へ戻すこと。
- **試験ごとの分離**: 別の試験のデータを、読まない・書き換えない・消さないこと。
- **壊れた値**: 保存済みの値が読めない場合に、黙って別の値にしないこと。
- **スキーマの制約と移行**: CloudKit で使える形であること。以前の版のストアを開けること。
- **同期後の統合**: 端末間で重複した記録を、決めた規則で 1 つにすること。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| IT-03-01 | 受験の開始から確定まで(NFR-04) | 受験を開始し、解答を 1 問ずつ保存し、確定する | 各段階の内容を読み出せる。進行中の受験を見つけられる | 自動: `ExamAttemptRepositoryTests.startAndFindInProgressAndRoundTrip`、`recordEachAnswerAndFinalize` | 現在 | 未実施 |
| IT-03-02 | 再起動後の保持(AC-02) | 解答を保存し、コンテナを作り直す | 保存した解答が残っている | 自動: `ExamAttemptRepositoryTests.recordSurvivesNewContainer`、`SchemaV1Tests.diskStoreReopensRecords` | 現在 | 未実施 |
| IT-03-03 | 解答とスナップショットの同時の保存 | 解答の保存の途中で失敗させる | 解答だけ、またはスナップショットだけが保存された状態にならない | 自動: `ExamAttemptRepositoryTests.recordSavesSnapshotAtomically`、`saveRejectsActiveSnapshotWithoutTimer` | 現在 | 未実施 |
| IT-03-04 | 保存の再試行と巻き戻し(E-05) | 保存を 1 回、または 2 回続けて失敗させる | 1 回の失敗は再試行で保存する。2 回続けて失敗したら、変更を巻き戻してエラーを返す | 自動: `ExamAttemptRepositoryTests.saveRetriesAndRollsBack` | 現在 | 未実施 |
| IT-03-05 | 試験と受験の取り違え | 別の試験の受験、存在しない受験を指定して保存する | 拒否する | 自動: `ExamAttemptRepositoryTests.rejectsWrongExamAndMissingAttempt` | 現在 | 未実施 |
| IT-03-06 | 受験の履歴 | 提出済み・破棄・別の試験の受験が混ざった状態で、履歴を読む | 破棄した受験と、別の試験の受験を含めない | 自動: `ExamAttemptRepositoryTests.historyOmitsAbandonedAndOtherExams` | 現在 | 未実施 |
| IT-03-07 | 解答の履歴 | 模試・練習などの各モードで解答する。2 つの試験で解答する | 直近の正誤と準備度の入力に、全モードが入る。出題済み・フラグ・正誤は試験ごとに分かれる。フラグの時刻は注入した時計に従う | 自動: `AnswerHistoryRepositoryTests.lastResultAndReadinessIncludeEveryMode`、`servedFlagsAndResultsArePerExam`、`flagUsesInjectedTime` | 現在 | 未実施 |
| IT-03-08 | 壊れた保存値 | 未知のモード、読めない選択内容、未知の種類のブックマークを、ストアに直接入れる | 未知の値をエラーにする。読めない選択内容は、その記録だけを集計から外す | 自動: `AnswerHistoryRepositoryTests.rejectsUnknownStoredMode`、`outcomesSkipUndecodableSelection`、`BookmarkRepositoryTests.unknownTargetTypeIsCorrupted`、`ReportQueueTests.unknownReasonIsCorrupted` | 現在 | 未実施 |
| IT-03-09 | カードの状態と学習の記録 | カードを評価して保存する。問題からカードを 2 回作る。日をまたいで評価する | 状態を保存し、記録を追記する。ほかのカード・試験を変えない。問題のカードは 1 枚だけ。その日の学習数を、日の境界で正しく数える | 自動: `CardStateRepositoryTests.applyRoundTripsAndAppendsLogs`、`singleCardLookupAndApplyPreserveOtherCardsAndExams`、`questionCardIsIdempotentAndPerExam`、`reviewCountUsesHalfOpenDayAndFirstEverReview` | 現在 | 未実施 |
| IT-03-10 | 設定 | 設定のない状態で読む。試験ごとの設定を保存する。範囲の外の値を保存する。行が重複した状態で読む | 既定値を返す。試験ごとに分かれる。範囲の外の値を拒否する。重複は新しい方を使う | 自動: `SettingsRepositoryTests.defaultsWhenEmptyAndSavesCurrentExam`、`preferenceIsPerExam`、`retentionValidated`、`duplicateRowsUseLatestAndUnknownLanguageFails` | 現在 | 未実施 |
| IT-03-11 | ブックマークと既読 | 付け外しし、種類と試験で絞り込む。既読を 2 回付ける | 付け外しと絞り込みが正しい。既読は 1 件だけで、試験ごとに分かれる | 自動: `BookmarkRepositoryTests.togglesAndFiltersByTypeAndExam`、`readMarksAreIdempotentAndIsolated` | 現在 | 未実施 |
| IT-03-12 | 複数のリポジトリの直列化 | あるリポジトリの保存の途中で、別のリポジトリから読む、または削除する | 保存の完了を待ってから実行する | 自動: `WriteCoordinationTests.readOrDeletionWaitsForAnotherRepositoryToSave` | 現在 | 未実施 |
| IT-03-13 | スキーマの制約(FR-ACCT-01) | スキーマの定義を調べる | 全プロパティに既定値があり、一意の制約がなく、リレーションが任意である(CloudKit で使える形) | 自動: `SchemaV1Tests.schemaContainsAllColumns`、`allPropertiesHaveDefaults`、`noUniqueAttributes`、`relationshipsAreOptional` | 現在 | 未実施 |
| IT-03-14 | 保存先の指定 | インメモリ、ディスク(保存先あり・なし・ファイル以外の URL)でコンテナを作る | インメモリはファイルを作らず、CloudKit を使わない。ディスクは保存先の指定が必須で、ファイル以外の URL を拒否する | 自動: `SchemaV1Tests.inMemoryDoesNotCreateFilesOrEnableCloudKit`、`diskStoreRequiresExplicitDirectory`、`diskStoreRejectsNonFileURL`、`storeIsInAppGroup` | 現在 | 未実施 |
| IT-03-15 | ストアの移行 | 移行計画の導入前に作った V1 のストアを、今のコードで開く | 記録を失わずに開ける | 自動: `MigrationPlanTests.reopensExistingV1StoreWithoutLosingRecords`、`containerUsesPlan` | 現在 | 未実施 |
| IT-03-16 | 重複の統合(BDD 6.9) | 同じカード、同じ模試の進行中の受験、設定が重複した状態で、統合を実行する。2 回実行する | カードは最後の学習が新しい方、受験は進みの大きい方を残す。追記だけの記録は消さない。2 回目は何も変えない。受験を統合したら、通知が必要であることを返す | 自動: `SyncMergeTests.cardStateKeepsLatestReviewOrSmallestID`、`attemptsKeepMostProgressAndIgnoreCompleted`、`deduplicatorKeepsAppendOnlyLogsAndIsIdempotent`、`deduplicatorKeepsLatestSettingsAndOldestMarkers` | 現在 | 未実施 |
| IT-03-17 | 統合の安全性 | 壊れたスナップショットを含む重複で、統合を実行する。別の試験の記録を含める | 判断できないときは、何も削除しない。別の試験の記録に触れない | 自動: `SyncMergeTests.corruptedSnapshotPreventsAnyDeletion`、`differentExamsAndAppendOnlyAreUntouched`、`deduplicatorAbandonsBothStatusAndSnapshot` | 現在 | 未実施 |
| IT-03-18 | 書き出し(FR-ACCT-03) | 全種類の記録を入れて書き出す。試験を指定して書き出す。2 回書き出す | 全種類・全項目・リレーションを含む。試験を指定すると、その試験だけになる。同じ内容なら同じ出力になる | 自動: `DataManagementTests.exportContainsEveryEntityColumnAndRelationship`、`exportIsDeterministicAndCanFilterByExam` | 現在 | 未実施 |
| IT-03-19 | 削除(FR-ACCT-03) | 試験を指定して削除し、続けて全体を削除する。削除の途中で失敗させる | 試験を指定すると、ほかの試験と全体の設定が残る。全体の削除ですべて消える。失敗したら巻き戻す | 自動: `DataManagementTests.deleteExamPreservesOtherExamAndGlobalSettingsThenDeleteAll`、`failedDeletionRollsBack` | 現在 | 未実施 |
| IT-03-20 | 誤り報告のキュー | 報告を保存し、コンテナを作り直す。試験で絞り込む。一部を消す | 再起動後も残る。古い順に返し、試験で絞り込める。指定したものだけを消す。CloudKit を使わない別のストアである | 自動: `ReportQueueTests.queuePersists`、`pendingIsOldestFirstAndFiltersByExam`、`removeDeletesOnlyGivenIDs`、`removeAllRespectsExam`、`containerIsLocalOnlyWithPlan` | 現在 | 未実施 |
| IT-03-21 | 大量のデータ | 1 年分に相当する記録(BDD 5.4 の見積もり)を入れて、ホームと分析の読み出し、書き出し、削除を実行する | 決めた時間内に終わり、メモリを使い切らない | 自動(追加) | リリース前 | 未実施 |
| IT-03-22 | 次のスキーマへの移行 | V1 のストアを、スキーマを変えた次の版(V2)で開く | 記録を失わずに移行する | 自動(追加) | P6 | 未実施 |

## 3. 既存のテストで覆われていない点

- **IT-03-21**: 大量のデータでの性能を確認するテストは見当たらない。BDD 5.4 のデータ量の見積もりを基準にする。
- **IT-03-22**: スキーマは V1 だけで、移行の段階がまだない。スキーマを変えるときに追加する。
- CloudKit を有効にした状態での同期は、自動テストでは確認できない(IT-05-17、手動)。
- リモートの CI での実行は未確認である(CLAUDE.md の記載)。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 大量のデータの基準値(記録の件数と、許容する時間) | リリース前 |
