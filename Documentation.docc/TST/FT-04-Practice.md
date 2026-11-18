# FT-04 練習モード

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 機能テスト |
| 対応要件 | FR-PRAC-01〜05、FR-CASE-03、SCR-020〜022、BDD 6.7、[DDD-P4](../DDD/DDD-P4-AppMVP.md) P4-S10 |
| 対象 | `PracticeViewModel`、`QuestionSelector` |
| 既存のテスト | [PracticeViewModelTests](../../packages/Presentation/Tests/AppCoreTests/PracticeViewModelTests.swift)、[QuestionSelectorTests](../../packages/Domain/Tests/QuestionSelectorTests/QuestionSelectorTests.swift) |

---

## 1. テストの観点

- **条件の組み合わせ**: ドメイン、サブ項目、ケース、難易度、状態(間違えた・未解答・フラグ付き)、出題数。該当が 0 問、候補が出題数より少ない場合。
- **出題の選び方**: 重複しないこと、直近 24 時間に出した問題を避けること、弱点を優先すること。境界(ちょうど 24 時間)。
- **即時の解説**: 解答を保存できてから正誤と解説を出すこと。保存の失敗と再試行で、解答を重ねて記録しないこと。
- **結果**: 解答した全問と、ドメイン別の集計。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| FT-04-01 | 条件設定の選択肢 | 形の違う 2 つの試験で、条件設定を開く | ドメイン・サブ項目・ケース・難易度の選択肢が、試験定義のとおりに出る。ケースのない試験ではケースを出さない | 自動: `PracticeViewModelTests.optionsAndPresetsFollowDefinition` | 現在 | 未実施 |
| FT-04-02 | 絞り込み(FR-PRAC-01) | ドメイン、サブ項目、ケース、難易度をそれぞれ、および組み合わせて指定する | 条件に合う問題だけを出す | 自動: `QuestionSelectorTests.filtersByDomain`、`filtersBySubObjectiveAndCase`、`filtersByDifficulty` | 現在 | 未実施 |
| FT-04-03 | 状態での絞り込み(FR-PRAC-03) | 「間違えた問題のみ」「未解答のみ」「フラグ付きのみ」を指定する | 直近の解答が不正解の問題、一度も解答していない問題、フラグを付けた問題だけを出す | 自動: `QuestionSelectorTests.wrongOnly`、`unansweredOnly`、`flaggedOnly`(直近の結果をまとめた `lastResult` を直接渡す。複数の解答のどれが直近かは見ない)。不正解のあとに正解した解答から `lastResult` が正解になることは `AnswerHistoryRepositoryTests.lastResultAndReadinessIncludeEveryMode`。保存した解答の履歴から「間違えた問題のみ」の絞り込みの結果までを通すことは自動(追加) | 現在 | 未実施 |
| FT-04-04 | 出題数(FR-PRAC-04) | 5・10・20 問・すべてを指定する。候補が指定より少ない | 指定した数を出す。候補が少なければ、ある分だけ出す | 自動: `QuestionSelectorTests.countLimits`、`countExceedsCandidates` | 現在 | 未実施 |
| FT-04-05 | 該当する問題がない | 条件に合う問題が 0 問。または、出題の記録の保存に失敗する | 練習を開始せず、その旨を表示する | 自動: `QuestionSelectorTests.emptyResult`、`PracticeViewModelTests.emptyAndFailedMarkServedDoNotStart` | 現在 | 未実施 |
| FT-04-06 | 重複と直近の除外 | 直近 24 時間に出題した問題を含む候補から選ぶ。候補が足りる場合と足りない場合。ちょうど 24 時間前 | 同じ問題を 2 回出さない。足りる限り直近の問題を除き、足りなければ古い順に補う。ちょうど 24 時間前は除外しない | 自動: `QuestionSelectorTests.noDuplicates`、`excludesRecentWhenEnough`、`fillsFromOldestRecent`、`servedExactlyAtBoundaryIsFresh` | 現在 | 未実施 |
| FT-04-07 | 弱点優先 | ドメインごとに正答率の差がある履歴で「おまかせ」を選ぶ。履歴のないドメインを含める | 正答率の低いドメインを多く出すが、高いドメインも出る。履歴のないドメインは最も弱いものとして扱う | 自動: `QuestionSelectorTests.weaknessFirstPrefersWeakDomain`、`weaknessFirstStillPicksStrongDomain`、`missingDomainScoreIsWeakest`、`weightIncludesBonuses`(出題の選び方を直接呼ぶ)。「おまかせ」の選択が `.weaknessFirst` になり、ドメイン別の正答率が `QuestionSelector` に渡ることは自動(追加) | 現在 | 未実施 |
| FT-04-08 | 選び方の再現性 | 同じ seed で、入力の並びを変えて選ぶ | 結果が同じになる | 自動: `QuestionSelectorTests.inputOrderDoesNotMatter` | 現在 | 未実施 |
| FT-04-09 | 条件と履歴の受け渡し | 条件を指定して練習を開始する | 条件と解答の履歴が出題の選択に渡り、出した問題が「出題済み」として記録される | 自動: `PracticeViewModelTests.filtersAndHistoryReachSelectorAndMarkServed` | 現在 | 未実施 |
| FT-04-10 | 即時の解説(FR-PRAC-02、FR-PRAC-05) | 解答を確定する。保存を 1 回失敗させてから再試行する | 保存できてから、正誤と全選択肢の解説を表示する。再試行しても解答を 1 件だけ記録する | 自動: `PracticeViewModelTests.feedbackOnlyAfterSuccessfulSaveAndRetryDoesNotDuplicate` | 現在 | 未実施 |
| FT-04-11 | 複数選択の解答 | 複数選択の問題で、指定数より少なく・ちょうど・解答後にもう一度選ぶ | 指定数ちょうどのときだけ確定できる。解答のあとは選択を変えられない | 自動: `PracticeViewModelTests.multipleSelectionRequiresExactCountAndLocksAfterAnswer` | 現在 | 未実施 |
| FT-04-12 | 保存中の操作 | 保存の途中で、確定や選択をもう一度行う | 2 回目の操作を無視する | 自動: `PracticeViewModelTests.duplicateSubmitAndSelectionAreIgnoredWhileSaving` | 現在 | 未実施 |
| FT-04-13 | フラグ | 練習中にフラグを付け、次の練習で「フラグ付きのみ」を選ぶ | フラグが保存され、次の練習の絞り込みに使われる | 自動: `PracticeViewModelTests.flagsPersistAndCanFilterLaterSessions` | 現在 | 未実施 |
| FT-04-14 | 練習の結果 | 10 問を解答して結果を開く | 解答した全問の正誤と、ドメイン別の集計を表示する。結果の画面に、解答した問題ごとの行(何問目か、正解・不正解の表示、問題文)が解答した数だけある | 自動: `PracticeViewModelTests.resultIncludesAllTenAnswersAndDomainBreakdown`(正答数・ドメイン別の集計・保存した解答の件数)。画面の行は自動(UI): `StartupTests.testPracticeFeedbackAndResultOffline`(`practice-answer-1`〜`practice-answer-10` があり、正誤の表示を含む) | 現在 | 未実施 |
| FT-04-15 | ケースで練習(FR-CASE-03) | ケースの詳細から「ケースで練習」を選ぶ | そのケースで絞り込んだ条件設定へ進む | 自動: `LearnFeatureTests.practiceForCase` | 現在 | 未実施 |
| FT-04-16 | 練習の途中での離脱 | 3 問を解答したところで、画面を閉じる | 解答済みの 3 問は履歴に残る。再び開いたときの扱い(続きから、または新しい練習)が仕様どおりである | 自動(追加) | 現在 | 未実施 |

## 3. 既存のテストで覆われていない点

- **FT-04-16**: 練習を途中でやめた場合の扱いを確認するテストを、テスト名からは特定できなかった。解答ごとに履歴へ保存することは FT-04-10 で確認している。
- 日英の切り替え(FR-PRAC-07)は P6-S01 の対象で、まだ項目にしていない。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 練習を途中でやめたあと、続きから再開できるようにするか(模試と違い、中断の状態を持たない設計に見える) | P4-S18 |
| 2 | 同じ問題に複数回解答した場合、「間違えた問題のみ」は直近の 1 回だけで判定する。この扱いを利用者に説明するか | リリース前 |
