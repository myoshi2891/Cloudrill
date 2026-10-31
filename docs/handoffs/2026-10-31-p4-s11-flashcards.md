# P4-S11 フラッシュカード 引き継ぎ（2026-10-31）

## 実装

- S10引き継ぎ・DDD-P4から次の作業をP4-S11と判断して実装した。開始時に作業ツリーの変更はなかった。変更は未コミット。
- Presentation に `FlashcardFeature` を追加。`DeckListViewModel`・`DeckListView`（SCR-030）、`CardSessionViewModel`・`CardSessionView`（SCR-031/032）。カードタブのルートと `.cardSession(DeckID)` に接続した。
- デッキ: すべて → 試験定義順のドメイン・サブ項目 → 間違えた問題（`Q:`）。カードのないデッキは出さない。`Q:` は問題索引で分類し、索引にない問題は除外。`features.flashcards: false` なら読み込まず空状態。
- キュー: 内部の `CardLibrary` を一覧と学習で共用。復習（状態あり・`.new` 以外）と新規（状態なしのコンテンツ → `.new` の `Q:`）を `DailyQueueBuilder` に渡す。上限は `ExamPreference` から今日の試験全体の実績を差し引く。「今日」は注入Calendar（アプリは `.current`）。
- 学習: 表 → 答え → 4評価。ボタンに次の間隔を表示。`apply` 成功後に次へ。失敗時は同じ結果で再試行、保存中の連打は拒否。`Q:` は表=問題文、裏=正解の選択肢と理由。英語があれば併記。完了画面に枚数と評価別内訳。

## 境界

- 同一セッション内の再出題（Againで今日中に期限が来るカード）は行わない。デッキ一覧の今日の枚数には残り、次のセッションで出る。
- 練習の誤答の自動カード化（FR-CARD-04）、上限・目標保持率の設定画面（FR-CARD-05、SCR-002）、独自カード（FR-CARD-07）は範囲外。
- Schema・コンテンツ・永続化モデル・Xcodeプロジェクト設定は変更していない。

## 検証

- Presentation 104テスト成功（DesignSystem 7、AppCoreTests 97。S11の13件: デッキ構成・機能無効・キュー順と上限・評価と保存・間隔表示・完了集計・`Q:` の面・保存失敗の再試行・保存中の重複拒否・読込失敗の再試行・DeckID）。
- 最初のテスト実行では、テストの期待値の誤り（カード1枚のデッキ数）で1件失敗。期待値を修正した。
- AppComposition 12テスト成功。実ストアでEasy評価 → 再起動後に review 段階で保存され、今日の枚数が1減ることを確認した。
- AppComposition Releaseビルド成功。
- iPhone 18 Pro Simulator のUIテスト: カードタブ→全カード→2枚評価→学習完了→一覧で今日0枚（追加1件）と、既存のタブ遷移2件が成功。完了画面のスクリーンショットで評価名がキーのまま表示される不具合を発見し、`LocalizedStringKey` に補間リテラルを渡していた箇所を修正。UIテストに評価名の確認を追加して再実行し成功。全UIテストの再実行は行っていない。
- ダーク・最大文字サイズ・実機VoiceOverはS18、リモートCIは未確認。

ログは `/tmp/cloudrill-s11-test.log`、`/tmp/cloudrill-s11-composition.log`、`/tmp/cloudrill-s11-release.log`、`/tmp/cloudrill-s11-ui.log`（一時ファイル）。

## 次の作業

1. P4-S12 関連ドキュメント本文。S15で報告フォーム・キューを接続する。
2. コミットは利用者のタイミングで行う。
