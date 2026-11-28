# FT-06 学ぶ(ドキュメントとケース)

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [テスト項目書(索引)](../TST.md) |
| レベル | 機能テスト |
| 対応要件 | FR-DOCS-01、FR-DOCS-02、FR-DOCS-06、FR-CASE-01、FR-CASE-03、SCR-040〜044、[DDD-P4](../DDD/DDD-P4-AppMVP.md) P4-S12・S13 |
| 対象 | `LearnFeature`(`LearnModuleRegistry`、ドメイン目次、ドキュメント閲覧、ケース一覧・詳細)、`MarkdownDocument`、`MarkdownView` |
| 既存のテスト | [LearnFeatureTests](../../packages/Presentation/Tests/AppCoreTests/LearnFeatureTests.swift)、[MarkdownDocumentTests](../../packages/Presentation/Tests/DesignSystemTests/MarkdownDocumentTests.swift)、[DesignSystemTests](../../packages/Presentation/Tests/DesignSystemTests/DesignSystemTests.swift) |

---

## 1. テストの観点

- **目次の構成**: ドメインごとの並び、原稿のないサブ項目の示し方、ドキュメント機能・ケース機能が無効な試験。
- **Markdown の表示**: 見出し、段落、リスト、表、コード、画像。対応していない記法と HTML の扱い。ブロックの順序。
- **ケースの表示**: 試験定義の順、4 区分の要約、公式ページへのリンク、ケースで練習。
- **見つからない・読めない**: 存在しない ID、読み込みの失敗と再試行。
- **出典とライセンス**: 出典の表示と CC BY 4.0 の表示。

## 2. テスト項目

| ID | テスト項目 | 条件・手順 | 期待結果 | 実施方法 | 時期 | 結果 |
|---|---|---|---|---|---|---|
| FT-06-01 | 学ぶタブの構成 | ドキュメントとケースが有効な試験、片方だけ有効な試験で、学ぶタブを開く | 有効な機能の入口だけを表示する。入口は登録表から追加できる | 自動: `LearnFeatureTests.learnModulesFollowFeatures`、`registryAcceptsAdditionalModules` | 現在 | 未実施 |
| FT-06-02 | ドキュメントの目次(FR-DOCS-01) | 一部のサブ項目にだけ原稿があるパックで、目次を開く | サブ項目をドメインごとにまとめて表示し、原稿のないサブ項目はそのことがわかる | 自動: `LearnFeatureTests.docsGroupedByDomainAndMissingDocsShown` | 現在 | 未実施 |
| FT-06-03 | ドメインでの絞り込み | ドメインを指定して目次を開く。ドキュメント機能が無効な試験で開く | 指定したドメインだけを表示する。無効な試験では何も読み込まない | 自動: `LearnFeatureTests.domainFilterAndDisabledDocs` | 現在 | 未実施 |
| FT-06-04 | ドキュメントの本文と出典(FR-DOCS-06) | 原稿のあるサブ項目を開く | 本文と、出典の一覧を表示する | 自動: `LearnFeatureTests.docShowsBodyAndReferences` | 現在 | 未実施 |
| FT-06-05 | Markdown のブロック(FR-DOCS-02) | 見出し・段落・リスト・表・コードブロック・引用を含む原稿 | それぞれを対応するブロックに変換し、原稿の順序を保つ | 自動: `MarkdownDocumentTests.markdownBlocks`、`documentKeepsBlockOrder` | 現在 | 未実施 |
| FT-06-06 | 対応していない記法 | HTML ブロックなど、対応していない記法を含む原稿 | 解釈せず、元の文字列として表示する。アプリは止まらない | 自動: `MarkdownDocumentTests.unsupportedMarkdownFallsBack` | 現在 | 未実施 |
| FT-06-07 | 画像の参照 | パックの中の相対パスの画像、段落の中の画像、パックの外を指す画像(`../`、絶対パス、URL) | パックの中のパスだけを解決する。パックの外を指す画像は解決しない | 自動: `MarkdownDocumentTests.imagesFromPackAssets`、`inlineImageStaysInParagraph`、`pathsOutsidePackAreHidden` | 現在 | 未実施 |
| FT-06-08 | 存在しないサブ項目 | 試験定義にないサブ項目の ID を指定して開く | 「見つかりません」と表示する | 自動: `LearnFeatureTests.unknownSubObjectiveIsNotFound` | 現在 | 未実施 |
| FT-06-09 | ドキュメントの読み込みの失敗 | 本文の読み込みを失敗させる | 失敗を表示し、再試行できる | 自動: `LearnFeatureTests.docLoadFailureCanRetry` | 現在 | 未実施 |
| FT-06-10 | ケースの一覧 | ケース一覧を開く。ケース機能が無効な試験で開く | 試験定義の順で表示する。無効な試験では読み込まない | 自動: `LearnFeatureTests.casesInDefinitionOrder`、`casesNotLoadedWhenDisabled` | 現在 | 未実施 |
| FT-06-11 | ケースの詳細(FR-CASE-01) | ケースを開く | 概要・ビジネス要件・技術要件・既存環境の 4 区分で表示し(`CaseStudySections`)、公式ページへのリンクを出す。全文は載せない | 自動: `LearnFeatureTests.detailShowsSummarySectionsAndOfficialLink` | 現在 | 未実施 |
| FT-06-12 | ケースの異常 | 存在しないケース ID を指定する。読み込みを失敗させる | 「見つかりません」または失敗を表示し、再試行できる | 自動: `LearnFeatureTests.unknownCaseIsNotFound`、`caseLoadFailureCanRetry` | 現在 | 未実施 |
| FT-06-13 | 出典とライセンスの表示(FR-DOCS-06) | ライセンスが CC BY 4.0、Apache 2.0、リンクだけの出典 | CC BY 4.0 と Apache 2.0 は名称を表示し、リンクだけの出典には表示しない | 自動: `DesignSystemTests.referencesShowAttributionLicenseButLinkOnlyHasNoLabel` | 現在 | 未実施 |
| FT-06-14 | 画像の表示 | パックに含まれる画像を参照する原稿を開く | 画像を表示する。読めない場合は代替テキストを出す | 自動(追加) | P4-S18 | 未実施 |
| FT-06-15 | 本文内のリンク | 本文に https のリンクと、それ以外のスキームのリンクを含む原稿を開き、タップする | https のリンクはブラウザで開く。それ以外は開かない(SEC-05-06 の決定に従う) | 自動(追加) | P4-S18 | 未実施 |

## 3. 既存のテストで覆われていない点

- **FT-06-14**: 画像は、パックの中のパスの解決と代替表示までが実装済みで、画像そのものの表示は未実装である。
- **FT-06-15**: 本文内のリンクのスキームの扱いは未決である([SEC-05](../SEC/SEC-05-InputAndRendering.md) の未決事項 1)。決定後にテストを追加する。
- 長い表や長いコードブロックの横スクロール、文字サイズを最大にしたときの表示は、E2E-06 で確認する。
- 全文検索(FR-DOCS-04)、ブックマークと既読(FR-DOCS-05)、問題・カードとの相互リンク(FR-DOCS-03)、要件マッピング(FR-CASE-02)は P6 の対象で、まだ項目にしていない。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 本文内のリンクのスキームの扱い(SEC-05 の未決事項 1 と同じ) | P4-S18 |
| 2 | 画像を表示する時期(MVP に含めるか) | リリース前 |
