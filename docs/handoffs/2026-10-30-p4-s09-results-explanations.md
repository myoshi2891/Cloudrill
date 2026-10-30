# P4-S09 結果・解説 引き継ぎ（2026-10-30）

## 利用者の指示と停止位置

- 「仕様書を確認して次のアクションを実装」の依頼を受け、README・RDD・BDD・DDD-P4・S08引き継ぎを確認し、P4-S09を実装した。
- 途中で「区切りが良いところで、引き継ぎして」と指示されたため、S09の検証と引き継ぎを終えて停止する。**S10は未着手**。
- ブランチは `dev`、開始時HEADは `2ddd935`。開始時に追跡ファイルの差分はなかった。今回の変更は未コミットで、コミットは利用者が行う。
- S08メモにあるPR #12のレビュー・リモートCIは今回確認していない。

## 実装したこと

- `ExamSubmissionReceiptView` を `ExamResultView` に置換。総合正答数・四捨五入した正答率・所要分数・ドメイン別・ケース別集計と全問の解説リンクを表示する。
- `SubmittedExamContent` で提出済み履歴を読み、受験時の版を `ExamContentResolving` で解決する。保存済み問題順と選択肢順を検証・復元し、現在の本文へ置き換えない。総合結果は保存済み解答から再採点し、保存済み総合正答数と照合する。
- 未解答は分母に含める。出題なしのドメインは「出題なし」。ケース機能無効ならケース欄を表示しない。時間切れ提出は再起動が遅れても保存済み試験時間を超える所要時間にしない。
- `ExplanationViewModel` / `ExplanationView` に全選択肢の解説、選択状態、誤答タグ、出典、日英切り替えを追加。英訳の欠落は `LocalizedText` の日本語フォールバックを使う。
- 共通の `ReferenceLink` は `CC-BY-4.0` を「CC BY 4.0」、Apacheを「Apache 2.0」と表示。`link-only` のライセンス文字列は表示しない。
- カード追加は既存の `CardStateRepository` を使う。`Q:<questionID>` が存在すれば最初から「追加済み」、無効な試験ではボタンなし。保存失敗の再試行・二重操作防止も実装した。
- docs機能が有効かつ該当サブ項目の資料があるときだけ、関連資料のRouteを開く。報告シートには試験ID・問題ID・revision・受験時のパック版を渡す。
- AppRootViewに結果と解説の経路を接続。Presentation → Data の依存は追加していない。コンテンツ・Schema・永続化層・Xcodeプロジェクト設定は変更していない。

## 後続ステップとの境界

- 関連ドキュメントは `.doc(subObjective:)` への遷移まで。本文画面は **S12** の実装待ちで「準備中」になる。
- 誤り報告はコンテキスト付きシートまで。「誤り報告の受付は準備中です」と表示する。入力・送信キューは **S15**、実際の送信は **P5**。送信やキュー保存はまだ行わない。
- 古いパックが既存の保持方針により削除された場合、過去の解説は読み込みエラーになる。最新版への代用も、全履歴のための無期限パック保持も追加していない。
- S10で練習の解説と共有する際は、現在の提出済み受験を読み込むViewModelに、練習の問題・選択を受け取る入口を追加する。表示Viewと共通部品は再利用できる。
- 本番App Group・識別子・本番コンテンツは引き続き未確定。Debugの開発用ストアで継続する。

## 検証

- 先行テストで `ExamResultViewModel` / `ExplanationViewModel` 未実装によるコンパイル失敗を確認した。
- Presentation **81テスト成功**（DesignSystem 7、AppCoreTests 74）。55問中40問の73%・98分、独立したドメイン集計期待値、ケース集計、未解答、出題なし、固定版、順序破損、成績不一致、提出前の解説拒否、カード再試行・二重追加防止、報告コンテキスト、資料の有無・機能無効を検証した。
- AppComposition **10テスト成功**。実ストアの提出→再起動→結果・解説の復元と、自動カード追加済み状態を確認した。
- AppComposition Releaseビルド成功。
- Simulator UIテストは関連3件が成功。結果→全選択肢の解説→日英切り替え→手動カード追加→報告シート→関連資料へのタブ遷移と、強制終了復元・期限超過提出の2件は `/tmp/cloudrill-s09-ui-final.xcresult`。既存の見直し・取消・手動提出1件は `/tmp/cloudrill-s09-ui.xcresult` 内で成功している。全9件のUIテスト再実行は行っていない。
- 最初の結果UIテストでは、資料のない問題1に関連資料のボタンを期待して失敗した。fixtureの資料は問題13（NET.1）にあるため、問題1ではボタンがないこと、問題13では遷移できることを検証するよう修正し、再実行で成功した。生成済みfixtureは変更していない。
- 通常文字サイズ・ライト表示の結果画面、解説の理由・誤答タグ・参考リンク・追加済み表示はスクリーンショットで目視確認した。ダーク・最大文字サイズ・実機VoiceOverの確認はS18。リモートCIは未確認。

## 再実行

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/Presentation
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/AppComposition
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path packages/AppComposition -c release
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ExamPrepApp.xcodeproj -scheme ExamPrepApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=3C8F027B-C4E0-479F-A6B3-7F4654DB6031' \
  -derivedDataPath /tmp/cloudrill-s09-build CODE_SIGNING_ALLOWED=NO \
  -only-testing:ExamPrepAppUITests/StartupTests/testResultExplanationAndCardActionsOffline \
  -only-testing:ExamPrepAppUITests/StartupTests/testAnswerRestoresAfterTerminationAndExpiresOnRelaunch \
  -only-testing:ExamPrepAppUITests/StartupTests/testReviewJumpCancelAndManualSubmission test
```

この端末はiPhone 18 Pro / iOS 27.0。Swiftキャッシュ・Simulator・xcresulttoolのキャッシュへのアクセスにサンドボックス昇格が必要だった。

ローカルログは `/tmp/cloudrill-s09-presentation.log`、`/tmp/cloudrill-s09-composition.log`、`/tmp/cloudrill-s09-release.log`、`/tmp/cloudrill-s09-ui-final.log`。目視確認した画像は `/tmp/cloudrill-s09-attachments/` にある（一時ファイルなので別環境への引き継ぎには含まれない）。

## 次の作業

1. 未コミット差分を確認し、利用者のタイミングでコミットする。
2. `Documentation.docc/DDD/DDD-P4-AppMVP.md` の **P4-S10 練習モード** から再開する。
3. S12で関連ドキュメント本文、S15で報告フォーム・キューを接続する。

主なファイル:

- `packages/Presentation/Sources/ExamFeature/ExamResultViewModel.swift` / `ExamResultView.swift`
- `packages/Presentation/Sources/ExamFeature/ExplanationViewModel.swift` / `ExplanationView.swift`
- `packages/Presentation/Sources/ExamFeature/SubmittedExamContent.swift`
- `packages/Presentation/Tests/AppCoreTests/ExamResultViewModelTests.swift` / `ExplanationViewModelTests.swift`
- `packages/AppComposition/Tests/AppCompositionTests/AppEnvironmentTests.swift`
- `ExamPrepAppUITests/StartupTests.swift`
