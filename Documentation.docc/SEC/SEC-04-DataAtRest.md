# SEC-04 端末内データの保護(保存・エクスポート・削除)

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [セキュリティ確認項目書(索引)](../SEC.md) |
| 対応要件 | NFR-09、BDD 8.2(学習データ)、BDD 8.3(データの削除)、FR-ACCT-03、[DDD-P3](../DDD/DDD-P3-Persistence.md) |
| 対象 | [ModelContainerFactory.swift](../../packages/Data/Sources/Persistence/ModelContainerFactory.swift)、[ReportQueueStore.swift](../../packages/Data/Sources/Persistence/ReportQueueStore.swift)、[PackStore.swift](../../packages/Data/Sources/ContentKit/PackStore.swift)、[SettingsViewModel.swift](../../packages/Presentation/Sources/SettingsFeature/SettingsViewModel.swift) |

---

## 1. 守るものと想定する脅威

守るものは、端末に保存する学習履歴・設定・未送信の誤り報告である。

- 端末を紛失したとき、ロック中の端末からデータを読まれる。
- エクスポートしたファイルが、一時ディレクトリや共有先に残り続ける。
- 「削除」を実行したのに、一部のデータ(未送信の報告、一時ファイル、iCloud 上の記録)が残る。

## 2. 確認項目

| ID | 確認項目 | 確認方法 | 対象 | 時期 | 結果 |
|---|---|---|---|---|---|
| SEC-04-01 | 学習履歴のストア(`StudyHistory.store`)の Data Protection クラスが、BDD 8.2 の `completeUntilFirstUserAuthentication` 以上である | 実機で、ストアのファイルの `NSFileProtectionKey` を確認する。entitlements の `com.apple.developer.default-data-protection` の値を確認する | ModelContainerFactory.swift、entitlements | リリース前 | 未確認 |
| SEC-04-02 | 誤り報告のキュー(`ReportQueue.store`)と、パックの保存先(`Content/`)にも同じ保護がかかる | SEC-04-01 と同じ方法で、3 つの保存先すべてを確認する | ReportQueueStore.swift、PackStore.swift | リリース前 | 未確認 |
| SEC-04-03 | App Group のコンテナを共有するのが、このアプリ(と将来のウィジェット)だけである | entitlements の App Group と、同じグループを使うターゲットの一覧を確認する | entitlements | リリース前 | 未確認 |
| SEC-04-04 | 端末のバックアップに含めるデータの範囲を決め、そのとおりになっている(学習履歴は含める、再取得できるパックは含めない、など) | 保存先ごとに `isExcludedFromBackup` の値を確認し、方針と比べる | 保存先の 3 か所 | リリース前 | 未確認 |
| SEC-04-05 | エクスポートに含まれる項目が、学習データと設定だけである。未送信の誤り報告の自由記述や、端末を識別する値を含まない | `DataManagementTests` のエクスポートのテストと、書き出した JSON のキーの一覧を確認する | DataManagement、DDD-P3 | 現在 | 未確認 |
| SEC-04-06 | エクスポートのファイルを、共有の完了後・設定画面を閉じたとき・次回の起動時のいずれかで削除する | エクスポート → 共有 → アプリの再起動のあと、`tmp/` に `cloudrill-export-*.json` が残っていないことを確認する | SettingsViewModel.swift `exportData()` | 現在 | 未確認 |
| SEC-04-07 | エクスポートのファイルが平文の JSON であることを、利用者に伝えている(共有先の選択は利用者の責任になる) | 設定画面の文言を確認する | SettingsView.swift | 現在 | 未確認 |
| SEC-04-08 | 全体の削除で、学習履歴・設定・未送信の誤り報告・削除の時点で残っているエクスポートのファイル(SEC-04-06 の削除を待っているもの)がすべて消える | `SettingsViewModel` の削除処理が `dataManagement.deleteAll` と `reports.removeAll` を呼び、未削除のエクスポートのファイルも消すことを目視する。削除後に両方のストアが空であることをテストで確認する。エクスポートしてから、SEC-04-06 の削除が動く前(共有の完了前・画面を閉じる前・再起動の前)に全体の削除を実行し、`tmp/` に `cloudrill-export-*.json` が残らないことをテストで確認する | SettingsViewModel.swift 162〜163 行目、`exportData()` | 現在 | 未確認 |
| SEC-04-09 | 試験を指定した削除で、ほかの試験のデータと `UserSettings` が残り、指定した試験のデータ(未送信の報告を含む)だけが消える | `DataManagementTests`、`ReportQueueTests` の該当するテストが通る | DataManagement、SwiftDataReportQueue | 現在 | 未確認 |
| SEC-04-10 | 削除の途中で失敗したとき、利用者に失敗を伝え、「削除済み」と表示しない | 片方のリポジトリを失敗させる Fake でテストし、エラー表示になることを確認する | SettingsViewModel.swift | 現在 | 未確認 |

## 3. 事前調査で把握した現状

- 保存先は 3 か所ある。学習履歴(`StudyHistory.store`)、誤り報告のキュー(`ReportQueue.store`)、パック(`Content/`)。Release では App Group の URL の下に置く。
- Data Protection クラスを明示的に指定しているコードは見当たらない。entitlements ファイルもまだ無い。指定しなければ iOS の既定値(初回のロック解除まで保護)になるが、BDD 8.2 の指定どおりかは実機で確認する必要がある。
- `isExcludedFromBackup` を設定しているコードは見当たらない。
- エクスポートは、全試験のデータを平文の JSON にして `FileManager.default.temporaryDirectory` に書き、`ShareLink` に渡す。書き出したファイルを削除する処理は見当たらない(SEC-04-06)。全体の削除も、エクスポートのファイルを消さない(SEC-04-08)。
- 削除は、学習履歴(`deleteAll`)と誤り報告のキュー(`removeAll`)の両方を呼んでいる。
- 現在は `cloudKitContainer: nil` で、CloudKit との同期は無効である(SEC-12)。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | Data Protection クラスを entitlements で指定するか、ファイルごとに指定するか。バックグラウンドでの更新確認(P5)やウィジェット(P6-S13)がロック中に読む必要があるかで決まる | P5 の着手前 |
| 2 | バックアップに含める範囲(SEC-04-04) | リリース前 |
| 3 | エクスポートのファイルを削除するタイミング(SEC-04-06) | リリース前 |
