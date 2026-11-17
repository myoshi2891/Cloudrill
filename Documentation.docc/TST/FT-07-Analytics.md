# FT-07 学習分析

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 機能テスト |
| 対応要件 | FR-ANLY-01、FR-ANLY-02、SCR-050、SCR-051、BDD 6.6、[DDD-P4](../DDD/DDD-P4-AppMVP.md) P4-S14 |
| 対象 | `AnalyticsFeature`(ドメイン別・サブ項目別の正答率)、`ReadinessCalculator` |
| 既存のテスト | [AnalyticsViewModelTests](../../packages/Presentation/Tests/AppCoreTests/AnalyticsViewModelTests.swift)、[ReadinessCalculatorTests](../../packages/Domain/Tests/ReadinessTests/ReadinessCalculatorTests.swift) |

---

## 1. テストの観点

- **集計の単位**: ドメイン別とサブ項目別。試験ごとに分けること。
- **解答がない場合**: 0% ではなく「—」と表示すること。全ドメインを試験定義の順で出すこと。
- **集計の対象**: 模試と練習の両方を含めること。問題が改訂でサブ項目を移っても、解答した時点の区分に残すこと。
- **読み込みの失敗**: 前の表示を保ち、再試行できること。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| FT-07-01 | ドメイン別の正答率(FR-ANLY-01) | ドメインごとに正答数の違う解答履歴で、分析タブを開く | ドメインごとの正答率と解答数を表示する | 自動: `AnalyticsViewModelTests.accuracyByDomain` | 現在 | 未実施 |
| FT-07-02 | サブ項目別の正答率(FR-ANLY-01) | ドメインの詳細を開く | サブ項目ごとの正答率と解答数を表示する | 自動: `AnalyticsViewModelTests.accuracyBySubObjective` | 現在 | 未実施 |
| FT-07-03 | 解答した時点の区分 | 解答のあとで、問題のサブ項目が別のドメインへ移った状態を作る | 解答を記録したときのドメインとサブ項目で集計する | 自動: `AnalyticsViewModelTests.subObjectiveTallyStaysWithRecordedDomain` | 現在 | 未実施 |
| FT-07-04 | 解答のないドメイン | 一部のドメインにだけ解答がある。まったく解答がない | 解答のないドメインは「—」と表示する。まったく解答がなくても、全ドメインを表示する | 自動: `AnalyticsViewModelTests.noAnswersDomain`、`emptyHistoryShowsAllDomainsAsDash` | 現在 | 未実施 |
| FT-07-05 | ドメインの名前と順 | 形の違う 2 つの試験で開く | ドメインの名前と順が、試験定義のとおりである | 自動: `AnalyticsViewModelTests.domainNamesFromDefinition` | 現在 | 未実施 |
| FT-07-06 | 試験ごとの集計 | 2 つの試験に解答履歴がある | 選んでいる試験の履歴だけを集計する | 自動: `AnalyticsViewModelTests.perExamOnly` | 現在 | 未実施 |
| FT-07-07 | 読み込みの失敗 | 履歴の読み込みを失敗させる | 前の表示を保ち、失敗を表示する。再試行で回復する | 自動: `AnalyticsViewModelTests.loadFailureKeepsPreviousAndCanRetry` | 現在 | 未実施 |
| FT-07-08 | 模試と練習の両方 | 模試と練習の両方で解答する | 両方の解答が集計に入る | 自動(追加) | 現在 | 未実施 |
| FT-07-09 | 同じ問題への複数回の解答 | 同じ問題に、不正解のあと正解する | 数え方(全回を数える、または直近だけ)が仕様どおりである | 自動(追加) | 現在 | 未実施 |
| FT-07-10 | グラフの表示 | 分析タブを開く | 横棒のグラフと数値が一致する。VoiceOver で値を読める | 手動 | P4-S18 | 未実施 |
| FT-07-11 | 合格準備度(FR-ANLY-02) | 解答数が最低数に満たない場合と、満たす場合 | 満たない間は「集計中」とし、満たしたら準備度を表示する。「目安」であることを明記する | 自動(追加)。計算は `ReadinessCalculatorTests.collectingBelowMinimum`、`workedExample` | P6 | 未実施 |

## 3. 既存のテストで覆われていない点

- **FT-07-08**: 画面の集計に模試と練習の両方が入ることを、ViewModel のテスト名からは特定できなかった。保存側は、結合テスト(IT-03-07 の `lastResultAndReadinessIncludeEveryMode`)で確認している。
- **FT-07-09**: 同じ問題に複数回解答した場合の数え方は、仕様の記述が見当たらない(未決事項 1)。
- **FT-07-10**: グラフ(Swift Charts)の表示は、自動テストでは確認していない。
- **FT-07-11**: 準備度の計算は実装済みだが、画面は P6-S09 の対象である。
- 誤答タグ別の集計(FR-ANLY-03)と学習カレンダー(FR-ANLY-04)は P6-S10 の対象で、まだ項目にしていない。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 同じ問題に複数回解答した場合の、正答率の数え方。準備度(`ReadinessCalculator`)は、最低解答数とカバー率には問題の種類数(重複を除く)を使うが、正答率には模試と練習の全解答を重み付きで数える(同じ問題に誤答のあと正答した場合、両方の解答が正答率に入る)。分析の正答率をどちらに合わせるか。比べるときは、準備度の正答率が繰り返しの解答を除いていないことを前提にする | P4-S18 |
