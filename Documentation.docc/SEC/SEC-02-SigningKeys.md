# SEC-02 署名鍵の管理とローテーション

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [セキュリティ確認項目書(索引)](../SEC.md) |
| 対応要件 | NFR-10、BDD 7.1、BDD 8.2(秘密情報)、[DDD-P2](../DDD/DDD-P2-ContentPack.md) 3.3、[DDD-P5](../DDD/DDD-P5-Delivery.md) P5-S01・5 章 |
| 対象 | [PublicKeyRing.swift](../../packages/Data/Sources/ContentKit/PublicKeyRing.swift)、[sign.py](../../content/scripts/contentpack/sign.py)、[testing.py](../../content/scripts/contentpack/testing.py)、`content/scripts/sign_manifest.py` |

---

## 1. 守るものと想定する脅威

守るものは、本番の署名鍵(Ed25519 の秘密鍵)と、アプリが信頼する公開鍵の一覧である。

- 本番の秘密鍵が、リポジトリ・CI のログ・開発者の端末から漏れる。
- テスト用の鍵で署名したパックを、本番のアプリが受け入れる。テスト用の鍵は公開されている文字列から誰でも再計算できる。
- 鍵が漏れたときに、信頼を取り消す手段がない。

## 2. 確認項目

| ID | 確認項目 | 確認方法 | 対象 | 時期 | 結果 |
|---|---|---|---|---|---|
| SEC-02-01 | 本番の秘密鍵は Secret Manager にだけ置き、リリース用のサービスアカウントだけが読める | 署名鍵のシークレットに対して、`secretmanager.versions.access` の権限を実際に持つ主体を確認する。シークレット自体の IAM ポリシーに加え、プロジェクト・フォルダ・組織から継承するポリシーと、この権限を含むカスタムロール・基本ロール(`roles/owner`、`roles/editor`)も対象にする(例: Policy Analyzer の `gcloud asset analyze-iam-policy --organization=<組織 ID> --full-resource-name=<シークレット> --permissions=secretmanager.versions.access`。継承する許可を含めるため、範囲は組織にする)。権限を持つのがリリース用のサービスアカウントだけであること。あわせて、リリース用のサービスアカウントになりすませる主体(そのサービスアカウントに対して `iam.serviceAccounts.getAccessToken`・`iam.serviceAccounts.signJwt`・`iam.serviceAccounts.signBlob` のいずれかを持つ主体。例: `gcloud asset analyze-iam-policy --organization=<組織 ID> --full-resource-name=<サービスアカウント> --permissions=iam.serviceAccounts.getAccessToken,iam.serviceAccounts.signJwt,iam.serviceAccounts.signBlob`。継承するポリシーとロールも対象。または、シークレットの分析に `--analyze-service-account-impersonation` を付け、なりすましを経由してアクセスできる主体も含めて確認する)を確認し、承認された主体(リリースのワークフローなど)だけに限られていること。あわせて、リリース用のサービスアカウントをワークロードに割り当てて、その権限で動かせる主体も確認する。そのサービスアカウントに対して `iam.serviceAccounts.actAs` を持つ主体(例: `gcloud asset analyze-iam-policy --organization=<組織 ID> --full-resource-name=<サービスアカウント> --permissions=iam.serviceAccounts.actAs`。継承するポリシーとロールも対象)を洗い出し、そのうちサービスアカウントを指定してワークロードを作成・更新・実行できる権限(Cloud Run のサービスとジョブの作成・更新・実行、Cloud Build のビルドの作成、Compute Engine のインスタンスの作成、Cloud Functions の関数の作成・更新など、プロジェクトで有効なサービスのもの)も持つ主体を確認する。両方を持ち、割り当てたワークロードから署名鍵のシークレットを読めるのが、承認された主体だけであること。さらに、サービスアカウントの鍵も、リリース用のサービスアカウントとして認証する別の経路なので確認する。鍵を作れる・登録できる主体(そのサービスアカウントに対して `iam.serviceAccountKeys.create`・`iam.serviceAccountKeys.upload` を持つ主体。例: `gcloud asset analyze-iam-policy --organization=<組織 ID> --full-resource-name=<サービスアカウント> --permissions=iam.serviceAccountKeys.create,iam.serviceAccountKeys.upload`。継承するポリシーとロールも対象)が承認された主体だけであるか、組織のポリシーで、このプロジェクトでの鍵の作成と登録の両方が無効になっていること。組織のポリシーは、マネージドの制約の組(`iam.managed.disableServiceAccountKeyCreation` と `iam.managed.disableServiceAccountKeyUpload` の両方)、または同等の従来の制約の組(`iam.disableServiceAccountKeyCreation` と `iam.disableServiceAccountKeyUpload` の両方)のどちらかとし、組の各制約について `gcloud org-policies describe <制約> --project=<プロジェクト> --effective` で実効の値を確認する。作成の制約だけでは足りない。組織のポリシーは新しい鍵を防ぐ追加の対策であり、既存の鍵の確認の代わりにはならない。どちらの場合も、既存のユーザー管理の鍵(`gcloud iam service-accounts keys list --iam-account=<サービスアカウント> --managed-by=user`)を必ず確認し、鍵が無いか、あれば保管場所・管理者・期限が決まっていること。最後に、これらの許可そのものを書き換えられる主体を確認する。IAM ポリシーを変更できる主体は、自分にシークレットの読み取りやなりすましの権限を付けられるためである。署名鍵のシークレットに対して `secretmanager.secrets.setIamPolicy`、リリース用のサービスアカウントに対して `iam.serviceAccounts.setIamPolicy`、上位のスコープに対して `resourcemanager.projects.setIamPolicy`・`resourcemanager.folders.setIamPolicy`・`resourcemanager.organizations.setIamPolicy` を持つ主体を洗い出す(例: `gcloud asset analyze-iam-policy --organization=<組織 ID> --full-resource-name=<シークレット> --permissions=secretmanager.secrets.setIamPolicy`。サービスアカウント・プロジェクト・フォルダ・組織にも同様に行う。継承するポリシーとロールも対象)。組織のポリシーで鍵を無効にしている場合は、その制約を変えられる主体(`orgpolicy.policy.set`)も対象にする。これらの権限を持つのが、承認された管理者だけであること | DDD-P5 P5-S07 | リリース前 | 未確認 |
| SEC-02-02 | ステージングと本番で別の鍵を使う。鍵 ID も別にする | 両環境のシークレットと、それぞれの `manifest.json` の `keyID` を比べる | DDD-P5 P5-S01 | P5 | 未確認 |
| SEC-02-03 | 署名ツールは、秘密鍵を環境変数から受け取り、ファイル・標準出力・例外のメッセージに出さない | `sign_manifest.py` の `--key-env` の処理と、`SigningError` のメッセージを目視する。わざと不正な鍵を渡し、出力に鍵の内容が含まれないことを確認する | sign_manifest.py、sign.py | 現在 | 未確認 |
| SEC-02-04 | テスト用の鍵(`--test-key`)は、テストと fixture の生成でだけ使える。リリースのワークフローから呼べない | `content-release.yml` に `--test-key` が無いこと。`build_pack.py` と `sign_manifest.py` が、本番の鍵 ID とテスト用の鍵の組み合わせを拒否するかを確認する | sign_manifest.py、P5-S01 | P5 | 未確認 |
| SEC-02-05 | アプリの本番用の鍵リングには本番の公開鍵だけが入り、テスト用の公開鍵(`test-keys.json`)が入らない。秘密鍵は一切入らない | Release ビルドで実際に有効になる鍵リング(バンドルのファイルから読む鍵と、コードに埋め込んだ鍵の両方)の鍵 ID と公開鍵を取り出し、承認済みの本番鍵の一覧(許可リスト)と完全に一致することを確認する。ファイルの有無だけでは判断しない(テスト用の鍵がコードの定数や別名のファイルで入る場合を見逃すため)。あわせて、`.app` の全ファイル(実行ファイルを含む)に秘密鍵が含まれないことを確認する(例: `grep -r -l -a -e 'PRIVATE KEY' <.app>`、テスト用の seed の接頭辞 `examprep-test-key:` の検索)。さらに、本番の署名鍵の seed(32 バイト)そのものが `.app` の全ファイルに含まれないことを、生のバイト列と、埋め込まれうる符号化の形(Base64 の標準形・URL 安全形、パディングの有無、前後のデータとの位置のずれ 3 通り。16 進の小文字・大文字。PKCS#8 の DER・PEM)で確認する。確認は検査用のスクリプトで行い、seed は Secret Manager から環境変数で受け取って、コマンドの引数・ファイル・ログに書かない。出力は一致したファイルのパスと形式の名前だけにし、seed や符号化した値、一致した前後のバイト列を出さない | アプリのバンドル | リリース前 | 未確認 |
| SEC-02-06 | 鍵リングの読み込みが、空の ID・長さの違う鍵・正規形でない Base64 を拒否する | `loadsTestKeys`、`rejectsInvalidKey` が通る | PublicKeyRing.swift | 現在 | 未確認 |
| SEC-02-07 | ローテーションの手順(①新しい公開鍵を入れたアプリを出す → ②新しい鍵で署名を始める → ③古い鍵を外す)を、ステージングで 1 回通す | ②を始める前に、鍵 A だけを持つアプリの扱いを決めて手順に書く。扱いは、更新を求める(`minAppVersion` で B の公開鍵を持つ版以上を求める、など)、サポートの対象外とする、のどちらかとする。どちらも採らない場合は、A だけを持つアプリが新しいパックを受け取れず、それまでのパックで動き続けることを、受け入れる影響として明記する。次の 3 つを、それぞれ必須の確認として行う。(1) 鍵 A と B の両方を持つアプリが、A の署名のパックと B の署名のパックをどちらも受け入れる。(2) 最終形の B だけを持つアプリが、B の署名のパックを受け入れ、A の署名のパックを拒否する。(3) 鍵 A だけを持つアプリに B の署名のパックを配信し、決めた扱いのとおりに動く(更新を求める表示が出る、または B の署名のパックを拒否して、それまでのパックで動き続ける。どちらの場合も、学習データを失わず、アプリが止まらない) | DDD-P2 3.3 | P5 | 未確認 |
| SEC-02-08 | 鍵が漏れたときの手順が文書になっている(鍵の無効化、新しい鍵での再署名、古い鍵を外したアプリのリリース、古いアプリへの影響) | 手順書があり、所要時間と担当が書かれていること | 未作成 | リリース前 | 未確認 |
| SEC-02-09 | 鍵の生成と Secret Manager への登録を、秘密鍵が端末やシェルの履歴に残らない方法で行う | 手順書に書かれた生成と登録のコマンドを確認し、seed が漏れる経路が無いことを確かめる。seed がコマンドの引数・シェルの履歴・ログに現れないこと(例: 標準入力やパイプで Secret Manager に渡し、`--data-file=-` などで受け取る)。seed を永続するファイルやクリップボードに残さないこと。一時的な複製を作る場合は、作る場所(メモリ上のファイルシステムなど)と、使い終えたあとの削除の手順が書かれていること。生成場所が決まっていること | 未作成 | リリース前 | 未確認 |

## 3. 事前調査で把握した現状

- 署名は Ed25519 で、対象は `manifest.json` のバイト列そのものである。
- テスト用の鍵は `SHA-256("examprep-test-key:" + label)` を seed にして作る。seed の作り方はリポジトリに書かれているので、テスト用の秘密鍵は誰でも再計算できる。秘密鍵をファイルに保存しないのは、コミットを避けるためであって、秘匿のためではない。
- `PublicKeyRing` は公開鍵だけを扱い、複数の鍵を持てる。
- 本番用の鍵リングをアプリに埋め込む仕組みは、まだ実装されていない。`ExamPrepApp/Resources/Packs/test-keys.json` はテスト用の公開鍵である。
- 追跡対象のファイルに、秘密鍵の PEM 形式の文字列は無い(`git grep` で確認。履歴は未確認。SEC-09-08)。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | 本番用の鍵リングを置く場所(バンドルのリソースか、コードの定数か)と、Release ビルドでテスト用の鍵を除く方法 | P5 の着手前 |
| 2 | 鍵の失効の方法。今の設計では、古い鍵を外したアプリをリリースする以外に取り消す手段がない。カタログに失効した鍵 ID を載せる方法を採るかを決める | P5 の着手前 |
| 3 | ローテーションの頻度と、「十分に普及した」と判断する基準 | リリース前 |
