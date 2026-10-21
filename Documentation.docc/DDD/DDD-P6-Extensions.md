# Cloudrill 詳細設計書 P6: 拡張(v1.1〜v2.0)

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-10-21 |
| 上位文書 | [詳細設計書(索引・共通設計)](../DDD.md) |
| 対象 | RDD 12 章の v1.1、v1.2、v2.0 の機能と、2つ目の試験の追加 |
| ステータス | レビュー待ち |

---

## 目次

1. [目的とスコープ](#1-目的とスコープ)
2. [前提](#2-前提)
3. [リリースとステップの対応](#3-リリースとステップの対応)
4. [ステップ](#4-ステップ)
5. [フェーズの完了条件](#5-フェーズの完了条件)
6. [申し送り](#6-申し送り)

---

## 1. 目的とスコープ

MVP の後に追加する機能を、P0〜P5 で用意した拡張点の上に積み上げる。各ステップは独立して進められるように、前提を明記する。

このフェーズの文書は、P0〜P5 より粒度を粗くしている。着手するリリース(v1.1 など)の計画時に、対象のステップを P0〜P5 と同じ粒度(テスト名、シグネチャ、コマンド)まで詳細化し、本書を改訂する。このように、近いものから順に詳細にする進め方を「ローリングウェーブ」と呼ぶ。

---

## 2. 前提

- MVP(P0〜P5)が完了し、v1.0 をリリースしている。
- 各ステップの設計の判断は、[DDD 4 章](../DDD.md#4-複数試験に対応するアーキテクチャ)の拡張点に従う。新しい機能は、既存の型を変更せずに、登録の追加で組み込むことを優先する。

---

## 3. リリースとステップの対応

| リリース | ステップ |
|---|---|
| v1.1 コンテンツの充実 | P6-S01〜S05(模試 6 回分と全ドキュメントはコンテンツの作業であり、コードの変更はない) |
| v1.2 差別化機能 | P6-S06〜S10 |
| v2.0 継続支援と AI | P6-S11〜S18 |
| 優先度 C の機能 | P6-S19 |
| 試験の追加(時期は別途決める) | P6-S20 |

---

## 4. ステップ

### P6-S01 日英の切り替え

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-PRAC-07、FR-CARD-06、NFR-08 |
| 前提 | P4 |
| 成果物 | `StudyModels/DisplayLanguage.swift`、各 ViewModel の表示用の変換、設定画面 |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `englishWhenAvailable` | 表示言語 `en`、`en` のある問題 | 英語の文章 |
| `fallbackToJapanese` | 表示言語 `en`、`en` のない問題 | 日本語の文章と、「英語版はありません」の表示 |
| `toggleOnExplanation` | 解説画面の [EN] をタップ | その画面だけ切り替わり、設定は変わらない |
| `cardShowsBoth` | カードの表と裏 | 日英を併記する(FR-CARD-06) |

**Green**: 既存の `LocalizedText.text(preferEnglish:)` を使う。英語が欠けていることを判定するため、`LocalizedText.hasEnglish` を追加する。

**完了条件**: 該当するテストが通る。

---

### P6-S02 iPad の Split View

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-EXAM-10、BDD 4.4 |
| 前提 | P4-S07 |
| 成果物 | `ExamSessionView` のレイアウトの分岐、`CaseSplitLayout` |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `layoutForRegularWidth` | 横方向のサイズクラスが regular、ケース問題 | `layout == .split(ratio: 0.4)` |
| `layoutWithoutCase` | regular、ケースのない問題 | `layout == .full` |
| `layoutForCompact` | compact | `layout == .sheet` |
| `ratioIsPersisted` | 比率を 0.5 に変える | 同じ受験の中で維持される |

レイアウトの判定は ViewModel の純粋関数にし、ドラッグの操作は UI テストで確認する。

**完了条件**: 該当するテストが通り、iPad のシミュレータの UI テストで左右に表示される。

---

### P6-S03 ドキュメントの全文検索

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-DOCS-04、BDD 8.1 |
| 前提 | P2、P4-S12 |
| 成果物 | `contentpack` の検索インデックスの生成、`docs/search-index.json`、Swift の `DocSearchIndex`、`formatVersion` の判断 |

**設計**: パックのビルド時に、文字の 2-gram の転置インデックスを作る。日本語の分かち書きは行わない(依存を増やさず、オフラインで動かすため)。ファイルを追加するだけなので、`formatVersion` は上げない(古いアプリは未知のファイルを読まない)。

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `test_search_index_is_deterministic`(Python) | 同じ docs で 2 回ビルド | 同じバイト列 |
| `searchFindsJapanese` | 「暗号鍵」 | その語を含むページが上位 |
| `searchNormalizesWidth` | 全角の「ＣＭＥＫ」 | 半角の CMEK を含むページ |
| `inPageSearch` | ページ内検索 | 該当箇所の位置の一覧 |

**完了条件**: Python と Swift の両方のテストが通る。

---

### P6-S04 受験履歴のグラフ

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-EXAM-13、SCR-016 |
| 前提 | P3-S02、P4-S09 |
| 成果物 | `ExamHistoryViewModel`、Swift Charts の View |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `historyPoints` | 提出済み 3 件 | 日付の順に 3 点 |
| `abandonedExcluded` | 放棄 1 件 | 含まない |
| `perExamSet` | 模試 1 と 2 | 模試ごとの系列 |

**完了条件**: 該当するテストが通る。

---

### P6-S05 関連リンク、ブックマーク、既読の画面

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-DOCS-03、FR-DOCS-05 |
| 前提 | P3-S05、P4-S12 |
| 成果物 | `DocViewModel` の関連リンク、ブックマークの一覧画面 |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `relatedQuestions` | サブ項目 3.2 のページ | 3.2 の問題数と、練習を始める Route |
| `relatedCards` | 同上 | 3.2 のカードのデッキへの Route |
| `bookmarkToggle` | ブックマークを切り替える | `BookmarkRepository` に反映される |
| `readMarkOnScrollEnd` | ページの末尾まで読む | 既読になる |

**完了条件**: 該当するテストが通る。

---

### P6-S06 ケースの要件マッピング

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-CASE-02 |
| 前提 | P4-S13 |
| 成果物 | `CaseDetailViewModel` の要件マッピング |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `mappingForRequirement` | 要件をタップ | 候補のサービス、選定の理由、除外すべき選択肢とその理由 |
| `noMapping` | マッピングのない要件 | タップできない |

**完了条件**: 該当するテストが通る。

---

### P6-S07 ディシジョンツリー

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-DECI-01、SCR-045 |
| 前提 | P4-S12(`LearnModuleRegistry`) |
| 成果物 | `DecisionTreeViewModel`、`LearnModuleRegistry` への登録、CI でのツリーの循環検出(`content/README.md` の未対応事項) |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `test_ci09_detects_cycle`(Python の invalid fixture) | ノードの `next` が循環する | CI-09 error |
| `test_ci09_detects_unreachable_node` | どこからも辿れないノード | CI-09 warning |
| `walkToResult` | 根から 3 回選ぶ | 結果のノードに着く |
| `back` | 1 つ戻る | 直前のノード |
| `registeredOnlyWhenEnabled` | `features.decisionTrees: false` | 「学ぶ」タブに出ない |

**完了条件**: Python と Swift の両方のテストが通る。

---

### P6-S08 キーワード反射トレーナー

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-DECI-02、SCR-046 |
| 前提 | P4-S12 |
| 成果物 | `KeywordDrillViewModel`、`LearnModuleRegistry` への登録 |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `twoChoicesShuffled` | ドリル 1 件 | `correct` と `distractor` の 2 択。並びは seed で決まる |
| `recordsAsDrill` | 解答する | `AnswerFact.mode == .drill`(準備度の計算から除かれる) |
| `timeLimitPerItem` | 1 問 5 秒 | 時間切れは不正解 |

**完了条件**: 該当するテストが通る。

---

### P6-S09 合格準備度の表示

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-ANLY-02、LG-05、TBD-08 |
| 前提 | P1-S09、P4-S05 |
| 成果物 | `HomeViewModel` と `AnalyticsViewModel` の準備度 |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `collectingState` | `.collecting(29, 30)` | 「データ収集中(あと 1 問)」。数値は出さない |
| `valueWithDisclaimer` | `.ready(68.2, …)` | 「68(目安)」と、「合格を予測するものではありません」 |
| `retentionsFromFSRS` | カード 3 枚 | `FSRSScheduler.retrievability` で求めた値が、ドメインごとに渡される |

**完了条件**: 該当するテストが通る。

---

### P6-S10 誤答タグの分析と学習カレンダー

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-ANLY-03、FR-ANLY-04、SCR-051 |
| 前提 | P4-S14 |
| 成果物 | `MistakeTagSummary`、`StudyCalendar`、分析画面 |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `countsTagsOfChosenWrongChoices` | 誤答で選んだ選択肢の `mistakeTags` | タグごとの件数(選ばなかった選択肢のタグは数えない) |
| `topTagMessage` | `cost` が最多 | 「コストの見落としが多い」 |
| `calendarDays` | 学習した日 | 日ごとの学習時間(解答の `elapsedSeconds` とカードの復習回数から求める) |

**完了条件**: 該当するテストが通る。

---

### P6-S11 学習計画

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-PLAN-01、SCR-001、SCR-003 |
| 前提 | P3-S06 |
| 成果物 | `StudyPlanCalculator`(Domain)、学習計画の画面、ホームのカウントダウン |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `dailyTargets` | 試験まで 20 日、未解答 300 問、未学習のカード 400 枚 | 1 日に問題 15、カード 20 |
| `pastExamDate` | 試験日が過去 | 計画を出さず、試験日の再設定を促す |
| `perExam` | 2 つの試験の試験日 | 選択中の試験の計画だけ |

**完了条件**: 該当するテストが通る。

---

### P6-S12 通知

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-PLAN-03 |
| 前提 | P6-S11 |
| 成果物 | `ReviewReminderScheduler`(`UNUserNotificationCenter` をプロトコルで包む) |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `schedulesWhenEnabled` | 通知 ON、明日の期限のカード 10 枚 | 明日の指定時刻に 1 件 |
| `noneWhenDisabled` | 通知 OFF | 予約しない。既存の予約を消す |
| `askPermissionOnce` | 初めて ON にする | 許可を 1 回だけ求める |

**完了条件**: 該当するテストが通る。

---

### P6-S13 ウィジェット

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-PLAN-02、BDD 2.3 |
| 前提 | P2-S08(App Group のパック)、P3 |
| 成果物 | `ExamPrepWidget` ターゲット、`TodayQuestionProvider` |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `questionOfTheDayIsStable` | 同じ日付、同じ試験 | 同じ問題(日付と試験 ID から seed を作る) |
| `differentPerExam` | 同じ日付、違う試験 | それぞれの試験の問題 |
| `readOnlyStore` | ウィジェットから | ストアを読み取りだけで開く(BDD 2.3) |

**完了条件**: 該当するテストが通る。ウィジェットのターゲットは Xcode の **File > New > Target…** で追加する。

---

### P6-S14 App Intents

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-PLAN-04 |
| 前提 | P4-S03 |
| 成果物 | `StartCardReviewIntent`、`StartPracticeIntent` |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `cardIntentRoutes` | 「カードを 10 枚」 | Route が `.cardSession`、枚数 10 |
| `intentUsesCurrentExam` | 選択中の試験 | その試験で開く |

**完了条件**: 該当するテストが通る。

---

### P6-S15 iCloud 同期の有効化

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-ACCT-01、E-10、BDD 6.9 |
| 前提 | P3(モデルは同期できる形になっている) |
| 成果物 | CloudKit のコンテナの設定、`SyncStatusMonitor`、設定画面の表示 |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `fallbackWhenUnavailable` | iCloud のアカウントがない | 端末内だけで動作し、設定画面に「iCloud 同期オフ」(E-10) |
| `dedupeAfterImport` | 同期の取り込みの通知 | `SyncDeduplicator.run()` が呼ばれる |

**検証手順**(手動): 2 台の実機で、解答とカードが同期されること、同時に同じ模試を進めた場合の通知(BDD 6.9)、全削除が両方の端末に反映されること(P3-S08 の申し送り)を確認する。

**完了条件**: テストが通り、手動の検証の記録がある。

---

### P6-S16 課金

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-ACCT-02、SCR-092、E-09、TBD-02 |
| 前提 | TBD-02 の決定 |
| 成果物 | `Purchases` の `EntitlementService`、`EntitlementProviding`(DomainInterfaces)、ペイウォール |

**設計**: 権利は試験ごとに判定する。商品 ID は `catalog.json` の `productIDs` から得る(コードに書かない。X-01)。

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `freeTierPerExam` | 未購入 | 試験ごとの無料範囲(模試 1 回など。BDD 7.3 の想定)だけが使える |
| `purchaseUnlocksExamOnly` | `test-alpha` の商品を購入 | `test-alpha` だけが解放される |
| `cachedOffline` | オフライン | 最後に確認した権利を使う(BDD 7.3) |
| `pendingNotGranted` | 購入が保留 | 権利を付与しない(E-09) |

StoreKit のテストには、StoreKit Configuration ファイルと `SKTestSession` を使う。

**完了条件**: 該当するテストが通る。

---

### P6-S17 AI 解説

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-AI-01、FR-AI-02、FR-AI-03、TBD-03 |
| 前提 | TBD-03 の決定 |
| 成果物 | `ExplanationRephraser` プロトコルと、選んだ方式の実装 |

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `neverJudgesCorrectness` | 言い換えの結果 | 正誤の表示は、常に作成済みのデータから出す(FR-AI-02)。言い換えの結果を採点に使う経路がない |
| `inputIsAuthoredRationale` | 言い換えの依頼 | 入力は、作成済みの解説と問題文だけ |
| `unavailableHidesButton` | 対応していない端末(Foundation Models を使う場合、iOS 26 未満) | ボタンを出さない |
| `labelAsAIGenerated` | 言い換えを表示 | 「AI による言い換え」と明示する |

**完了条件**: 該当するテストが通る。

---

### P6-S18 図の配置問題(新しい出題形式の実例)

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-DECI-03、[DDD 4.10 C](../DDD.md#c-新しい出題形式を追加するアプリの更新が必要) |
| 前提 | P1-S03、P4-S07 |
| 成果物 | `QuestionKind.placement`、`AnswerSelection.placement`、`PlacementEvaluator`、`PlacementRenderer`、Schema の変更、fixture |

[DDD 4.10 C](../DDD.md#c-新しい出題形式を追加するアプリの更新が必要) の手順を、そのまま実行する。

**Red**:

| テスト | 条件 | 期待 |
|---|---|---|
| `test_schemas::test_placement_question` | 枠とサービスの対応を持つ問題 | 違反なし |
| `PlacementEvaluatorTests.allSlotsCorrect` | すべての枠が正しい | `true` |
| `PlacementEvaluatorTests.oneSlotWrong` | 1 つ違う | `false`(部分点なし。ADR-03) |
| `registryCoversAllKinds`(P1-S03 の既存のテスト) | `placement` を追加した直後 | 評価器を登録するまで失敗する(登録漏れの検出が働くことの確認) |
| `rendererRegistryCoversKinds`(P4-S07 の既存のテスト) | 同上 | 表示を登録するまで失敗する |
| `integrityRejectsOldApp` | `supportedKinds` に `placement` がない | `ContentIntegrityChecker` が違反にする |

**完了条件**: 全テストが通る。`placement` を使うパックの `minAppVersion` を、この機能を含むアプリの版にする。

---

### P6-S19 優先度 C の機能

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-CARD-07(独自カード)、FR-CASE-04(推奨アーキテクチャ図)、FR-ANLY-05(推薦) |
| 前提 | 各機能の計画時に、ステップを分けて詳細化する |

| 機能 | 設計の方針 |
|---|---|
| 独自カード | 利用者が作ったカードは、学習記録として SwiftData に保存する(コンテンツパックには入れない)。ID は `U:` + UUID。`SchemaV2` の追加が必要 |
| 推奨アーキテクチャ図 | ケースのデータに図のパス(`assets/`)を追加する。Schema と Swift の型を同時に変える |
| 推薦 | `QuestionSelector` の弱点優先と、FSRS の保持率を組み合わせた `Recommender` を Domain に追加する |

---

### P6-S20 2つ目の試験の追加

| 項目 | 内容 |
|---|---|
| 対応要件 | [DDD 4.10 A](../DDD.md#a-新しい試験を追加するコードの変更なし)、X-01、X-06 |
| 前提 | 追加する試験の決定(例: Google Cloud Associate Cloud Engineer、`gcp-ace`)。他ベンダーの場合は TBD-11 の決定 |
| 成果物 | `content/exams/<examID>/`、`catalog.yaml` の更新(必要なら `vendors.yaml`) |

**コードを変更せずに試験を追加できる**ことを確かめる、拡張性の最終的な受け入れテストである。

**Red**:

1. `catalog.yaml` に新しい試験を `comingSoon` で追加する。CI-13 が「試験のディレクトリがない」ことで失敗するのを確認する。
2. `content/exams/<examID>/exam.yaml` を作る。`validate.py --exam <examID>` が、模試の構成などの不足を報告するのを確認する。

**Green**: [DDD 4.10 A](../DDD.md#a-新しい試験を追加するコードの変更なし) の手順でコンテンツを追加し、error を 0 件にする。

**検証手順**:

1. ステージングにリリースし(P5-S01)、カタログを `available` にする(P5-S02)。
2. 既存のアプリ(コードを変更していない版)で、試験の一覧に新しい試験が出て、選ぶとパックを取得し、模試・練習・カードが使えることを確認する。

**完了条件**: `git diff --stat <前回のアプリのリリースタグ> -- packages/ ExamPrepApp/` の結果が空である(コードを変更していない)。

---

## 5. フェーズの完了条件

各リリース(v1.1、v1.2、v2.0)の時点で、[DDD 7.8](../DDD.md#78-フェーズの完了条件共通) の共通条件を満たすこと。加えて、そのリリースに含めたステップを、本書で P0〜P5 と同じ粒度まで詳細化してあること。

---

## 6. 申し送り

| 宛先 | 内容 |
|---|---|
| 次の改訂 | v1.1 の計画時に、P6-S01〜S05 を詳細化する。P6-S20 の対象の試験が決まったら、その試験の `exam.yaml` の下書きを付録に加える |
| BDD 更新の PR | 本書の C-01〜C-14 を BDD に反映するときに、P6 の機能の画面一覧(SCR-003、016、045、046、051、092)の対応も確認する |
