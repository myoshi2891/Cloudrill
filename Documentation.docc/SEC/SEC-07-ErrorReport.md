# SEC-07 誤り報告(アプリのキューと report-api)

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [セキュリティ確認項目書(索引)](../SEC.md) |
| 対応要件 | NFR-09、BDD 7.2、BDD 8.2(API の悪用対策)、E-08、[DDD-P4](../DDD/DDD-P4-AppMVP.md) P4-S15、[DDD-P5](../DDD/DDD-P5-Delivery.md) 3.3・P5-S04〜S06 |
| 対象 | [ReportSheetViewModel.swift](../../packages/Presentation/Sources/SettingsFeature/ReportSheetViewModel.swift)、[ReportQueueStore.swift](../../packages/Data/Sources/Persistence/ReportQueueStore.swift)、[AppEnvironment.swift](../../packages/AppComposition/Sources/AppComposition/AppEnvironment.swift)(`reportMetadata`)、P5 で作る `server/report-api/` と `ReportClient` |

---

## 1. 守るものと想定する脅威

守るものは、報告の自由記述に含まれうる個人情報と、report-api の可用性である。

- 利用者が自由記述に氏名や連絡先を書き、それが長く保存される、または複製される。
- アプリ以外から大量の報告を送られる。
- 捕まえたリクエストを再送される。
- 報告の内容を、担当者以外が読める。

## 2. 確認項目

