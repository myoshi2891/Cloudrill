# FT-05 フラッシュカード

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 機能テスト |
| 対応要件 | FR-CARD-01、FR-CARD-02、FR-CARD-03、FR-CARD-05、AC-08、SCR-030〜032、BDD 6.5、[DDD-P4](../DDD/DDD-P4-AppMVP.md) P4-S11 |
| 対象 | `FlashcardFeature`(デッキ一覧、カード学習、学習完了)、`DailyQueueBuilder`、FSRS |
| 既存のテスト | [FlashcardViewModelTests](../../packages/Presentation/Tests/AppCoreTests/FlashcardViewModelTests.swift)、[DailyQueueBuilderTests](../../packages/Domain/Tests/FSRSTests/DailyQueueBuilderTests.swift)、[FSRSVectorTests](../../packages/Domain/Tests/FSRSTests/FSRSVectorTests.swift) |

---

## 1. テストの観点

- **デッキの構成**: ドメイン別・サブ項目別・誤答のデッキ。カードのないデッキ、カード機能が無効な試験。
- **その日の出題**: 復習と新規の順、1 日の上限、すでに学習した分の差し引き、期限の境界(その日の終わり)。
- **評価の操作**: 表 → 裏 → 4 段階の評価の順。各評価の次回までの間隔の表示。
- **スケジュールの正しさ**: リファレンス実装と同じ結果になること。
- **保存の失敗**: 位置を進めず、同じ評価で再試行できること。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| FT-05-01 | デッキの一覧(FR-CARD-01) | カードタブを開く | ドメイン別とサブ項目別のデッキを、枚数とともに表示する | 自動: `FlashcardViewModelTests.decksByDomainAndSubObjective` | 現在 | 未実施 |
| FT-05-02 | 誤答のデッキ | 誤答から作ったカードがある場合と、ない場合 | カードがあるときだけ、誤答のデッキを表示する | 自動: `FlashcardViewModelTests.noMistakeDeckWithoutQuestionCards` | 現在 | 未実施 |
| FT-05-03 | カード機能が無効な試験 | カード機能が無効な試験定義で、カードタブを開く | デッキを表示しない | 自動: `FlashcardViewModelTests.hiddenWhenFeatureDisabled` | 現在 | 未実施 |
| FT-05-04 | その日の出題の順 | 期限の来た復習カードと、新規のカードがあるデッキを開く | 復習を先に、期限の古い順で出す。新規のカードは決まった順で出す | 自動: `FlashcardViewModelTests.queueFromDailyBuilder`、`DailyQueueBuilderTests.reviewsBeforeNew`、`dueOrder`、`newCardOrderIsStable` | 現在 | 未実施 |
| FT-05-05 | 1 日の上限(FR-CARD-05) | 新規の上限と復習の上限を設定し、その日にすでに学習した分がある | 上限から、その日に学習した分を引いた数だけ出す。負の上限は 0 として扱う | 自動: `DailyQueueBuilderTests.reviewLimit`、`newLimitConsidersToday`、`reviewLimitConsidersToday`、`negativeLimitsAreZero` | 現在 | 未実施 |
| FT-05-06 | 期限の境界 | 期限が今日の終わりのカードと、明日のカード | 端末の時間帯で今日の終わりまでに期限が来るカードを出し、明日のカードは出さない | 自動: `DailyQueueBuilderTests.dueUntilEndOfLocalDay`、`notDueTomorrow` | 現在 | 未実施 |
| FT-05-07 | めくってから評価(FR-CARD-03) | カードを表のまま評価しようとする。めくってから評価する | 表のままでは評価できない。めくると 4 段階(Again・Hard・Good・Easy)を選べる | 自動: `FlashcardViewModelTests.flipThenRate` | 現在 | 未実施 |
| FT-05-08 | 次回までの間隔の表示 | カードをめくる | 4 つの評価のそれぞれに、次回までの間隔(分・時間・日などの区分)を表示する | 自動: `FlashcardViewModelTests.ratingButtonsShowIntervals`、`intervalBuckets` | 現在 | 未実施 |
| FT-05-09 | スケジュールの一致(FR-CARD-02、AC-08) | リファレンス実装で作ったテストベクタ(入力と期待値)を使う | 次回の出題日と内部の状態が、リファレンス実装と一致する | 自動: `FSRSVectorTests.allVectors`、`vectorsAreWellFormed` | 現在 | 未実施 |
| FT-05-10 | 問題から作ったカード | 誤答から作ったカードを表示する | 表に問題文、裏に正解の選択肢を表示する | 自動: `FlashcardViewModelTests.questionCardShowsStemAndCorrectChoices` | 現在 | 未実施 |
| FT-05-11 | 保存の失敗 | 評価の保存を 1 回失敗させる。保存の途中で、もう一度評価する | カードの位置を進めず、同じ評価で再試行できる。保存中の評価は受け付けない | 自動: `FlashcardViewModelTests.saveFailureKeepsPositionAndRetriesSameOutcome`、`rejectsRatingWhileSaving` | 現在 | 未実施 |
| FT-05-12 | 学習の完了 | その日の出題をすべて評価する | 学習した枚数と評価の内訳を表示する | 自動: `FlashcardViewModelTests.finishShowsSummary` | 現在 | 未実施 |
| FT-05-13 | 読み込みの失敗 | デッキの読み込みを失敗させる | 失敗を表示し、再試行できる | 自動: `FlashcardViewModelTests.loadFailureCanRetry` | 現在 | 未実施 |
| FT-05-14 | 出題するカードがない | 期限の来たカードも新規のカードもないデッキを開く | 学習を始めず、今日の分が終わっていることを表示する | 自動(追加) | 現在 | 未実施 |
| FT-05-15 | 学習の途中での日付の変わり目 | 学習の途中で、時計を翌日に進めてから評価する | 評価を正しい日付で記録し、上限の計算が日ごとに分かれる | 自動(追加) | 現在 | 未実施 |

## 3. 既存のテストで覆われていない点

- **FT-05-14**: 出題するカードが 0 枚のときの表示を確認するテストを、テスト名からは特定できなかった。
- **FT-05-15**: 学習の途中で日付が変わる場合のテストを、テスト名からは特定できなかった。日ごとの学習数の数え方は、結合テスト(IT-03-09 の `reviewCountUsesHalfOpenDayAndFirstEverReview`)で確認している。
- 日英の併記(FR-CARD-06、P6-S01)と、利用者によるカードの作成(FR-CARD-07、P6-S19)は、まだ項目にしていない。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 端末の時間帯を変えた場合(旅行など)の「今日」の扱い | リリース前 |
