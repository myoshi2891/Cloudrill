# SEC-05 入力検証とコンテンツ描画

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [セキュリティ確認項目書(索引)](../SEC.md) |
| 対応要件 | NFR-10、BDD 8.2、[DDD-P2](../DDD/DDD-P2-ContentPack.md) P2-S06・P2-S07、[DDD-P4](../DDD/DDD-P4-AppMVP.md) P4-S12 |
| 対象 | [FileReading.swift](../../packages/Data/Sources/ContentKit/FileReading.swift)、[MarkdownDocument.swift](../../packages/Presentation/Sources/DesignSystem/MarkdownDocument.swift)、[MarkdownView.swift](../../packages/Presentation/Sources/DesignSystem/MarkdownView.swift)、[ReferenceLink.swift](../../packages/Presentation/Sources/DesignSystem/ReferenceLink.swift)、[common.schema.json](../../content/schemas/common.schema.json)、[loader.py](../../content/scripts/contentvalidate/loader.py) |

---

## 1. 守るものと想定する脅威

守るものは、アプリとビルド環境が、細工されたコンテンツで想定外の動作をしないことである。パックは署名で守るが、署名鍵の漏えいや制作時の混入に備えて、読み込みと描画の側でも確認する。

- パックの中のパスで、パックの外のファイルを読ませる。
- Markdown のリンクや画像で、想定外のスキーム(`javascript:`、`file:`、独自スキーム)や外部のホストへ誘導する。
- 極端に大きいファイルや深い入れ子で、アプリやビルドを止める。
- YAML の機能を使って、検証ツールの実行環境でコードを動かす。

## 2. 確認項目

| ID | 確認項目 | 確認方法 | 対象 | 時期 | 結果 |
|---|---|---|---|---|---|
| SEC-05-01 | パックの本文を読む経路(`PackFiles.data`)が、絶対パス・`..`・パックの外に出るパスを拒否する | `PackLoaderTests` に該当するテストがあることを確認する(無ければ追加する)。`../x`、`/etc/hosts`、`a/../../x` を渡して `storage` のエラーになること | FileReading.swift 15〜21 行目 | 現在 | 未確認 |
| SEC-05-02 | `PackFiles.data` が、読み込みのたびにパック内のパスの各要素を確認し、シンボリックリンクを拒否する(同梱パックは起動時に `PackVerifier` を通らないため、検証済みであることを前提にしない)。既存の確認(先頭の `/`、`..`、パックの外への正規化)も保つ | `PackLoaderTests.symlinkIsRejectedAtRead`(読み込み後に本文をパックの外へのシンボリックリンクに置き換え、`unsafe path` で拒否される)と、`missingAndUndecodableFiles`・`rejectsForeignDocEntry` が成功すること | FileReading.swift | 現在 | 未確認 |
| SEC-05-03 | 試験 ID・版・問題 ID など、ファイル名やパスに使う値を、パスを組み立てる前に形式で確認する | `PackStore.examPath`(試験 ID の正規表現)、`checkVersion`(SemVer)を目視する。問題 ID からパスを作る箇所を洗い出し、同じ確認があることを確認する | PackStore.swift、PackContent.swift | 現在 | 未確認 |
| SEC-05-04 | 未知の列挙値・未知の形式のデータを、黙って無視せずにエラーにする | `FixtureDecodingTests` と `ContentIntegrityCheckerTests` が通る。未知の `QuestionKind` を含むパックが `failures` に入ること | DomainModels、ContentIntegrityChecker.swift | 現在 | 未確認 |
| SEC-05-05 | 参照 URL と公式リンク(`Reference.url`、`officialURL`)が https だけである | `common.schema.json` の `HttpsURL` の正規表現と、それを使う Schema の一覧を確認する。`http://` と `javascript:` の値が CI-01 で拒否されること | common.schema.json、ReferenceLink.swift、CaseStudySections.swift | 現在 | 未確認 |
| SEC-05-06 | Markdown の本文内のリンクも https だけである。それ以外のスキームは、検証ツールで拒否するか、アプリで開かない | `[x](javascript:alert(1))`、`[x](file:///etc/hosts)`、`[x](tel:110)` を含むドキュメントで、`validate.py` の結果と、アプリでタップしたときの挙動を記録する | MarkdownView.swift 82〜83 行目、検証ルール | 現在 | 未確認 |
| SEC-05-07 | Markdown の HTML を解釈しない。画像はパックの中の相対パスだけを解決し、外部の URL を取得しない | `MarkdownDocument` のテストで、`<script>` が文字列として出ること、`![](https://example.com/a.png)` と `![](../a.png)` の `path` が `nil` になることを確認する | MarkdownDocument.swift `packAssetPath` | 現在 | 未確認 |
| SEC-05-08 | パック・ファイル・JSON の大きさに上限がある。上限を超えたら読み込みを中止する | 上限の定義を確認する。数百 MB のファイルを持つパックで、検証と読み込みがメモリを使い切らないこと | PackVerifier.swift、FileReading.swift | P5 | 未確認 |
| SEC-05-09 | YAML を安全なローダーで読む。重複したキーをエラーにする | `loader.py` と `config.py` が `SafeLoader`(`CSafeLoader`)だけを使うこと、`yaml.load(` をローダーの指定なしで呼ぶ箇所が無いことを `grep` で確認する。`test_loader.py` が通る | loader.py、config.py | 現在 | 未確認 |
| SEC-05-10 | リンク切れの確認(CI-06、`--check-links`)が、コンテンツに書かれた URL にだけアクセスし、リダイレクト先や応答の内容を実行・保存しない | `ci06_links.py` の実装を基準に、リダイレクト(301・302)を返すローカルのテストサーバー、または `httpx.MockTransport` に対して `--check-links` を実行し、リクエストの記録を確認する。送られたリクエストが、コンテンツに書かれた URL への HEAD(と、設定した応答での GET の再試行)だけで、リダイレクト先(`Location` の URL)へのリクエストが無いこと。応答の本文を保存・実行しないこと。タイムアウトと同時実行数に上限があること | `content/scripts/contentvalidate/rules/` の CI-06 | 現在 | 未確認 |

