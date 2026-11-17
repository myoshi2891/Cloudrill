# SEC-06 通信(ATS・HTTPS・更新の取得)

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [セキュリティ確認項目書(索引)](../SEC.md) |
| 対応要件 | NFR-03、NFR-09、BDD 6.8、BDD 7.1、BDD 8.2(通信)、E-03、[DDD-P5](../DDD/DDD-P5-Delivery.md) 3.2・P5-S03・P5-S06 |
| 対象 | `ExamPrepApp.xcodeproj/project.pbxproj`(Info.plist の設定)、P5 で作る `Networking`(`HTTPClient`、`PackUpdater`、`ReportClient`) |

---

## 1. 守るものと想定する脅威

守るものは、アプリとサーバーの間の通信の秘匿性と、通信先の正しさである。パックの内容そのものは署名で守る(SEC-01)。

- 平文の HTTP で通信し、内容を読まれる、または書き換えられる。
- 設定やカタログの値で、想定していないホストへ接続させられる。
- 通信の失敗や遅延で、学習機能が使えなくなる。

## 2. 確認項目

| ID | 確認項目 | 確認方法 | 対象 | 時期 | 結果 |
|---|---|---|---|---|---|
| SEC-06-01 | P4 までのアプリが、ネットワークに接続しない(外部リンクを利用者が開く場合を除く) | `grep -rn -E 'URLSession\|URLRequest\|NWConnection' packages/*/Sources ExamPrepApp` が何も出さない。`OfflineUITests` が通る | アプリ全体 | 現在 | 未確認 |
| SEC-06-02 | Info.plist に ATS の例外(`NSAppTransportSecurity`、`NSAllowsArbitraryLoads`、ドメインごとの例外)が無い | `grep -n NSAppTransportSecurity ExamPrepApp.xcodeproj/project.pbxproj` が何も出さない。Release ビルドの Info.plist を確認する | project.pbxproj | 現在 | 未確認 |
| SEC-06-03 | 配信と報告の接続先が https で、ホストが固定されている。カタログや manifest の値でホストを変えられない | `PackUpdater` と `ReportClient` が、基底 URL をビルド時の設定から取り、パスだけを組み立てることを確認する。パスの値(試験 ID・版・ファイルのパス)を形式で確認すること | P5-S03、P5-S06 | P5 | 未確認 |
| SEC-06-04 | リダイレクトで https 以外や別のホストへ移らない | 接続先を 302 で `http://` と別ホストへ向ける Fake でテストし、たどらないことを確認する | P5-S03 | P5 | 未確認 |
| SEC-06-05 | 取得する応答の大きさと時間に上限がある。超えたら中止し、現在の版を使い続ける(E-03) | 大きい応答・遅い応答の Fake でテストする | P5-S03 | P5 | 未確認 |
| SEC-06-06 | カタログ(`catalog.json`)が書き換えられても、被害が「更新が届かない」までに収まる。版戻し・別の試験への差し替え・`minAppVersion` の偽装ができない | 細工したカタログ(古い版を指す、別の試験の manifest を指す)でテストし、`notNewer`・`examMismatch` で拒否されることを確認する。さらに、`minAppVersion` を書き換えたカタログ(実際より低い値)でテストし、`PackUpdater` がカタログの値ではなく、署名済みの manifest の `minAppVersion` と比べて `appTooOld` で拒否することを確認する | P5-S03、SEC-01-07 | P5 | 未確認 |
| SEC-06-07 | 証明書のピン留めをしない判断と、その理由(内容は署名で守る。報告は TLS と App Attest で守る)が設計書に書かれている | BDD 8.2 または DDD-P5 に記述があること | BDD 8.2 | P5 | 未確認 |
| SEC-06-08 | 通信に、端末や利用者を識別する値(広告 ID、端末名、独自の ID)を付けない。`User-Agent` は既定のままか、アプリの版までにする | `HTTPClient` のヘッダーを確認する。ステージングで受けたリクエストのヘッダーを記録する | P5-S03、P5-S06 | P5 | 未確認 |

## 3. 事前調査で把握した現状

- アプリのソース(`packages/*/Sources`、`ExamPrepApp`)に、`URLSession`・`URLRequest`・`NWConnection` を使うコードは無い。外部に出るのは、利用者が参照リンク(`Link`)をタップして、ブラウザで開く場合だけである。
- Info.plist は自動生成(`GENERATE_INFOPLIST_FILE = YES`)で、`NSAppTransportSecurity` の設定は無い。
- 配信の設計(DDD-P5 3.2)では、manifest と署名を取得して検証してから、ファイルを取得する。
- カタログ(`catalog.json`)には署名が無い。manifest の署名と版・試験の確認で守る設計である(SEC-06-06 で確認する)。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | カタログに署名を付けるか。付けない場合、攻撃者が古いカタログを返し続けて更新を止める攻撃(凍結)を許容する理由を書く | P5 の着手前 |
| 2 | 応答の大きさ・時間の上限値 | P5-S03 |
