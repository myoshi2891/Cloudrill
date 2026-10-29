# P4-S08 見直し・提出 引き継ぎ（2026-10-30）

## 利用者の指示と停止位置

- 利用者がコミットを行う。エージェントはコミット・push・PR作成を行っていない。
- ブランチは `dev` のまま。開始時の HEAD は `7912391`（S06のドキュメント更新）。
- S07の未コミット変更に続けてS08を実装したため、現在の作業ツリーには **S07とS08の両方** が含まれる。新規ファイルは untracked のため、コミット時に取り漏らさないこと。
- 利用者の追加指示により、S08の検証完了を区切りに本書を残して停止する。**S09は未着手**（S07の最小の提出確認画面だけがある）。

## 実装内容

- S07: 解答・即時保存・フラグ・問題移動・固定版コンテンツ・ケースシート・タイマー・中断復元・期限超過提出。
- S08: `ExamReviewViewModel` / `ExamReviewView`。全問題の解答状態とフラグ、未解答・見直し件数、問題へのジャンプ、提出確認とキャンセルを実装。
- `ExamSessionStore` は受験IDごとに解答・見直し経路で同じ `ExamSessionViewModel` を共有する。問題本文を往復のたびに読み直さない。
- `ExamSessionController` の状態機械に `openReview`・`closeReview`・手動 `submit` を接続。解答と見直し間の遷移は中断せず、タブ移動・バックグラウンドでは中断する。見直し中の復帰は `.reviewing` に戻す。
- `ExamSubmission` が手動・期限超過の採点、受験確定、誤答カード追加、パック固定解除を共有する。提出確認中に期限を過ぎた場合は `.timeExpired` を優先する。
- カード追加は試験の `features.flashcards` と `ExamPreference.autoCardFromMistakes` が両方有効なときだけ行う。実際に選択して誤答した問題を対象にし、未解答は含めない。対象と採点結果は最初の提出時に固定する。
- 再試行では確定済みの受験・追加済みのカードを重複処理しない。`SwiftDataCardStateRepository.addCardFromQuestion` 自体も同じカードIDの追加に対して冪等。再試行の進捗は `ExamSubmission` のインスタンス内で保持し、永続的な提出後処理キューは今回追加していない。
- Presentation → Data の依存は追加していない。コンテンツSchema・SwiftDataスキーマ・本番パック・Xcodeプロジェクト設定は今回変更していない。

## 検証

- S08の先行テストで未実装APIによるコンパイル失敗を確認してから実装した。
- Presentation: 全66テスト成功（DesignSystem 6、その他60。S08の11テストを含む）。見直し件数、確認・取消、問題ジャンプ、正答数、カードON/OFF・機能無効、期限超過、復帰、保存失敗、カード追加途中の失敗と再試行を検証。
- AppComposition: 全10テスト成功。実ストアで手動提出・カード保存・パック固定解除を行い、再起動後の結果とカードの存在を確認。S07の復元・自動提出も成功。
- AppCompositionのReleaseビルド成功。
- Simulator UIテスト: 最終結果を追記する。
- S07で検証済みのDataテストは既存120件と固定版解決2件。S08ではDataソースを変更していないため再実行していない。
- リモートCI、ダークモード・最大文字サイズ・実機VoiceOverの確認は未実施。

再実行例:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/Presentation
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/AppComposition
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path packages/AppComposition -c release
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ExamPrepApp.xcodeproj -scheme ExamPrepApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=3C8F027B-C4E0-479F-A6B3-7F4654DB6031' \
  -derivedDataPath /tmp/cloudrill-s07-build CODE_SIGNING_ALLOWED=NO test
```

Simulator IDはこの端末のiPhone 18 Pro / iOS 27.0。別環境では置き換える。キャッシュやSimulatorへのアクセスでサンドボックス昇格が必要だった。

## 次の作業

1. この作業ツリーを利用者側でレビュー・コミットする。
2. `Documentation.docc/DDD/DDD-P4-AppMVP.md` の **P4-S09 結果と解説** に着手する。
3. `ExamSubmissionReceiptView` を詳細結果画面へ置き換え、ドメイン・ケース別集計、全選択肢の解説、誤答タグ、出典・ライセンス、カード追加、報告、関連ドキュメントへの経路を接続する。
4. 詳細結果は受験の `packVersion` と保存済みの `QuestionOrder`・解答から再構成する。最新版の本文へ置き換えない。
5. 本番App Group・識別子・パックは未確定のまま。Debugの開発用保存先で作業を続ける。

主な参照先:

- `Documentation.docc/DDD/DDD-P4-AppMVP.md` 第2節の実装履歴、S08・S09
- `packages/Presentation/Sources/ExamFeature/ExamSessionController.swift`
- `packages/Presentation/Sources/ExamFeature/ExamSubmission.swift`
- `packages/Presentation/Sources/ExamFeature/ExamReviewViewModel.swift`
- `packages/Presentation/Sources/ExamFeature/ExamSessionStore.swift`
- `packages/Presentation/Tests/AppCoreTests/ExamReviewViewModelTests.swift`
- `packages/AppComposition/Tests/AppCompositionTests/AppEnvironmentTests.swift`
- `ExamPrepAppUITests/StartupTests.swift`
