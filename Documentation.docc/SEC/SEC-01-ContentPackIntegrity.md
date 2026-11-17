# SEC-01 パックの完全性(署名・ハッシュ・版戻し・パス)

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [セキュリティ確認項目書(索引)](../SEC.md) |
| 対応要件 | NFR-10、AC-05、BDD 6.8、BDD 8.2、E-02、[DDD-P2](../DDD/DDD-P2-ContentPack.md) 3.1・3.3・P2-S05 |
| 対象 | [PackVerifier.swift](../../packages/Data/Sources/ContentKit/PackVerifier.swift)、[PackStore.swift](../../packages/Data/Sources/ContentKit/PackStore.swift)、[verify.py](../../content/scripts/contentpack/verify.py)、[契約 fixture](../../content/tests/fixtures/packs/tampered/expected.json) |

---

## 1. 守るものと想定する脅威

守るものは、利用者に表示する問題・解説の正しさである。

- 配信経路や CDN で、パックの一部または全部が差し替えられる。
- 正しく署名された古い版を再配信し、修正済みの誤りを復活させる(版戻し)。
- manifest のパスを細工して、パックのディレクトリの外にあるファイルを読ませる、または書かせる。
- インストール後に、端末の保存先でファイルを書き換える。

## 2. 確認項目

| ID | 確認項目 | 確認方法 | 対象 | 時期 | 結果 |
|---|---|---|---|---|---|
| SEC-01-01 | 署名の確認が済むまで、manifest の JSON を解析しない | `swift test --package-path packages/Data --filter PackVerifierTests` の `signatureCheckedBeforeDecode` が通る。`verify()` の先頭が `checkSignature` であることを目視する | PackVerifier.swift、verify.py | 現在 | 未確認 |
| SEC-01-02 | 改ざんした 9 種類のパックを、Python と Swift が同じエラーで拒否する | `tamperedPacks`(Swift)と `(cd content && .venv/bin/pytest tests/test_sign.py tests/test_generated.py)` が通る。`tampered/expected.json` の `error` が両方で使われていることを確認する | 契約 fixture | 現在 | 未確認 |
| SEC-01-03 | 署名が鍵リングのどれかで検証でき、かつ manifest の `keyID` がその鍵の ID と一致する場合だけ受け入れる | `unknown-key` の fixture が拒否されること、`verifiedIDs.contains(manifest.keyID)` の分岐を目視する | PackVerifier.swift 30 行目、verify.py `_decode` | 現在 | 未確認 |
| SEC-01-04 | 署名・公開鍵の Base64 は正規形だけを受け入れる(長さ 64 バイト・32 バイト、再エンコードして一致) | `rejectsInvalidKey` と `bad-signature` の fixture が通る。改行つきの `manifest.sig` を手で作り、拒否されることを確認する | PackVerifier.swift、PublicKeyRing.swift | 現在 | 未確認 |
| SEC-01-05 | manifest の全ファイルについて、存在・サイズ・SHA-256 を確認する | `hash-mismatch`、`size-mismatch`、`missing-file` の fixture が拒否される | `checkFiles` | 現在 | 未確認 |
| SEC-01-06 | `PackLoader.load` が読むファイル(`PackLoader.loadedFiles`)は、すべて manifest に載っていてハッシュを検証される。載っていない manifest は、署名が正しくても `fileMissing` で拒否する。manifest に載っていない余分なファイルは、読まれないので許容する | `PackVerifierTests` の `unlistedLoadedFileIsRejected`(5 ファイルそれぞれを外して署名し直す)、`modifiedUnlistedLoadedFileIsRejected`(外した `exam.json` を書き換える)、`extraUnlistedFileIsAccepted`(余分なファイルを `verify` が通し、`PackLoader` が読まない)が成功すること | PackVerifier.swift、PackLoader.swift | 現在 | 未確認 |
| SEC-01-07 | 現在の版以下のパックを拒否する(build metadata だけが違う版も含む) | `notNewerIsRejected`(`1.0.0`、`1.1.0`、`1.0.0+build`)が通る | `checkVersions` | 現在 | 未確認 |
| SEC-01-08 | パスの規則(絶対パス・`..`・許可外の文字の拒否)が、Schema・Python・Swift で一致している | `manifest.schema.json` の `FileEntry.path` の正規表現と、`checkPath` の正規表現を比べる。`path-traversal` の fixture が拒否される | manifest.schema.json、`checkPath` | 現在 | 未確認 |
| SEC-01-09 | パックの中のシンボリックリンクを拒否する(ファイルと途中のディレクトリの両方) | `symlinkIsRejected`(`exam.json`、`questions`)が通る | `checkPath` | 現在 | 未確認 |
| SEC-01-10 | `PackStore` が、試験 ID・版・staging の形式とシンボリックリンクを確認してから移動・削除する | `examPath`、`install`、`garbageCollect` の確認を目視する。試験 ID に `../x`、版に `1.0.0/..`、staging にシンボリックリンクを渡すテストがあることを確認する(無ければ追加する) | PackStore.swift、PackStoreTests.swift | 現在 | 未確認 |
| SEC-01-11 | 差分更新で、ファイルの取得より前に署名を確認し、全ファイルがそろってから `PackVerifier.verify` と `ContentIntegrityChecker.check` を通して `install` する | P5-S03 の `PackUpdater` のテストと、P5-S08 の手順 3(改ざんしたパックがインストールされない)の記録 | DDD-P5 3.2 | P5 | 未確認 |
| SEC-01-12 | 検証に失敗したら staging を削除し、現在の版を使い続ける(E-02) | P5-S03 のテストで、失敗後に `staging/` が空で、`state.json` の `current` が変わっていないことを確認する | DDD-P5 3.2 | P5 | 未確認 |

