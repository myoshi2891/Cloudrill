# SEC-09 CI/CD・依存・秘密情報

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-11-17 |
| 上位文書 | [セキュリティ確認項目書(索引)](../SEC.md) |
| 対応要件 | BDD 8.2(秘密情報)、BDD 10 章、[DDD](../DDD.md) 8 章(外部依存)、[DDD-P5](../DDD/DDD-P5-Delivery.md) 5 章 |
| 対象 | `.github/workflows/*.yml`(7 件)、[dependabot.yml](../../.github/dependabot.yml)、[pyproject.toml](../../content/pyproject.toml)、`content/uv.lock`、`Package.resolved`(3 件)、[.gitignore](../../.gitignore) |

---

## 1. 守るものと想定する脅威

守るものは、ビルドとリリースの経路、およびリポジトリに置く情報である。

- 依存するパッケージや GitHub Actions が差し替えられ、CI やアプリに不正なコードが入る。
- プルリクエストから、書き込み権限やシークレットを使われる。
- 秘密鍵・トークン・個人の情報が、リポジトリ・履歴・ログに残る。

## 2. 確認項目

| ID | 確認項目 | 確認方法 | 対象 | 時期 | 結果 |
|---|---|---|---|---|---|
| SEC-09-01 | 全ワークフローの `permissions` が最小である(今は `contents: read` だけ)。ジョブ単位の指定でも広げていない | `grep -A2 '^permissions:' .github/workflows/*.yml` で、ワークフローの既定が 7 件すべてにあることを確認する。ジョブ単位の指定はワークフローの既定を上書きするので、`grep -n -A3 -E '^\s+permissions:' .github/workflows/*.yml` で、字下げされたジョブの `permissions` もすべて確認する(`write` や `write-all` が無いこと)。リポジトリの既定の権限(Settings > Actions)が読み取り専用であること | `.github/workflows/` | 現在 | 未確認 |
| SEC-09-02 | `pull_request_target` と `workflow_run` を使わない。フォークからのプルリクエストでシークレットを使わない | `grep -n -w -e pull_request_target -e workflow_run -e secrets .github/workflows/*.yml` が何も出さない(`-w` で `secrets` を単語として探し、`secrets.TOKEN` のプロパティの形と `secrets['TOKEN']` の添字の形、`secrets: inherit` の両方を拾う) | `.github/workflows/` | 現在 | 未確認 |
| SEC-09-03 | チェックアウトで認証情報を残さない(`persist-credentials: false`) | `actions/checkout` の全 8 か所に指定があることを確認する | `.github/workflows/` | 現在 | 未確認 |
| SEC-09-04 | GitHub Actions をコミット SHA で固定する。少なくとも、シークレットや `id-token` を使うリリースのワークフローでは必ず固定する | `grep -h -o 'uses: .*' .github/workflows/*.yml` で、`@<40 桁の SHA>` になっていることを確認する | `.github/workflows/` | 現在 | 未確認 |
| SEC-09-05 | `run:` の中に、プルリクエストの題名・ブランチ名・タグ名などの外部から決められる値(`${{ github.event.* }}`、`${{ github.head_ref }}`、`${{ github.ref_name }}`、`${{ github.ref }}`、`${{ inputs.* }}` など)を直接埋め込まない。値は `env:` で渡し、シェルの変数として引用符つきで使う | `grep -n -F '${{' .github/workflows/*.yml` で全ての式を洗い出し、`run:` のブロックの中にある式を 1 つずつ確認する。`run:` の中に残してよいのは、外部から決められない値(`runner.*`、ワークフローの中で定義した `matrix.*` など)だけである | `.github/workflows/` | 現在 | 未確認 |
| SEC-09-06 | Python の依存をバージョンとハッシュで固定し、CI は `uv sync --locked` で入れる | `pyproject.toml` の直接依存が `==` であること、`uv.lock` にハッシュがあること、ワークフローが `--locked` を使うことを確認する | pyproject.toml、uv.lock | 現在 | 未確認 |
| SEC-09-07 | Swift の依存をリビジョンで固定し、`Package.resolved` をコミットしている。依存の更新を定期的に確認する仕組みがある | 3 件の `Package.resolved` の内容が一致すること。Dependabot に `swift` のエコシステムがあるか、別の確認手順があること | Package.resolved、dependabot.yml | 現在 | 未確認 |
| SEC-09-08 | リポジトリと履歴に、秘密鍵・API キー・トークンが無い | `gitleaks detect`(または同等のツール)を全履歴に対して実行する。追跡対象のファイルは `git grep -I -l -E -e 'BEGIN [A-Z ]*PRIVATE KEY' -e 'AKIA[0-9A-Z]{16}' -e 'AIza[0-9A-Za-z_-]{35}' -e 'gh[pousr]_[A-Za-z0-9]{36}'` で確認する | リポジトリ全体 | 現在 | 未確認 |
| SEC-09-09 | 秘密情報を含みうるファイルを `.gitignore` で除外している(`.env`、署名用の証明書・プロファイル、サービスアカウントの鍵) | `.gitignore` を確認する。`*.p8`、`*.p12`、`*.mobileprovision`、`*.pem`、`.env.*` の扱いを決める | .gitignore | 現在 | 未確認 |
| SEC-09-10 | GitHub のシークレットスキャンとプッシュ保護が有効である | リポジトリの Settings > Code security を確認する | GitHub の設定 | 現在 | 未確認 |
| SEC-09-11 | リリースのワークフローのログに、署名鍵とトークンが出ない | P5-S01 の実行ログを確認する。鍵を環境変数で渡し、`set -x` や引数の表示で出ないこと | P5-S01、DDD-P5 5 章 No. 2 | P5 | 未確認 |
| SEC-09-12 | `main` ブランチを保護している(プルリクエストとレビューが必須、必須のチェック、強制プッシュの禁止) | リポジトリのブランチ保護(ルールセット)を確認する | GitHub の設定 | 現在 | 未確認 |

