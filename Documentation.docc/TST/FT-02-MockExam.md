# FT-02 模擬試験(開始・解答・タイマー・見直し・提出)

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 機能テスト |
| 対応要件 | FR-EXAM-01〜07、FR-EXAM-11、FR-EXAM-12、NFR-04、E-05、E-06、E-07、SCR-010〜013、SCR-091、BDD 6.1〜6.4、[DDD-P4](../DDD/DDD-P4-AppMVP.md) P4-S06〜S08 |
| 対象 | `ExamStartViewModel`、`ExamSessionViewModel`、`ExamReviewViewModel`、`ExamEngine`(状態遷移、タイマー、出題順) |
| 既存のテスト | [ExamStartViewModelTests](../../packages/Presentation/Tests/AppCoreTests/ExamStartViewModelTests.swift)、[ExamSessionViewModelTests](../../packages/Presentation/Tests/AppCoreTests/ExamSessionViewModelTests.swift)、[ExamReviewViewModelTests](../../packages/Presentation/Tests/AppCoreTests/ExamReviewViewModelTests.swift)、[ExamEngineTests](../../packages/Domain/Tests/ExamEngineTests/) |

---

## 1. テストの観点

- **状態の遷移**: 未開始 → 進行中 → 中断 → 進行中 → 提出済み(手動・時間切れ)・破棄。許されない遷移を拒否すること。
- **解答の操作**: 単一選択と複数選択、選び直し、解除、フラグ、前後の移動。解答中に正誤を見せないこと。
- **時間**: 残り時間の計算、警告、期限ちょうど、バックグラウンド中の経過、期限を過ぎてからの復帰。
- **保存の失敗**: 解答・スナップショット・確定・版の固定のそれぞれが失敗したときに、状態が壊れず、再試行できること。
- **版の固定**: 受験の途中でコンテンツが更新されても、開始時の版で出題を続けること。
- **重複した操作**: 保存の完了を待たない連続タップ。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| FT-02-01 | 模試の一覧(FR-EXAM-01) | 問題がそろった模試と、そろっていない模試を含むパック | そろった模試だけを、上限の数まで表示する | 自動: `ExamStartViewModelTests.listsCompleteExamSetsAndRespectsLimit` | 現在 | 未実施 |
| FT-02-02 | 開始確認の表示 | 模試を選ぶ | 問題数・制限時間・含まれるケースを、試験定義のとおりに表示する | 自動: `ExamStartViewModelTests.startShowsFormatAndCases` | 現在 | 未実施 |
| FT-02-03 | 模試の開始 | 開始を確定する | 受験の記録を作り、出題順を保存し、コンテンツの版を固定して、解答画面へ進む | 自動: `ExamStartViewModelTests.startCreatesAttemptAndPins` | 現在 | 未実施 |
| FT-02-04 | 進行中の模試がある | 中断中の模試がある状態で、試験トップを開く | 新しい模試を開始できず、再開と破棄を選べる。破棄すると固定を外す | 自動: `ExamStartViewModelTests.startBlockedResumeAndAbandon` | 現在 | 未実施 |
| FT-02-05 | 開始・破棄の失敗 | 版の固定、破棄の保存、固定の解除をそれぞれ失敗させる | 版の固定・破棄の保存の失敗では、画面を進めず、記録と固定を元のまま保ち、再試行できる。固定の解除の失敗では、受験の記録は削除済みで固定だけが残る。画面は進行中の受験として扱い、読み込み直したあとの再試行で固定を解除できる | 自動: `ExamStartViewModelTests.pinFailureDoesNotNavigateAndCanRetry`、`abandonFailureKeepsAttemptAndPin`、`unpinFailureCanRetryAfterReload` | 現在 | 未実施 |
| FT-02-06 | 開始の連続操作 | 設定の読み込み中に、開始をもう一度タップする | 2 回目を無視し、受験の記録を 1 つだけ作る | 自動: `ExamStartViewModelTests.duplicateStartWhileAwaitingSettingsIsIgnored` | 現在 | 未実施 |
| FT-02-07 | 問題の読み込みと出題順 | 解答画面を開く | 全問を 1 回で読み込み、保存した出題順と選択肢の順で表示する | 自動: `ExamSessionViewModelTests.loadsAllQuestionsOnceAndRestoresOrder` | 現在 | 未実施 |
| FT-02-08 | 解答の保存と正誤の非表示(FR-EXAM-03、NFR-04) | 選択肢を選ぶ | 選ぶたびに保存する。正誤・解説・正解数を画面に出さない | 自動: `ExamSessionViewModelTests.selectionPersistsAndDoesNotExposeCorrectness` | 現在 | 未実施 |
| FT-02-09 | 単一選択と複数選択(FR-EXAM-06) | 単一選択で選び直す。複数選択で指定数まで選び、超えて選ぶ、解除する | 単一選択は 1 つだけ選ばれる。複数選択は指定数を超えて選べず、解除できる | 自動: `ExamSessionViewModelTests.multipleLimitAndDeselection`、`ExamSessionAnswerTests.selectRecordsAnswer`、`selectNilClearsAnswer` | 現在 | 未実施 |
| FT-02-10 | フラグと移動(FR-EXAM-04) | フラグを付け外しし、前後へ移動する。最初と最後の問題で、さらに移動する | フラグと現在位置を保存する。範囲の外へは移動しない | 自動: `ExamSessionViewModelTests.flagMoveAndSnapshotRestoration`、`ExamSessionAnswerTests.toggleFlag`、`moveClampsIndex` | 現在 | 未実施 |
| FT-02-11 | 中断からの復元(FR-EXAM-07) | 解答・フラグ・現在位置を保存した状態から、ViewModel を作り直す | 解答・フラグ・現在位置・残り時間を復元する | 自動: `ExamSessionViewModelTests.flagMoveAndSnapshotRestoration`、`ExamSessionAnswerTests.restoreFromSnapshot`、`restoreClampsIndex` | 現在 | 未実施 |
| FT-02-12 | 残り時間と警告(FR-EXAM-02) | 時計を進めて、警告のしきい値をまたぐ | 残り時間は「期限 − 現在」で、負にならない。警告の通知は、しきい値ごとに 1 回だけ出す | 自動: `ExamTimerTests.remainingIsDeadlineMinusNow`、`remainingNeverNegative`、`crossedThreshold`、`ExamSessionViewModelTests.warningThresholdsOnlyRequestFeedbackOnce` | 現在 | 未実施 |
| FT-02-13 | 時間切れの自動提出(FR-EXAM-02) | 時計を期限ちょうど、および期限の後へ進める | 1 回だけ確定し、固定を保持枠へ移す。期限の後の選択は記録しない | 自動: `ExamTimerTests.expiredExactlyAtDeadline`、`ExamSessionViewModelTests.expiryFinalizesOnceAndUnpins`、`expiredSelectionIsNotRecorded` | 現在 | 未実施 |
| FT-02-14 | バックグラウンドと期限後の復帰(E-06) | バックグラウンドへ移り、時計を進めて復帰する(期限の前と後) | バックグラウンド中も時間が進む。期限の後に復帰したら提出し、「制限時間を過ぎたため提出しました」を表示する | 自動: `ExamSessionViewModelTests.backgroundContinuesTimeAndExpiredResumeSubmits`、`ExamTimerTests.resumeAfterExpiryAutoSubmits` | 現在 | 未実施 |
| FT-02-15 | ケース文の表示(FR-EXAM-11) | ケースに属する問題と、属さない問題を表示する | ケース文を開くボタンは、ケースに属する問題にだけ出る | 自動: `ExamSessionViewModelTests.caseSheetOnlyForCaseQuestions` | 現在 | 未実施 |
| FT-02-16 | 受験中の版の固定(E-07) | 受験の途中で、有効なコンテンツの版を新しくする。または、固定した版を消す | 開始時の版で出題を続ける。固定した版がなければエラーを表示し、現在の版で代用しない | 自動: `ExamSessionViewModelTests.usesPinnedVersionEvenWhenActiveContentChanged`、`missingPinnedVersionDoesNotOpenCurrentContent` | 現在 | 未実施 |
| FT-02-17 | 保存の失敗(E-05) | 解答の保存、スナップショットの保存、確定、固定の解除をそれぞれ失敗させる | 画面の選択を保ち、失敗を表示し、再試行できる。保存済みの解答を失わない | 自動: `ExamSessionViewModelTests.recordFailureKeepsSelectionAndCanRetry`、`snapshotFailureAfterRecordKeepsCommittedAnswer`、`finalizeAndUnpinFailuresAreRetryable` | 現在 | 未実施 |
| FT-02-18 | 保存中の操作 | 保存の途中で、同じ選択肢をもう一度タップする、またはバックグラウンドへ移る | 同じ選択を重ねて保存しない。バックグラウンドへの移行で保存を取りこぼさない | 自動: `ExamSessionViewModelTests.backgroundDuringSaveIsNotDroppedAndDuplicateSelectionIsIgnored` | 現在 | 未実施 |
| FT-02-19 | 見直し一覧(FR-EXAM-05) | 未解答とフラグ付きの問題がある状態で、見直しを開く | 未解答とフラグ付きの問題を一覧し、提出の確認に件数を出す | 自動: `ExamReviewViewModelTests.listsUnansweredAndFlaggedAndConfirmsCounts`、`ExamSessionAnswerTests.reviewSummary` | 現在 | 未実施 |
| FT-02-20 | 見直しからの移動 | 一覧から問題を選ぶ。戻る操作で一覧を閉じ、解答を変える | 問題を読み込み直さずに移動する。戻ったあとも解答を変更できる。移動に失敗したら一覧と位置を保つ | 自動: `ExamReviewViewModelTests.jumpsToQuestionWithoutReloadingContent`、`systemBackClosesReviewAndAllowsAnswerChanges`、`failedJumpKeepsReviewAndPosition` | 現在 | 未実施 |
| FT-02-21 | 見直し中の時間切れ | 一覧の表示中、および提出の確認中に、期限を過ぎる | 時間切れとして 1 回だけ提出する。手動の提出と重ならない | 自動: `ExamReviewViewModelTests.expiryWhileConfirmingUsesTimeoutAndSharedAutoCards`、`reviewBackgroundResumeAndExpiry` | 現在 | 未実施 |
| FT-02-22 | 選択肢のシャッフル(FR-EXAM-12) | シャッフルを ON・OFF にして模試を開始する。同じ seed で 2 回作る | OFF では元の順。ON では seed ごとに決まった順で、全選択肢が残る。進行中の模試の順は変わらない | 自動: `ExamOrderBuilderTests.noShuffleKeepsChoiceOrder`、`shuffleIsDeterministic`、`shuffleKeepsAllChoices`、`restoreValidatesChoices` | 現在 | 未実施 |
| FT-02-23 | 状態遷移の表(BDD 6.1) | 全状態 × 全操作の組み合わせ | 表のとおりに遷移し、許されない遷移は状態とタイマーを変えない | 自動: `ExamSessionTransitionTests.transitionTable`、`transitionTableHasAllCells`、`invalidTransitionKeepsTimer` | 現在 | 未実施 |

## 3. 既存のテストで覆われていない点

- この観点の項目は、すべて既存の自動テストに対応づけられた。
- 画面の表示そのもの(タイマーの見た目、警告の色、触覚)は ViewModel のテストでは確認できない。E2E-01・E2E-06 で確認する。
- iPad の Split View(FR-EXAM-10)は P6-S02 の対象で、まだ項目にしていない。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 端末の時刻を利用者が変えた場合の扱い(期限は絶対時刻で持つため、時刻を戻すと残り時間が増える) | リリース前 |
