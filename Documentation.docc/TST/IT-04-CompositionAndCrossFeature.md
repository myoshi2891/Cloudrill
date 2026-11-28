# IT-04 構成と機能間の連携(Data と Presentation の接続)

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 結合テスト |
| 対応要件 | FR-EXAM-07、FR-EXAM-09、FR-CARD-04、FR-ANLY-01、FR-ACCT-03、AC-02、E-06、E-07、[DDD](../DDD.md) 5 章、[DDD-P4](../DDD/DDD-P4-AppMVP.md) P4-S01 |
| 対象 | `AppEnvironment`(`live`・`development`・`uiTesting`)で、実際のパック・実際のストア・ViewModel をつないだ状態。`ExamSessionStore`、`SubmittedExamContent`、`SubmittedExamContentCache` |
| 既存のテスト | [AppEnvironmentTests](../../packages/AppComposition/Tests/AppCompositionTests/AppEnvironmentTests.swift) |

---

## 1. テストの観点

機能テスト(FT)は依存を Fake に差し替える。ここでは、実際のパックと実際のストアをつないで、次の 2 つを確認する。

- **構成の正しさ**: アプリの起動時の組み立て(Composition root)が、正しい実装どうしをつないでいること。本番・開発・UI テストの構成の違い。
- **機能間の連携**: ある機能の結果が、別の機能に正しく伝わること。
  - 模試の提出 → 誤答のカード化 → カードのデッキとホームの復習期限
  - 模試・練習の解答 → 分析の正答率とホームの弱点
  - 設定(シャッフル、上限) → 次の模試・カードの出題
  - データの削除 → 全タブの画面と、版の固定
  - 提出済みの受験 → 受験時の版と出題順での結果・解説

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| IT-04-01 | UI テスト用の構成 | 起動引数を渡して、UI テスト用の構成を作る | 引数を解釈し、指定した fixture の試験だけで起動する。時計と乱数が固定される | 自動: `AppEnvironmentTests.uiTestingParsesArgumentsAndBootstrapsFixture`(時計と、乱数の seed が 42 に固定されることを確認する) | 現在 | 未実施 |
| IT-04-02 | 不正な起動引数 | 未知の引数、重複した引数、矛盾した引数、不正な日時やパスを渡す | 構成を作らず、エラーにする | 自動: `AppEnvironmentTests.invalidArgumentsAreRejected`(重複した引数 `-network offline -network offline`、`-store-in-memory` の重複を含む) | 現在 | 未実施 |
| IT-04-03 | 開発用の構成 | 開発用の構成を作る | システムの時計と、実際のリポジトリを使う | 自動: `AppEnvironmentTests.developmentUsesSystemTimeAndRealRepositories` | 現在 | 未実施 |
| IT-04-04 | 本番の構成 | 開発用の印(`development.json`)のあるパックで、本番の構成を作る | 起動を拒否する | 自動: `AppEnvironmentTests.liveRejectsDevelopmentBundle` | 現在 | 未実施 |
| IT-04-05 | 同梱パックの確認 | アプリに同梱したパックを読む | カタログで `available` の試験のパックがそろっていて、署名の検証に通る | 自動: `AppEnvironmentTests.bundledPacksArePresentAndSignaturesVerify` | 現在 | 未実施 |
| IT-04-06 | 採点と描画の対応 | 採点の登録表と、問題の描画の登録表を比べる | 対応する問題の種類が一致する。一致しなければ起動を拒否する | 自動: `AppEnvironmentTests.supportedKindsMatchBothRegistries`(対応する種類が `QuestionKind.allCases` と一致することだけ)。不一致のときに起動を拒否すること(`AppEnvironment` の `registryMismatch`)は自動(追加)。登録表が static なので、不一致を作るには差し替えの手段が要る | 現在 | 未実施 |
| IT-04-07 | 選択の復元 | ディスクの保存先で試験を選び、構成を作り直す | 前回の試験が選ばれている | 自動: `AppEnvironmentTests.diskConfigurationRestoresLastSelection` | 現在 | 未実施 |
| IT-04-08 | 模試の開始と破棄 | 実際のリポジトリとパックの保存で、模試を開始し、破棄する | 受験の記録と版の固定ができ、破棄で両方が消える | 自動: `AppEnvironmentTests.startsAndAbandonsWithRealRepositoriesAndPins` | 現在 | 未実施 |
| IT-04-09 | 模試の復元と期限後の提出(AC-02、E-06) | ディスクの保存先で解答し、構成を作り直す。時計を期限の後へ進める | 解答と残り時間を復元する。期限を過ぎていれば提出する | 自動: `AppEnvironmentTests.sessionRestoresDiskAnswersAndSubmitsAfterExpiry` | 現在 | 未実施 |
| IT-04-10 | 解答と見直しの共有 | 解答画面で解答し、見直しを開いて提出する | 解答と見直しが同じ状態を共有する。提出で得点を確定し、誤答のカードを保存する | 自動: `AppEnvironmentTests.reviewAndManualSubmissionUseSharedSessionAndPersistCards` | 現在 | 未実施 |
| IT-04-11 | 提出済みの受験の結果と解説(E-07) | 模試を提出したあと、有効なコンテンツの版を新しくしてから、結果と解説を開く | 受験したときの版と出題順で表示する | 自動(追加)。Fake での確認は FT-03-06〜08 | 現在 | 未実施 |
| IT-04-12 | 練習の解答とフラグの保持 | ディスクの保存先で練習し、フラグを付け、保存先を開き直す | 解答とフラグが残っている | 自動: `AppEnvironmentTests.practiceAnswersAndFlagsSurviveReopeningDiskStore` | 現在 | 未実施 |
| IT-04-13 | カードの学習の保持 | ディスクの保存先でカードを評価し、保存先を開き直す | カードの状態と次回の期限が残っている。デッキの一覧に反映される | 自動: `AppEnvironmentTests.cardReviewSurvivesReopeningDiskStore`(開き直したあと、カードの状態が `review` であることと、デッキの今日の枚数が 1 枚減ることを確認する)。保存された次回の期限の値そのものの確認は自動(追加) | 現在 | 未実施 |
| IT-04-14 | 同梱のドキュメント | 同梱パックのドキュメントを開く | Markdown として読み込み、ブロックに変換できる | 自動: `AppEnvironmentTests.bundledDocOpensAsMarkdown` | 現在 | 未実施 |
| IT-04-15 | 誤答のカード化からデッキ・ホームへ | 模試で間違えて提出し、カードタブとホームを開く | 誤答のデッキにカードが出る。ホームの復習期限の枚数に入る | 自動(追加) | 現在 | 未実施 |
| IT-04-16 | 解答から分析・ホームへ | 模試と練習で解答し、分析タブとホームを開く | 両方の解答が、ドメイン別の正答率と弱点に反映される | 自動(追加) | 現在 | 未実施 |
| IT-04-17 | 設定から出題へ | シャッフルを ON にして模試を開始する。進行中にシャッフルを OFF にする。カードの上限を変える | 次に開始する模試に反映する。進行中の模試の順は変わらない。カードのその日の出題数が変わる | 自動(追加) | 現在 | 未実施 |
| IT-04-18 | 削除から画面と版の固定へ | 模試の進行中と提出後に、その試験のデータを削除する | 履歴・カード・分析・再開の導線が消える。版の固定が外れ、不要な版を消せる | 自動(追加) | 現在 | 未実施 |
| IT-04-19 | 試験ごとの分離 | 試験 A で模試・練習・カードを行い、試験 B に切り替える | B のホーム・分析・カード・履歴に、A のデータが出ない。A に戻ると元のデータがある | 自動(追加) | 現在 | 未実施 |
| IT-04-20 | 保持の上限を超えた受験 | 保持の上限を超える件数の模試を提出し、最も古い受験の結果を開く | 版がなければ、エラーを表示する(現在の版で代用しない)。得点の要約など、版がなくても出せる情報の扱いが仕様どおりである | 自動(追加) | リリース前 | 未実施 |