| ID | 確認項目 | 確認方法 | 対象 | 時期 | 結果 |
|---|---|---|---|---|---|
| SEC-07-01 | 入力欄に「個人情報は書かないでください」と表示する | 報告シートを開き、`report.privacyNotice` の文言が表示されることを確認する | ReportSheetView、`Localizable.strings` | 現在 | 未確認 |
| SEC-07-02 | 自由記述が 500 文字を超えると送信できない | `ReportSheetViewModel` のテスト(`isCommentTooLong`、`canSubmit`)が通る | ReportSheetViewModel.swift 18・41〜43 行目 | 現在 | 未確認 |
| SEC-07-03 | 報告に含める項目が、試験 ID・問題 ID・改訂番号・パックの版・理由・自由記述・アプリの版・ロケールだけである | 送信の処理(`ReportClient`)が実際に作るリクエストの本文(シリアライズしたあとの JSON)をテストで取り出し、トップレベルのキーの集合が、DDD-P5 3.3 の `POST /v1/reports` の 8 項目(`examID`・`questionID`・`questionRevision`・`packVersion`・`reason`・`comment`・`appVersion`・`locale`)と完全に一致することを確認する。キューの管理に使う `id`・`createdAt`、端末の識別子(`identifierForVendor` など)、端末名、学習履歴が本文に無いこと。ヘッダーに App Attest の鍵 ID と assertion が付いていること(鍵 ID は SEC-06-08 の例外として扱う)。ヘッダーと本文のどちらにも、端末の識別子・端末名・学習履歴が無いこと。P5 までは、前段の確認として、`PendingReport` のプロパティ(上記の項目と `id`・`createdAt`)と `reportMetadata` が返す値を目視し、`id` が報告ごとにランダムに作るキューのレコードの ID であることを確かめる(これだけでは適合としない) | ReportQueueStore.swift、AppEnvironment.swift 69〜73 行目、P5 の `ReportClient` | 現在(前段)・P5 | 未確認 |
| SEC-07-04 | 未送信の報告を iCloud に同期しない | `ReportQueueContainerFactory` が `cloudKitDatabase: .none` を指定していること。`ReportQueueTests` が通る | ReportQueueStore.swift 38〜45 行目 | 現在 | 未確認 |
| SEC-07-05 | 送信に成功した報告と、利用者が削除を選んだ報告を、端末から消す | `ReportSender` のテスト(P5-S06)と、SEC-04-08・SEC-04-09 | P5-S06 | P5 | 未確認 |
| SEC-07-06 | report-api が、App Attest の assertion を検証する。assertion は、リクエスト本文の SHA-256 と challenge に対するものである | 契約テスト(本文を書き換えたリクエスト、別の鍵の assertion が 401 になる) | DDD-P5 3.3、P5-S04 | P5 | 未確認 |
| SEC-07-07 | challenge は使い捨てで、有効期限が 5 分である。同じ assertion の再送を拒否する(カウンターの確認を含む) | 契約テスト(期限切れ、使用済みの challenge、カウンターが進んでいない assertion が拒否される) | DDD-P5 3.3 | P5 | 未確認 |
| SEC-07-08 | レート制限(鍵 ID のハッシュごとに 1 時間 20 件)が働く。未登録の端末による `/v1/challenge` と `/v1/devices` の大量呼び出しにも制限がある | `rate_limit`、`rate_window` のテストが通る。登録前のエンドポイントの制限を確認する | P5-S04、P5-S05 | P5 | 未確認 |
| SEC-07-09 | テスト用の検証器(App Attest の差し替え)が、ステージングと本番で無効である。有効な設定では起動しない | ステージングの設定と本番の設定のそれぞれで、差し替えを有効にして起動し、どちらも起動に失敗することを確認する | P5-S04 | P5 | 未確認 |
| SEC-07-10 | 入力を検証する(ID は Schema と同じ形式、自由記述は 500 文字以内、未知のキーは 400、本文の大きさに上限) | 契約テストが通る。大きい本文を送って 413 または 400 になること | DDD-P5 3.3 | P5 | 未確認 |
| SEC-07-11 | 保存の前に、メールアドレスと電話番号の形式を `[redacted]` に置き換える | `redact_email`、`redact_phone`、`redacts_contact_info` のテストが通る | P5-S05 | P5 | 未確認 |
| SEC-07-12 | 報告を受け付けてから 180 日を過ぎたら削除する(`expireAt` と Firestore の TTL ポリシー)。Firestore の TTL による削除は非同期で、期限を過ぎてから実際に消えるまでに遅れ(通常 24 時間以内、それを超えることもある)があるため、保存期間の約束は「180 日を過ぎたあと、TTL の削除の遅れの範囲内に消える」とし、利用者への表示もこれに合わせる。遅れを許さない場合は、期限を過ぎた報告を読み取り・集計の対象から外す | `sets_ttl` のテストが通る(`expireAt` = 受付時刻 + 180 日)。ステージングの Firestore で TTL ポリシーが `expireAt` に対して有効(状態が `ACTIVE`)であること。加えて、ステージングで `expireAt` を過去の時刻にした報告を書き込み、一定時間(例: 72 時間)以内に、その報告が削除されたことを確認して記録する。確認は、その報告のドキュメント ID での取得で存在しないこと、またはその報告を特定できる削除のログのどちらかで行う。TTL の削除の件数などの集計の指標だけでは、その報告が削除された証拠にしない | P5-S05、P5-S07 | P5 | 未確認 |
| SEC-07-13 | 報告を読めるのがコンテンツの担当者だけである。Firestore にクライアントから直接アクセスできない | Firestore の IAM とセキュリティルール(全拒否)を確認する | P5-S07 | リリース前 | 未確認 |

## 3. 事前調査で把握した現状

- 報告シートは実装済みで(P4-S15)、報告は端末の送信キューに保存する。送信(`ReportSending`)は P5 で実装し、P4 では未設定である。
- 自由記述の上限は `commentLimit = 500` で、超えると `canSubmit` が `false` になる。保存の前に前後の空白を取り除く。
- 注意書きの文言は「氏名・メールアドレスなどの個人情報は書かないでください」(`report.privacyNotice`)である。
- 送信キューは、学習履歴と別のストア(`ReportQueue.store`)で、CloudKit を使わない。理由は、同期すると端末ごとに同じ報告を送り、自由記述も iCloud に複製されるためである。
- `reportMetadata` は、アプリの版(`CFBundleShortVersionString`)とロケール(BCP 47)だけを返す。
- report-api(`server/report-api/`)はまだ無い。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | report-api の実装言語(TBD-07) | P5 の着手前 |
| 2 | App Attest が使えない環境(シミュレータ、対応していない端末)での扱い。報告を送らないのか、別の制限で受け付けるのか | P5-S04 |
| 3 | 置き換えの対象を、メールアドレスと電話番号以外(氏名、住所、URL)に広げるか | P5-S05 |
| 4 | 端末のキューに残す件数と期間の上限(送信できない状態が続いた場合) | P5-S06 |
