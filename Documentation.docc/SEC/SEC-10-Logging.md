# SEC-10 ログと診断情報

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [セキュリティ確認項目書(索引)](../SEC.md) |
| 対応要件 | NFR-09、BDD 8.5、E-02、E-05、[DDD-P5](../DDD/DDD-P5-Delivery.md) 3.3(ログ)・5 章 No. 3 |
| 対象 | [StartupMetrics.swift](../../packages/AppComposition/Sources/AppComposition/StartupMetrics.swift)、[AppRootView.swift](../../packages/AppComposition/Sources/AppComposition/AppRootView.swift)、[ActiveExamContext.swift](../../packages/Presentation/Sources/AppCore/ActiveExamContext.swift)、[ExamSessionController.swift](../../packages/Presentation/Sources/ExamFeature/ExamSessionController.swift)、P5 で作る report-api |

---

## 1. 守るものと想定する脅威

守るものは、ログと診断情報に学習データや個人情報を残さないことである。

- 端末のログ(sysdiagnose、コンソール)から、解答の内容や自由記述を読まれる。
- サーバーのログに、報告の自由記述や端末を識別する値が残る。
- エラーの詳細(ファイルのパス、内部の状態)を画面に出し、利用者や第三者に見せる。

## 2. 確認項目

| ID | 確認項目 | 確認方法 | 対象 | 時期 | 結果 |
|---|---|---|---|---|---|
| SEC-10-01 | アプリのログに、解答・自由記述・設定の値・ファイルの絶対パスを出さない | パッケージとアプリのターゲットで、`Logger` のインスタンスを作る箇所をすべて洗い出す(`grep -rn 'Logger(' packages/*/Sources ExamPrepApp`)。インスタンスを変数やプロパティに入れている場合は、その名前(`logger`、`audit` などの別名を含む)ごとに呼び出しを検索し、すべてのログの呼び出しを確認する。決まった名前(`logger.` など)の検索だけで済ませない。`Logger` のインスタンスを作らずに使える、関数の形のログの API も別に洗い出す(`grep -rn -E -e '\bos_log\(' -e '\bos_log_(debug\|info\|error\|fault)\(' -e '\bOSLog\(' -e '\bos_signpost\(' packages/*/Sources ExamPrepApp`)。`os_log` などの呼び出しも、埋め込む値と `%{public}`・`%{private}` の指定を同じ基準で確認する。解答・自由記述・設定の値・パスなどの利用者のデータは、`privacy` の指定にかかわらずログに埋め込まない。それ以外の値を埋め込む場合は `privacy: .private` を明示する。数値(整数・浮動小数点数)は既定で公開になるため、埋め込まないか、`privacy: .private` を明示する。既定の扱いに頼らない | アプリ全体 | 現在 | 未確認 |
| SEC-10-02 | `print`・`NSLog`・`debugPrint`・`dump` を、製品のコードで使わない | `grep -rn -E -e '\bprint\(' -e '\bNSLog\(' -e '\bdebugPrint\(' -e '\bdump\(' packages/*/Sources ExamPrepApp` が、テスト支援以外で何も出さない | アプリ全体 | 現在 | 未確認 |
| SEC-10-03 | 計測用のサインポスト(`OSSignposter`)の名前と付加情報に、利用者のデータを含めない | アプリ全体(`packages/*/Sources`、`ExamPrepApp`)のサインポストの呼び出し(`beginInterval`・`endInterval`・`emitEvent` など)を、特定のファイルに限らずすべて洗い出す(例: `grep -rn -E -e 'OSSignposter' -e 'signposter' -e 'beginInterval' -e 'endInterval' -e 'emitEvent' packages/*/Sources ExamPrepApp`。今は `StartupMetrics`・`AppEnvironment`・`AppRootView` にある)。呼び出しごとに、名前が固定の文字列であることと、付加情報(メッセージの文字列と埋め込む値)に利用者のデータが含まれないことを目視する。名前だけの確認で済ませない | アプリ全体(StartupMetrics.swift、AppEnvironment.swift、AppRootView.swift ほか) | 現在 | 未確認 |
| SEC-10-04 | 画面に出すエラーは決まった文言だけで、`error.localizedDescription` や内部のエラーの文字列をそのまま出さない | `String(describing: error)` と `localizedDescription` の使用箇所を洗い出し、画面に届かないことを確認する(`ContentError.undecodable` の `reason`、`storage` の文字列を含む) | Presentation、FileReading.swift、PackStore.swift | 現在 | 未確認 |
| SEC-10-05 | report-api が、自由記述(`comment`)・App Attest の assertion・鍵 ID の生の値をログに出さない | P5-S05 のテストと、ステージングの Cloud Logging の確認。リクエスト本文を記録する設定(ロードバランサー、Cloud Run)が無効であること | DDD-P5 3.3、5 章 No. 3 | P5 | 未確認 |
| SEC-10-06 | クラッシュと性能の診断(MetricKit)を導入する場合、送る内容と送り先を決め、プライバシー表示に反映する | 導入時に、診断のペイロードに利用者のデータが無いこと、送り先が BDD 8.3 の範囲であることを確認する | BDD 8.5 | リリース前 | 未確認 |
| SEC-10-07 | サーバーのログの保存期間と、読める人を決めている | Cloud Logging のバケットの保持期間と IAM を確認する | P5-S07 | リリース前 | 未確認 |

## 3. 事前調査で把握した現状

- アプリのログは `os.Logger`(サブシステム `Cloudrill`、カテゴリ `content`・`exam`)で、文言はすべて固定の文字列である。値の埋め込みは無い(「アプリの起動に失敗しました」「試験選択の復元に失敗しました」など)。
- サインポストは `OSSignposter`(サブシステム `Cloudrill`、`pointsOfInterest`)で、名前は固定(`StartupReady`、`StudyStore`、`ContentBootstrap` など)である。
- `ContentError.undecodable` の `reason` には `String(describing: error)` が入り、`PackStore` の `storage` のエラーには `\(error)` が入る。これらがログや画面に出る経路は、今は見当たらないが、P5 で E-02 の「ログに記録する」を実装するときに確認が必要である(SEC-10-04)。
- MetricKit、利用統計、トラッキングの SDK は使っていない。
- ログの文言が固定のため、失敗の原因を調べる手がかりが少ない。原因を出す場合は、値の種類ごとに公開・非公開を決める必要がある。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | エラーの原因をログに出す範囲と、`privacy` の指定の方針(エラーの種類は公開、パスと内容は非公開、など) | P5 の着手前 |
| 2 | 匿名の利用統計の範囲と基盤(TBD-05)。決まったら確認項目を追加する | MVP 開発の中盤 |
| 3 | MetricKit の診断の送り先(SEC-10-06) | リリース前 |
