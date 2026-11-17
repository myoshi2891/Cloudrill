# FT-08 設定・データ管理・誤り報告

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 機能テスト |
| 対応要件 | FR-ACCT-03、FR-CONT-03、FR-EXAM-12、FR-CARD-04、FR-CARD-05、E-05、E-08、SCR-002、SCR-090、BDD 7.2、[DDD-P4](../DDD/DDD-P4-AppMVP.md) P4-S15・S16 |
| 対象 | `SettingsViewModel`、`ReportSheetViewModel`、`ActiveExamContext`(削除後の画面の作り直し) |
| 既存のテスト | [SettingsViewModelTests](../../packages/Presentation/Tests/AppCoreTests/SettingsViewModelTests.swift)、[ReportSheetViewModelTests](../../packages/Presentation/Tests/AppCoreTests/ReportSheetViewModelTests.swift)、[ActiveExamContextTests](../../packages/Presentation/Tests/AppCoreTests/ActiveExamContextTests.swift) |

---

## 1. テストの観点

- **設定の保存**: 試験ごとの学習設定と、全体の設定(シャッフル)。保存の失敗で、画面の値を元へ戻すこと。ほかの項目を上書きしないこと。
- **書き出し**: ファイルの作成と共有への受け渡し。失敗の表示。
- **削除**: 確認を必ず挟むこと。試験ごとの削除と全体の削除。削除のあとの画面の状態。失敗時に「完了」としないこと。
- **誤り報告**: 理由の選択、自由記述の上限、注意書き、送信キューへの保存、オフラインの表示、二重送信の防止。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| FT-08-01 | 学習設定の編集(FR-CARD-05) | 1 日の新規カード数、復習の上限、誤答の自動カード化を変える | 選んでいる試験の設定として保存する | 自動: `SettingsViewModelTests.editsExamPreference` | 現在 | 未実施 |
| FT-08-02 | 設定の保存の失敗(E-05) | 保存を失敗させる | 画面の値を変更前に戻し、「保存に失敗しました」を表示する | 自動: `SettingsViewModelTests.preferenceSaveFailureRestoresValue` | 現在 | 未実施 |
| FT-08-03 | シャッフルの設定(FR-EXAM-12) | シャッフルを切り替える | 全体の設定として保存し、試験の選択などほかの項目を上書きしない | 自動: `SettingsViewModelTests.shuffleSetting` | 現在 | 未実施 |
| FT-08-04 | 学習データの書き出し(FR-ACCT-03) | 「書き出す」を選ぶ | 全試験の学習データを JSON ファイルに書き、共有の画面へ渡す。ファイル名に日付が入る | 自動: `SettingsViewModelTests.exportData` | 現在 | 未実施 |
| FT-08-05 | 書き出しの失敗 | 書き出しを失敗させる | 失敗を表示し、共有の画面を出さない | 自動: `SettingsViewModelTests.exportFailureShowsError` | 現在 | 未実施 |
| FT-08-06 | 削除の確認(FR-ACCT-03) | 試験ごとの削除、全体の削除を選ぶ。確認でキャンセルする | 確認を挟むまで削除しない。キャンセルしたら何も消えない | 自動: `SettingsViewModelTests.deleteRequiresConfirmation` | 現在 | 未実施 |
| FT-08-07 | 削除の失敗 | 削除を失敗させる | 失敗を表示し、「削除しました」としない | 自動: `SettingsViewModelTests.deleteFailureDoesNotFinish` | 現在 | 未実施 |
| FT-08-08 | 試験ごとの削除のあと | 選んでいる試験のデータを削除する | 試験の選択は保ち、各タブの画面を作り直して、古い表示を残さない | 自動: `ActiveExamContextTests.deletingExamDataKeepsExamAndRebuildsScreens` | 現在 | 未実施 |
| FT-08-09 | 全体の削除のあと | 全データを削除する | 起動時と同じ手順で試験を選び直す(1 つなら自動で選び、複数なら選択画面) | 自動: `ActiveExamContextTests.deletingAllDataReselectsLikeLaunch` | 現在 | 未実施 |
| FT-08-10 | このアプリについて | 「このアプリについて」を開く | アプリの版、商標の表示、ライセンスの表示を出す | 自動: `SettingsViewModelTests.aboutShowsNotices` | 現在 | 未実施 |
| FT-08-11 | 報告の理由(FR-CONT-03) | 報告シートを開く | 6 つの理由から 1 つを選べる。選ぶまで送信できない | 自動: `ReportSheetViewModelTests.reasonsAreSelectable` | 現在 | 未実施 |
| FT-08-12 | 自由記述の上限 | 500 文字ちょうど、501 文字を入力する | 500 文字までは送信でき、501 文字では送信できない。残りの文字数を表示する | 自動: `ReportSheetViewModelTests.commentLimit` | 現在 | 未実施 |
| FT-08-13 | 個人情報の注意書き | 報告シートを開く | 「氏名・メールアドレスなどの個人情報は書かないでください」を表示する | 自動: `ReportSheetViewModelTests.privacyNoticeShown` | 現在 | 未実施 |
| FT-08-14 | 報告の内容 | 解説の画面から報告を送る | 試験 ID・問題 ID・改訂番号・パックの版・理由・自由記述・アプリの版・ロケールを、送信キューに保存する | 自動: `ReportSheetViewModelTests.enqueueContainsContext` | 現在 | 未実施 |
| FT-08-15 | オフラインの表示(E-08) | 送信の手段がない状態で報告を送る | 「オフラインのため、あとで送信します」を表示し、キューに残す | 自動: `ReportSheetViewModelTests.offlineMessage` | 現在 | 未実施 |
| FT-08-16 | 送信済みの報告 | 送信に成功する | キューから消える | 自動: `ReportSheetViewModelTests.sentReportLeavesQueue` | 現在 | 未実施 |
| FT-08-17 | 報告の保存の失敗と二重送信 | キューへの保存を失敗させる。送信を続けて 2 回押す | 失敗を表示し、再試行できる。報告は 1 件だけ保存する | 自動: `ReportSheetViewModelTests.saveFailureCanRetry`、`rejectsDuplicateSubmit` | 現在 | 未実施 |
| FT-08-18 | 進行中の模試があるときの削除 | 模試の進行中に、その試験のデータを削除する | 受験の記録と版の固定を消し、再開のバナーを出さない | 自動(追加) | 現在 | 未実施 |
| FT-08-19 | 書き出しのファイルの後始末 | 書き出して共有を終える。もう一度書き出す | 古いファイルが残らない([SEC-04-06](../SEC/SEC-04-DataAtRest.md) の決定に従う) | 自動(追加) | リリース前 | 未実施 |

## 3. 既存のテストで覆われていない点

- **FT-08-18**: 模試の進行中にデータを削除した場合の、版の固定の扱いを確認するテストを、テスト名からは特定できなかった。
- **FT-08-19**: 書き出したファイルを削除する処理が見当たらない(SEC-04 の未決事項 3)。
- 設定画面の値の範囲(上限の最小・最大)を画面で制限しているかは、ViewModel のテスト名からは特定できなかった。負の値を 0 として扱うことは FT-05-05 で確認している。
- 学習計画(FR-PLAN-01)、通知(FR-PLAN-03)、iCloud 同期の表示(E-10)は P6 の対象で、まだ項目にしていない。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 1 日の新規カード数と復習の上限の、設定できる範囲 | P4-S18 |
| 2 | 書き出したファイルを削除するタイミング(SEC-04 の未決事項 3 と同じ) | リリース前 |
