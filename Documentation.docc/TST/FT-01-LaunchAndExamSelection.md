# FT-01 起動・試験選択・ホーム・タブ

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 機能テスト |
| 対応要件 | FR-CONT-01、SCR-001、E-01、BDD 4.1、[DDD](../DDD.md) 4 章、[DDD-P4](../DDD/DDD-P4-AppMVP.md) P4-S02・S03・S05 |
| 対象 | `ActiveExamContext`、`ExamPickerViewModel`、`HomeViewModel`、`AppRouter` |
| 既存のテスト | [ActiveExamContextTests](../../packages/Presentation/Tests/AppCoreTests/ActiveExamContextTests.swift)、[HomeViewModelTests](../../packages/Presentation/Tests/AppCoreTests/HomeViewModelTests.swift)、[AppRouterTests](../../packages/Presentation/Tests/AppCoreTests/AppRouterTests.swift) |

---

## 1. テストの観点

- **起動時の試験の決め方**: 前回の選択がある / ない、利用できる試験が 0・1・複数、前回の試験が使えなくなった、の組み合わせ。
- **試験の切り替え**: 進行中の模試の中断保存、設定の保持、画面の経路のリセット。保存に失敗した場合と、連続して操作した場合。
- **ホームの表示**: データがない状態、復習期限、弱点、再開の導線。読み込みの失敗を「データなし」と取り違えないこと。
- **タブと経路**: タブごとに経路が独立していること、提出後に解答画面へ戻れないこと。
- **機能の有無**: 試験定義で無効な機能(カード、ケースなど)の入口を出さないこと。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| FT-01-01 | 前回の試験の復元 | 前回の選択が保存されていて、その試験が利用できる状態で起動する | 選択画面を出さず、前回の試験のホームを表示する | 自動: `ActiveExamContextTests.restoresLastExam` | 現在 | 未実施 |
| FT-01-02 | 試験が 1 つだけ | 利用できる試験が 1 つで、前回の選択がない | その試験を自動で選び、選択を保存する | 自動: `ActiveExamContextTests.singleExamAutoSelectedAndSaved` | 現在 | 未実施 |
| FT-01-03 | 試験が複数 | 利用できる試験が複数で、前回の選択がない | 試験の選択画面を表示する | 自動: `ActiveExamContextTests.multipleExamsShowPicker` | 現在 | 未実施 |
| FT-01-04 | 前回の試験が使えない | 前回の試験が読み込みに失敗、または公開終了になっている | 別の試験を黙って選ばず、選択画面を表示する | 自動: `ActiveExamContextTests.unavailableLastExamDoesNotSilentlySelectAnother` | 現在 | 未実施 |
| FT-01-05 | 利用できる試験がない(E-01) | 全試験の読み込みに失敗する | 致命的エラーの画面を表示する | 自動: `ActiveExamContextTests.noExamAvailableIsFatal` | 現在 | 未実施 |
| FT-01-06 | 選択画面の表示 | 近日公開・公開終了・読み込み失敗の試験を含むカタログ | 近日公開は選べない状態で表示する。未インストールの公開終了と読み込み失敗は選べない。商標の表示がある。ベンダーは重複なく並ぶ | 自動: `ActiveExamContextTests.pickerDisablesComingSoonAndShowsTrademark`、`failedAndUninstalledRetiredExamsCannotBeSelected`、`vendorsAreUniqueAndSorted` | 現在 | 未実施 |
| FT-01-07 | 試験の切り替え | 模試の進行中に、別の試験を選ぶ | 進行中の模試を中断として保存し、試験ごとの設定を保ち、全タブの経路を初期化する | 自動: `ActiveExamContextTests.switchSuspendsAttemptPreservesSettingsAndResetsNavigation`(経路のあるカード・学ぶ・分析・試験の各タブに経路を積んでから切り替え、全タブが空になることを確認する) | 現在 | 未実施 |
| FT-01-08 | 切り替えの保存失敗 | 切り替え時の保存を失敗させる | 元の試験と経路のままで、保存に失敗したことを表示する | 自動: `ActiveExamContextTests.failureKeepsActiveExamAndNavigation` | 現在 | 未実施 |
| FT-01-09 | 切り替えの連続操作 | 保存の完了を待たずに、別の試験を続けて選ぶ | 後の操作を受け付けず、最初の選択が上書きされない | 自動: `ActiveExamContextTests.concurrentSwitchDoesNotOverwritePendingSelection` | 現在 | 未実施 |
| FT-01-10 | 復元の繰り返し | 起動時の復元処理を 2 回呼ぶ | 開いていた画面の経路を捨てない | 自動: `ActiveExamContextTests.repeatedRestoreDoesNotDiscardNavigation` | 現在 | 未実施 |
| FT-01-11 | ホーム(データなし) | 学習履歴がない状態でホームを開く | 試験名と、データがないことを示す表示、学習への導線を出す | 自動: `HomeViewModelTests.showsExamNameAndNoDataYet` | 現在 | 未実施 |
| FT-01-12 | ホーム(復習期限と弱点) | 期限の来たカードと、ドメインごとに差のある解答履歴を用意する | 期限の来たカードの枚数と、正答率の最も低いドメインを表示する。同率なら試験定義の順。ほかの試験の履歴を含めない | 自動: `HomeViewModelTests.dueCardCount`、`weakestDomainAndExamIsolation`、`tiedDomainsFollowDefinitionOrder` | 現在 | 未実施 |
| FT-01-13 | ホーム(再開の導線) | 中断中の模試がある | 再開のバナーを表示し、タップで解答画面へ進む | 自動: `HomeViewModelTests.resumeBanner`、`homeEntryPointsReplaceExamPath` | 現在 | 未実施 |
| FT-01-14 | ホーム(読み込みの失敗) | 履歴の読み込みを失敗させる | 「データなし」と表示せず、失敗を示す。ほかの導線は使える。再読み込みで回復する | 自動: `HomeViewModelTests.failureIsNotEmptyHistory`、`historyFailureKeepsOtherEntryPoints`、`refreshReplacesHistoryAndRetryClearsError` | 現在 | 未実施 |
| FT-01-15 | ホーム(更新の競合) | 読み込みの途中で再読み込みを要求する、または画面を離れる | 最後の要求の結果を表示し、古い結果で上書きしない | 自動: `HomeViewModelTests.refreshDuringLoadRunsAgain`、`cancelledRefreshStillAppliesResults` | 現在 | 未実施 |
| FT-01-16 | タブごとの経路 | あるタブで画面を進めてから、別のタブへ移り、戻る | 各タブの経路が独立して保たれる。全 15 種類の遷移先にタブが割り当てられている | 自動: `AppRouterTests.openSwitchesTabAndKeepsIndependentPaths`、`everyRouteHasATabAndNavigationPopIsWritable` | 現在 | 未実施 |
| FT-01-17 | 機能が無効な試験 | カード機能が無効な試験定義でホームを開く | カードの情報を読み込まず、入口を表示しない | 自動: `HomeViewModelTests.disabledCardsAreNotLoaded` | 現在 | 未実施 |
| FT-01-18 | 起動中と起動失敗の表示 | 起動処理の完了前、および起動処理を失敗させた状態で `AppRootView` を表示する | 完了前は読み込み中の表示、失敗時は「データの読み込みに失敗しました」を表示する | 自動(追加) | 現在 | 未実施 |

## 3. 既存のテストで覆われていない点

- **FT-01-18**: 起動中・起動失敗の表示は `AppRootView`(View)の中にあり、ViewModel のテストでは確認できない。UI テストの `StartupTests.testInvalidLaunchArgumentsShowFailure` が失敗の表示を確認している(E2E-04-05)。読み込み中の表示は自動テストが見当たらない。
- 起動時に選択の保存が失敗した場合の表示(`StartupPersistenceFailed` の記録)は、対応するテストをテスト名からは特定できなかった。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | E-01 の画面の文言を BDD 9 章の「再インストールしてください」まで含めるか(現在は `error.contentLoadFailed`) | P4-S18 |