## 3. 既存のテストで覆われていない点

既存の `AppEnvironmentTests`(13 件)は、構成の正しさと、1 つの機能の保存・復元を確認している。**複数の機能をまたぐ連携(IT-04-15〜19)を、実際のストアで確認するテストは見当たらない。** 機能ごとの振る舞いは FT で、画面を通した確認は UI テスト(E2E-03)で一部を見ているが、次の点が空いている。

- **IT-04-11**: 結果と解説の復元は、Fake を使った ViewModel のテスト(FT-03-06〜08)にある。実際のパックの保存と受験の記録を使った確認は見当たらない。
- **IT-04-15、16**: 提出や解答の結果が、別のタブの集計に届くこと。
- **IT-04-17**: 設定の変更が、次の出題にだけ効くこと。
- **IT-04-18**: データの削除のあとの、版の固定の扱い。
- **IT-04-19**: 試験の切り替えをまたいだデータの分離。リポジトリ単体の分離は IT-03 で確認している。
- **IT-04-20**: 保持の上限(既定 20 件)を超えた受験の結果の表示。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 保持の上限を超えた古い受験について、結果のどこまでを表示するか(得点だけを出すか、全体をエラーにするか) | リリース前 |
| 2 | 機能間の連携のテストを、`AppEnvironmentTests` に足すか、UI テストに足すか(実行時間と、失敗時の原因の特定のしやすさで決める) | P4-S18 |