## 3. 事前調査で把握した現状

- `PackVerifier.verify` は「署名 → デコード → 版・試験 → ファイル」の順で確認する。`verify.py` も同じ順序である。
- `PackVerifier.verify` は、ファイルの確認の最初に、`PackLoader.loadedFiles` がすべて manifest に載っていることを確認する(2026-11-17 に追加)。`verify.py` にはこの確認がない。`build_pack.py` が常にこれらのファイルを載せるため実害はないが、Python と Swift の検証の範囲が異なる。
- 改ざんの fixture は 9 種類ある(`app-too-old`、`bad-signature`、`exam-mismatch`、`hash-mismatch`、`missing-file`、`path-traversal`、`size-mismatch`、`unknown-key`、`unsupported-format`)。版戻しとシンボリックリンクは fixture ではなく、`PackVerifierTests` の個別のテストで扱っている。
- 起動時の `ContentBootstrapper` は、署名と本文のハッシュを再検証しない。manifest・試験定義・ベンダーの一致と、索引の整合だけを確認する(起動時間 NFR-01 のため)。
- `PackStore.installBundled` は、同梱版を複製するときに manifest の試験 ID と版の一致だけを確認し、署名は確認しない。
- `PackStoreTests.swift` には「symlink」を含むテストが見当たらない(SEC-01-10 で確認する)。
- アプリの起動処理(`AppEnvironment.make`)は、まだ `PackVerifier` を使っていない。同梱パックは署名を確認せずに読み込む。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | インストール後の保存先(App Group)での改ざんを脅威に含めるか。含めるなら、起動時または一定間隔での再検証の方法を決める。含めないなら、理由(アプリのサンドボックスと Data Protection で守られる)を BDD 8.2 に書く | P5 の着手前 |
| 2 | 同梱パックの署名を、ビルド時・起動時・`pin` の複製時のどこで確認するか。アプリ本体のコード署名で守られるため不要とするなら、その判断を記録する | P5 の着手前 |
| 3 | manifest に載っていないファイルの扱い。`PackLoader` が読むファイルは拒否し、読まれない余分なファイルは許容することにした(SEC-01-06)。残る論点は、`verify.py` に同じ確認を足して Python と Swift の範囲をそろえるか | P5-S03 |
| 4 | パックとファイルのサイズの上限(SEC-05-08 と同じ) | P5-S03 |
