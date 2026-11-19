# FT-03 結果・解説・カード追加

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 機能テスト |
| 対応要件 | FR-EXAM-08、FR-EXAM-09、FR-PRAC-05、FR-PRAC-06、FR-PRAC-08、FR-CARD-04、AC-03、SCR-014、SCR-015、BDD 6.3、[DDD-P4](../DDD/DDD-P4-AppMVP.md) P4-S08・S09 |
| 対象 | `ExamResultViewModel`、`ExplanationViewModel`、`ExamReviewViewModel`(提出と誤答のカード化)、`Scoring` |
| 既存のテスト | [ExamResultViewModelTests](../../packages/Presentation/Tests/AppCoreTests/ExamResultViewModelTests.swift)、[ExplanationViewModelTests](../../packages/Presentation/Tests/AppCoreTests/ExplanationViewModelTests.swift)、[ExamReviewViewModelTests](../../packages/Presentation/Tests/AppCoreTests/ExamReviewViewModelTests.swift)、[ScoringTests](../../packages/Domain/Tests/ExamEngineTests/ScoringTests.swift) |

---

## 1. テストの観点

- **集計の正しさ**: 総合・ドメイン別・ケース別の正答数と分母。未解答の扱い。ケースのない試験。
- **受験時の内容の再現**: 結果と解説を、受験したときの版と出題順で表示すること。その版がない、保存した順が壊れている場合に、別の内容で代用しないこと。
- **解説の表示範囲**: 全選択肢の解説、誤答タグ、自分の選択。受験に含まれない問題の解説を見せないこと。
- **カード化**: 手動の追加と、提出時の自動の追加。重ねて追加しないこと。設定と機能の有無。失敗からの再試行。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| FT-03-01 | 結果の表示(FR-EXAM-08) | 提出済みの受験の結果を開く | 総合の正答数と正答率、ドメイン別、ケース別、所要時間を、試験定義の順で表示する | 自動: `ExamResultViewModelTests.showsTotalsAndDefinitionBreakdownsInSavedOrder` | 現在 | 未実施 |
| FT-03-02 | ドメイン別正答率の一致(AC-03) | 解答の記録から、ドメインごとの正答数を別の方法で数える | 結果画面の値と一致する。ドメイン別の合計が総合と一致する | 自動: `ExamResultViewModelTests.domainBreakdownsMatchIndependentAnswerCounts`、`ScoringTests.domainTotalsSumToTotal`、`byDomainHasEveryDomain` | 現在 | 未実施 |
| FT-03-03 | 未解答の扱い | 未解答を含む受験を提出する | 未解答を不正解として数え、分母に含める | 自動: `ExamResultViewModelTests.caseBreakdownAndUnansweredDenominator`、`ScoringTests.unansweredIsIncorrect` | 現在 | 未実施 |
| FT-03-04 | ケースのない試験 | ケース機能が無効な試験(`test-beta`)の結果を開く | ドメインは 4 つで、ケース別の区分を表示しない | 自動: `ExamResultViewModelTests.betaShowsFourDomainsAndNoCases`、`ScoringTests.byCaseStudyEmptyWhenDisabled` | 現在 | 未実施 |
| FT-03-05 | 所要時間の上限 | 期限を過ぎてから提出された受験 | 所要時間は制限時間を超えない | 自動: `ExamResultViewModelTests.overdueSubmissionCapsElapsedTimeAtExamDuration` | 現在 | 未実施 |
| FT-03-06 | 受験時の版がない | 固定した版を消してから、結果を開く | エラーを表示し、現在の版で代用しない。再試行できる | 自動: `ExamResultViewModelTests.missingVersionShowsErrorAndCanRetryWithoutFallback` | 現在 | 未実施 |
| FT-03-07 | 保存した内容の不整合 | 出題順が壊れている、得点が解答と合わない、未提出の受験を指定する | 結果を一部だけ表示することなく、エラーにする | 自動: `ExamResultViewModelTests.invalidSavedOrderDoesNotShowPartialResult`、`mismatchedScoreOrUnsubmittedAttemptIsRejected` | 現在 | 未実施 |
| FT-03-08 | 検証済みの内容の共有 | 結果と解説を続けて開く。検証に失敗したあとで開き直す | 検証済みの内容を使い回す。失敗した結果は保持しない | 自動: `ExamResultViewModelTests.sharedCacheReusesValidatedContentAcrossRoutes`、`cacheDoesNotKeepFailedValidation` | 現在 | 未実施 |
| FT-03-09 | 解説の表示(FR-EXAM-09、FR-PRAC-05、FR-PRAC-06) | 提出済みの受験から、問題の解説を開く | 全選択肢の解説、誤答タグ、自分の選択、正解を、受験時の選択肢の順で表示する | 自動: `ExplanationViewModelTests.allRationalesTagsSelectionAndOriginalOrderAreShown` | 現在 | 未実施 |
| FT-03-10 | 受験に含まれない問題 | その受験に含まれない問題 ID を指定して解説を開く | 解説を表示しない | 自動: `ExplanationViewModelTests.questionOutsideAttemptCannotRevealExplanation` | 現在 | 未実施 |
| FT-03-11 | カードへの追加(FR-CARD-04) | 解説から「カードに追加」を 2 回押す。保存を 1 回失敗させる | カードは 1 枚だけできる。失敗したら再試行できる | 自動: `ExplanationViewModelTests.addToCardsIsIdempotentAndCanRetryFailure` | 現在 | 未実施 |
| FT-03-12 | 誤答の自動カード化(FR-CARD-04) | 自動カード化を ON・OFF にして、誤答と未解答を含む受験を提出する | ON では、解答して間違えた問題だけをカードにする。OFF、またはカード機能が無効な試験では作らない | 自動: `ExamReviewViewModelTests.confirmSubmitScoresAndCreatesOnlyAnsweredMistakeCards`、`disabledAutoCards`、`disabledFlashcardsDoNotDependOnCardSettings` | 現在 | 未実施 |
| FT-03-13 | カード化の途中の失敗 | 自動カード化の途中で、保存や設定の読み込みを失敗させる | 提出をやり直さず、カードを重ねて作らずに再試行できる。設定を読めないときは、提出を確定しない | 自動: `ExamReviewViewModelTests.partialCardFailureRetriesWithoutRefinalizingOrDuplicatingCards`、`settingsFailureDoesNotFinalizeOrSilentlySkipCards` | 現在 | 未実施 |
| FT-03-14 | 出典の表示(FR-PRAC-08) | 出典のある問題の解説を開く | 出典の題名とリンクを表示する。ライセンスが CC BY 4.0・Apache 2.0 のときは表示し、リンクだけのときは出さない | 自動: `DesignSystemTests.referencesShowAttributionLicenseButLinkOnlyHasNoLabel` | 現在 | 未実施 |
| FT-03-15 | 関連する画面への導線 | 解説から、関連ドキュメントと誤り報告を開く。カード・ドキュメントが無効な試験でも開く | 関連ドキュメントへ進める。報告には問題と版の情報が渡る。無効な機能の導線は出さない | 自動: `ExplanationViewModelTests.reportContextAndRelatedDocRoute`、`disabledCardsAndAbsentDocsOfferNoActions`、`disabledDocsAreHiddenEvenWhenIndexHasAnEntry` | 現在 | 未実施 |
| FT-03-16 | 正誤の表し方 | 正解・不正解・未解答の表示を比べる | 色だけでなく、アイコンと言葉でも区別できる。誤答タグは種類ごとに題名とアイコンが違う | 自動: `DesignSystemTests.resultsHaveDifferentIconsAndWords`、`allMistakeTagsHaveDistinctLocalizedTitlesAndIcons` | 現在 | 未実施 |
| FT-03-17 | 提出後の経路 | 提出して結果へ進んだあと、戻る操作をする | 解答画面へ戻らない | 自動: `AppRouterTests.submitReplacesStackAndSwitchResetsAllTabs` | 現在 | 未実施 |

## 3. 既存のテストで覆われていない点

- この観点の項目は、すべて既存の自動テストに対応づけられた。
- 受験の履歴の一覧とスコアの推移(FR-EXAM-13、SCR-016)は P6-S04 の対象で、まだ項目にしていない。
- 結果と解説を、実際の保存先とパックで復元する確認は、結合テスト(IT-04-11)で扱う。

## 4. 未決事項

なし。
