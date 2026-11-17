# SEC-03 開発・テスト用機能の本番混入防止

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [セキュリティ確認項目書(索引)](../SEC.md) |
| 対応要件 | NFR-10、BDD 8.2、[DDD-P4](../DDD/DDD-P4-AppMVP.md) の起動構成 |
| 対象 | [AppEnvironment.swift](../../packages/AppComposition/Sources/AppComposition/AppEnvironment.swift)、[AppRootView.swift](../../packages/AppComposition/Sources/AppComposition/AppRootView.swift)、[UITestingConfiguration.swift](../../packages/AppComposition/Sources/AppComposition/UITestingConfiguration.swift)、`ExamPrepApp/Resources/Packs/`、[bundle_packs.py](../../scripts/bundle_packs.py) |

---

## 1. 守るものと想定する脅威

守るものは、本番のアプリの挙動である。

- 開発用のパック(テスト用の鍵で署名したもの)が、本番のアプリに同梱される。
- 起動引数で、保存先・時刻・コンテンツを差し替える経路が本番に残る。
- 仮のバンドル ID や開発用の保存先のまま、ストアに提出する。

## 2. 確認項目

| ID | 確認項目 | 確認方法 | 対象 | 時期 | 結果 |
|---|---|---|---|---|---|
| SEC-03-01 | `uiTesting`・`development` の構成と `UITestingConfiguration` が、Release ビルドに含まれない | `swift build --package-path packages/AppComposition -c release` が通る(`app-test.yml` の該当ステップ)。Release のバイナリに `-ui-testing`、`-store-path` の文字列が無いことを `strings` で確認する | AppEnvironment.swift、UITestingConfiguration.swift | 現在 | 未確認 |
| SEC-03-02 | Release ビルドは、起動引数(`-ui-testing`、`-store-path`、`-fixed-now`、`-content-fixture`、`-network`)を無視する | `AppRootView` の `#else` の分岐が `arguments` を参照していないことを目視する。Release ビルドを引数つきで起動し、挙動が変わらないことを確認する | AppRootView.swift | リリース前 | 未確認 |
| SEC-03-03 | `live` は、同梱パックに `development.json` があると起動を拒否する | AppComposition のテスト(`developmentContentNotAllowed` を期待するもの)が通る | AppEnvironment.swift 35 行目 | 現在 | 未確認 |
| SEC-03-04 | Release 用の同梱パックに、`development.json`・`test-keys.json`・`test-alpha`・`test-beta` が無い | Release ビルドの `.app/Packs/` の一覧を確認する。同梱するのは本番の鍵で署名した `gcp-pca` だけであること | アプリのバンドル | リリース前 | 未確認 |
| SEC-03-05 | 同梱パックを Release 用に差し替える手順があり、差し替え忘れをビルドまたは CI で検知できる | 手順書または CI のステップがあること。SEC-03-03 の起動拒否だけに頼らず、ビルド時に失敗させる | 未作成 | リリース前 | 未確認 |
| SEC-03-06 | `bundle_packs.py` は `--development` を必須にし、既存の出力先を上書きしない | `--development` なしで終了コード 2、既存のディレクトリを指定して終了コード 2 になることを確認する | bundle_packs.py | 現在 | 未確認 |
| SEC-03-07 | Release の保存先は App Group の URL で、Info.plist の `CloudrillAppGroup` と entitlements の App Group が一致する。Debug の `CloudrillDevelopment` を使わない | Release ビルドの Info.plist と entitlements を比べる。実機で保存先のパスを確認する | AppRootView.swift 55 行目 | リリース前 | 未確認 |
| SEC-03-08 | バンドル ID が本番の値で、`devplaceholder` を含まない。UI テスト用のターゲットがストア提出物に入らない | `project.pbxproj` の `PRODUCT_BUNDLE_IDENTIFIER` と、アーカイブの中身を確認する | project.pbxproj | リリース前 | 未確認 |

## 3. 事前調査で把握した現状

- `AppEnvironment.uiTesting`・`development` と、`UITestingConfiguration.swift` の全体は `#if DEBUG` の中にある。`AppRootView` も、起動引数を見る処理は `#if DEBUG` の中だけである。
- `ExamPrepApp/Resources/Packs/` には、開発用のパック(`test-alpha`、`test-beta`)、`development.json`、`test-keys.json`、`catalog.json` がコミットされている。今の状態で Release ビルドを起動すると、`live` が `developmentContentNotAllowed` で失敗する(意図どおり)。
- `CloudrillAppGroup` を設定している Info.plist・xcconfig・`project.pbxproj` は見当たらない。本番の App Group ID は未定である(TBD-04)。
- アプリのターゲットのバンドル ID は `devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).…` の仮の値である。
- `UITestingConfiguration` は、未知の引数・重複した引数・相対パスの `-store-path`・形式の違う `-content-fixture` を拒否する。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 本番の App Group ID とバンドル ID(TBD-04 の `<逆ドメイン>`) | App Store 申請前 |
| 2 | Release 用の同梱パックを作って配置する手順(`bundle_packs.py` の本番版、または `build_pack.py` の出力を使う手順) | P5-S01 |