## 3. 事前調査で把握した現状

- `PackFiles.data` は、先頭の `/`、`..` の要素、正規化後のパスがパックの外に出ることを確認する。2026-11-17 に、パスの各要素がシンボリックリンクでないことの確認を足した(`PackVerifier.checkPath` と同じ方法)。アプリの読み込み経路(`ExamCatalogService`、`ExamContentResolver`)は `PackVerifier` を通らないため、読み込み時の確認で守る。
- `PackStore.examPath` は試験 ID を `\A[a-z0-9]+(?:-[a-z0-9]+)*\z` で確認し、パスの各要素がシンボリックリンクでないことを確認する。
- `HttpsURL` は `^https://[^\s/$.?#][^\s]*$` である。`ReferenceLink` と `CaseStudySections` は、デコード済みの `URL` を SwiftUI の `Link` に渡す。
- Markdown の本文内のインラインは、`AttributedString(markdown:)`(`inlineOnlyPreservingWhitespace`)で変換して `Text` に渡す。リンクのスキームを確認する処理は、アプリにも検証ルールにも見当たらない(SEC-05-06)。
- HTML ブロックは解釈せず、元の文字列を段落として出す。
- `packAssetPath` は、絶対パス、`\`、先頭の要素の `:`(スキームつき)、`..`、空の要素を拒否する。
- YAML のローダーは `CSafeLoader`(無ければ `SafeLoader`)である。
- リンク切れの確認は `httpx` を使い、`follow_redirects=True` で、タイムアウトと同時実行数を設定から読む。`follow_redirects=True` のため、現在の実装はリダイレクト先にもリクエストを送る。SEC-05-10 の確認方法では不適合になる見込みで、リダイレクトをたどらずに 3xx を報告するか、たどることを許容して記録するかを決める必要がある。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 本文内のリンクのスキームを、検証ルール(CI)で拒否するか、アプリで開かないようにするか、両方か | P4-S18 まで |
| 2 | パック・ファイルの大きさの上限値と、それを置く場所(`validation.yaml` とアプリの定数) | P5-S03 |
