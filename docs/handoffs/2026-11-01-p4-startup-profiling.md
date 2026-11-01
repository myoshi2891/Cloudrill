# P4 起動計測と残課題（2026-11-01）

## 今回の対応

S17 の次の作業である NFR-01（コールドスタートから操作可能になるまで2秒）の調査を開始した。

- `AppComposition` に OSLog の区間計測を追加。subsystem `Cloudrill`、category は `OSLog.Category.pointsOfInterest`（Instruments の Points of Interest に表示される）。Release でも有効で、ユーザーデータは記録しない。
- 操作可能状態の終点として、イベント `StartupReady` を1プロセスにつき1回だけ記録する。画面が操作可能な状態になった後、その状態を反映したフレームを待ってから記録する（`StartupMetrics.markReadyAfterNextFrame()`。iOS では `CADisplayLink` の次の更新）。終点は起動の経路で次の3通り。
  - 初回起動で試験一覧を表示する（同梱試験が複数）: 試験選択の一覧が読み込み中でなく、選択できる試験がある状態。
  - 初回起動で試験が1つだけ: `InitialExamSelection.resolve` がその試験を自動選択し、試験選択を表示せずにホームへ進む。終点はホームの読み込み完了（`HomeViewModel.state.isLoaded` が true）。
  - 試験選択済みの再起動: 同じくホームの読み込み完了。
- `StartupPreparation`: `AppRootView.task` 開始から依存の設定完了または起動失敗まで。プロセスの起動・初回描画を含まないため、この区間だけで NFR-01 を判定しない。
- 内訳は `StudyStore`（学習ストア生成）、`ReportStore`（報告キュー生成）、`ContentBootstrap`（パック読み込み・整合確認）、`RestoreSelection`（`ActiveExamContext.restore()` による設定の読み込みと試験選択の復元のみ）。中断中の受験の検出はその後の `HomeViewModel.load()` で行い、この区間には含まれない（その時間は `StartupReady` までに含まれる）。ストアとパックの区間は失敗しても終了する。
- 既存の `testLaunchPerformance` に加えて、`testLaunchToExamPickerPerformance` を追加。全同梱試験・空のインメモリストアで起動し、試験選択ボタンが存在して操作可能になるまでを5回測る。終了処理は計測の外に置く。XCTest の起動・問い合わせ時間も含むので実機の合否判定には使わない。

## 実機での計測手順

1. 本番 App Group、署名と entitlement、`CloudrillAppGroup` の Info.plist 設定、本番署名済み同梱パックを準備する。現在の Release は開発用パックを拒否するため、現状のままでは正常起動を計測できない。
2. 接続した実機を選び、Release を Profile する。UI テスト用の引数は使わない。Instruments の App Launch と Points of Interest を使い、プロセス起動から `StartupReady` イベントまでを NFR-01 の値として記録し、上記の区間で内訳を確認する。`StartupPreparation` や `testLaunchToExamPickerPerformance` の値を NFR-01 の代わりにしない。
3. 初回起動と、試験選択後にプロセスを終了した再起動（ストア再利用・ホーム復元）を分けて記録する。初回起動は同梱試験の数で終点が変わるため、試験一覧を表示する場合（複数試験）と、1試験の自動選択でホームへ進む場合を区別して記録する。各条件で複数回測り、端末・OS・コミット・パック版・保存状態・各回の値を記録する。
4. NFR-01 の2秒判定と内訳を PR に添付し、時間を要している区間が分かってから改善する。Simulator、Debug、UI テストの数値と直接比較しない。

2026-11-01 の `xcrun devicectl list devices` では登録済みの iPhone 16 Plus が `unavailable`。実機計測は未実施で、NFR-01 を完了扱いにしていない。

## P4 の完了条件の確認と次の作業

- S17: 前回はUIテスト19件が成功。今回の変更後の対象検証は下記に記録する。
- Presentation の Data import: `git grep -n -e 'import ContentKit' -e 'import Persistence' -- packages/Presentation` は0件。
- **P4-S18 は未着手**。SCR-001・012・014・015・031・042 のライト／ダーク／最大文字サイズのスナップショット、Accessibility Inspector、実機 VoiceOver、視差効果を減らす設定の確認が必要。結果は仕様どおり PR に添付する。
- test-beta の全画面の手動確認、リモート CI、共通完了条件の最終確認も残る。P4 全体は未完了。
- P5 の外部配信作業へ進む前に上記を確認する。本番識別子・パック等は未決定のまま作成しない。
- コミットは利用者が行う。

## 今回の検証

- `swift test --package-path packages/AppComposition`: 13件成功。
- `swift build --package-path packages/AppComposition -c release`: 成功。
- 既存の `LaunchPerformanceTests.testLaunchPerformance`: 成功。Simulator・Debug で平均14.562秒（10.656〜21.968秒）。今回の実行はビルドの並行実行を含む環境で変動が大きく、前回比や NFR-01 の判定には使わない。
- 新しい `testLaunchToExamPickerPerformance` は初回、`stopMeasuring` と自動終了設定の競合で失敗。SDK の定義を確認し、`invocationOptions = [.manuallyStop]` を明示し、対象テストを再実行して成功。平均10.214秒（8.227〜12.806秒）。UI 自動化の時間を含む参考値。
- `git diff --check`: 成功。
- レビュー対応（終点をフレーム描画後に変更、UI 計測は `isHittable` を述語で最大20秒待つ）の後: `swift test --package-path packages/AppComposition` 13件成功、`xcodebuild build-for-testing`（iOS Simulator）成功、`testLaunchToExamPickerPerformance` 単体で成功（平均17.588秒、12.391〜21.069秒。参考値）。UI テスト全件は未再実行。

テスト成果物: `/tmp/cloudrill-build/Logs/Test/Test-ExamPrepApp-2026.11.01_10-05-02-+0900.xcresult`（追加テストの再実行）。ログは `/tmp/cloudrill-startup-composition.log`、`/tmp/cloudrill-startup-release.log`、`/tmp/cloudrill-startup-ui.log`、`/tmp/cloudrill-startup-ui-retry.log`。UI 全件の再実行・実機計測・リモート CI は今回未実施。