## 3. 事前調査で把握した現状

- ワークフローは 7 件で、すべて `permissions: contents: read` である。`pull_request_target` と `secrets.` の使用は無い。
- `actions/checkout` は 8 か所で使い、すべて `persist-credentials: false` を指定している。
- 使っている Actions は `actions/checkout@v7` と `astral-sh/setup-uv@v10.3.2` の 2 つで、タグで指定している。コミット SHA では固定していない(SEC-09-04)。
- Python の直接依存(`cryptography`、`httpx`、`jsonschema`、`PyYAML`、`pytest`、`fsrs`)は `==` で固定し、CI は `uv sync --locked` を使う。
- Swift の外部依存は `swift-markdown` と、その依存の `swift-cmark` だけである。`Package.resolved` はリビジョンつきでコミットしている。
- Dependabot の対象は `uv`(`/content`)と `github-actions` だけで、Swift のパッケージは対象になっていない(SEC-09-07)。
- `.gitignore` が除外する秘密情報は `.env` だけである。
- 追跡対象のファイルに、秘密鍵・クラウドの API キー・GitHub のトークンの形式に合う文字列は無い(`git grep` で確認)。履歴は確認していない。
- macOS のワークフローは `macos-latest` を使い、Xcode の版を固定していない。

## 4. 未決事項

| No. | 内容 | 決める時期 |
|---|---|---|
| 1 | Actions を SHA で固定する範囲(全ワークフローか、リリースだけか) | P5-S01 まで |
| 2 | Swift の依存の更新を確認する方法(Dependabot の `swift` か、手動の定期確認か) | リリース前 |
| 3 | アプリのコード署名(証明書、プロビジョニングプロファイル、App Store Connect の API キー)を CI で扱うか。扱う場合の保管場所 | リリース前 |
| 4 | SBOM やライセンスの一覧を作るか(ストアの「このアプリについて」の表示と合わせる) | リリース前 |
