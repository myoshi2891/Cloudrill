# content — 学習コンテンツ

クラウド認定試験対策 iOS アプリ「Cloudrill」の学習コンテンツです。試験ごとに `exams/<examID>/` の下に置きます(初期リリースの対象は Google Cloud PCA の `exams/gcp-pca/`)。
問題、フラッシュカード、ケーススタディなどを YAML / Markdown で管理し、CI で検証してから JSON に変換して配信します。
モノレポ全体の構成は [ルートの README](../README.md) を参照してください。

ここで定める **JSON Schema と検証ルール** は、Swift の `Codable` 定義(`packages/DomainModels/`)と CI の両方の基準になります。

> [!IMPORTANT]
> **運用ルール: Schema を変更したら `packages/DomainModels` も同じ PR で更新し、両方のテストを通すこと。**
> `content/schemas/*.schema.json` を変更したときは、次の作業を同じ PR で行ってください。
> 1. `packages/DomainModels/Sources/` の型を更新する
> 2. 必要に応じて `content/tests/fixtures/generate.py` を更新し、fixture を再生成する
> 3. `content/scripts/export_json.py` で Swift 用 JSON(`content/tests/fixtures/valid-json/`)を再生成する
> 4. `pytest` と `swift test` の両方が通ることを確認する
>
> CI では `content-validate.yml`(pytest + validate.py)と `domainmodels-test.yml`(swift test)が実行されます。

## ローカルでの実行

以下のコマンドは、リポジトリのルートから実行する前提です。

```sh
cd /path/to/google-cloud-professional-cloud-architect

# uv(https://docs.astral.sh/uv/)が必要。Python 3.14 の取得と content/.venv の作成をまとめて行う
uv sync --project content

# コンテンツの検証(--root を省略すると content/ が対象。どのディレクトリから実行しても結果は同じ)
content/.venv/bin/python content/scripts/validate.py
content/.venv/bin/python content/scripts/validate.py --check-links      # リンク切れ確認(CI-06)も行う
content/.venv/bin/python content/scripts/validate.py --only CI-02,CI-03 --format json

# テスト(pyproject.toml がある content/ で実行する)
(cd content && .venv/bin/pytest)

# fixture と Swift 用 JSON の再生成(コミット対象)
content/.venv/bin/python content/tests/fixtures/generate.py
content/.venv/bin/python content/scripts/export_json.py

# Swift のテスト
swift test --package-path packages/DomainModels
```

`swift test` が `plugin for module 'TestingMacros' not found` で失敗する場合は、Command Line Tools ではなく Xcode のツールチェーンを使ってください。
例: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/DomainModels`

### validate.py

```
python content/scripts/validate.py [--root content] [--config validation.yaml] [--exam gcp-pca] [--check-links] [--strict]
                                   [--format text|json|github] [--only CI-02,CI-03]
```

| 項目 | 仕様 |
|---|---|
| 終了コード | `0` = error なし / `1` = error あり(`--strict` では warning も含む)/ `2` = 引数や設定の不備 |
| `--format text` | `path:line: [CI-xx] severity: message`。最後に件数の集計とルール別の内訳を出す |
| `--format json` | `[{"rule","severity","file","line","message"}]`。`file` は `--root` からの相対パス |
| `--format github` | `::error file=...,line=...,title=CI-xx::message`。`file` はリポジトリルート(`GITHUB_WORKSPACE`、なければカレントディレクトリ)からの相対パス |
| `--only` | 指定したルールだけを報告する。Schema 検証そのものは常に行う(後述) |
| `--exam` | 指定した試験(カンマ区切り)だけを検証する。全体のファイル(`vendors.yaml`)は常に対象。存在しない試験 ID は終了コード 2 |
| `--strict` | warning を error に昇格する。出力の深刻度と終了コードの両方に反映される |
| `--root` | 省略時は、スクリプトの位置から見た `content/` を使う(実行場所に依存しない) |
| `--config` | 全体の設定ファイル。省略時は `<root>/validation.yaml` を使い、なければ `content/validation.yaml` を使う。試験ごとの設定(`exams/<examID>/validation.yaml`)は常に試験ディレクトリから読む |

### build_pack.py

```
SOURCE_DATE_EPOCH=<秒> python content/scripts/build_pack.py --exam <examID> --version <X.Y.Z> --min-app-version <X.Y.Z> \
                                                     --key-id <ID> [--root content] [--config validation.yaml] --out <出力先>
```

1つの試験の配信パック(形式は `Documentation.docc/DDD/DDD-P2-ContentPack.md` の 3.1)を `<出力先>/<examID>/<version>/` に作ります。署名(`manifest.sig`)は作りません。

| 項目 | 仕様 |
|---|---|
| 終了コード | `0` = 成功(warning は標準エラーに出す)/ `1` = コンテンツの検証で error がある(出力しない)/ `2` = 引数・環境の不備、出力先がすでにある(上書きしない) |
| 検証 | `validate.py --exam <examID>` と同じ検証を先に行う |
| 決定論 | 同じ入力と `SOURCE_DATE_EPOCH` なら、全ファイルのバイト列が一致する。`createdAt` は `SOURCE_DATE_EPOCH` から作る |
| 機能 | `exam.yaml` の `features` が false の種別(`cases.json` など)は出力しない。`docs/index.json` は常に出力する(`features.docs` が false なら空の配列) |

### sign_manifest.py / build_catalog.py

```sh
python content/scripts/sign_manifest.py --manifest <manifest.json> --key-id <ID> --key-env <環境変数名>
# ローカルのテスト専用。秘密鍵ファイルは作らない
python content/scripts/sign_manifest.py --manifest <manifest.json> --key-id test-2026 --test-key test-2026
SOURCE_DATE_EPOCH=<秒> python content/scripts/build_catalog.py --root content --out <catalog.json> \
    [--previous <catalog.json>] [--update <examID>=<manifest.json> ...]
```

署名には `cryptography` の Ed25519 を使います。`--key-env` は32バイトの seed を標準 Base64 で設定した環境変数の名前です。manifest 自体は変更せず、そのバイト列への署名を改行なしの Base64 として `manifest.sig` に書きます。`--key-id` が manifest の `keyID` と異なる場合は失敗します。

カタログの表示情報は `catalog.yaml` と `exam.yaml`、版は `--previous` と `--update` から作ります。`generatedAt` は `SOURCE_DATE_EPOCH` で固定します。更新しない試験の版は保持し、SemVer の優先順位で版戻しを拒否します。`available` には版が必要なので、未配信の試験は `comingSoon` にしてください。署名・カタログの終了コードは成功が `0`、入力・I/O の不備が `2` です。書き込みはアトミックに置き換えます。

配信前後の検証は `contentpack.verify.verify_pack(directory, key_ring=..., expected_exam_id=..., app_version=..., current_version=...)` を使います。鍵リングは鍵 ID → `Ed25519PublicKey` の辞書です。署名 → デコード → 形式の版 → アプリの版 → 試験 ID → 版戻し → 各ファイルの安全なパス・存在・サイズ・SHA-256 の順で検証し、`VerificationError.code` に Swift のエラー名に対応する snake_case を返します。

契約 fixture は `content/.venv/bin/python content/tests/fixtures/generate_packs.py` で再生成します。`tests/fixtures/packs/` に正常な3パック、改ざん9種類、公開鍵、カタログを置きます。`--out <生成専用ディレクトリ>` も指定できます（既存の出力は置き換えます）。生成には固定 epoch を使い、`test_generated.py` がバイト単位の一致と期待する検証結果を確認します。Swift のテストはこのディレクトリを直接参照します。

## ディレクトリ構成(`content/` 配下)

```
schemas/                  JSON Schema(Draft 2020-12)
validation.yaml           検証の閾値(全体)
vendors.yaml              ベンダーの定義(全試験で共通)
catalog.yaml              カタログの元データ(検証時は任意、生成時は必須)
exams/<examID>/           試験ごとのディレクトリ(例: exams/gcp-pca/)
  exam.yaml               試験の定義(ドメインと比重、形式、機能、語彙)
  validation.yaml         試験ごとの検証設定(模試の構成 examSet、閾値の上書き。任意)
  exam-sets.yaml          模試ごとの問題 ID とケースの割り当て
  questions/domain{1..6}/ 問題(1ファイル1問。ファイル名は <id>.yaml)
  flashcards/*.yaml       フラッシュカード(1ファイルに複数枚: { cards: [...] })
  cases/*.yaml            ケーススタディ(1ファイル1ケース)
  decisions/*.yaml        ディシジョンツリー(1ファイル1ツリー)
  drills/keywords.yaml    キーワード反射ドリル({ drills: [...] })
  docs/*.md               YAML フロントマター + Markdown 本文
scripts/validate.py       検証 CLI(実装は scripts/contentvalidate/)
scripts/export_json.py    YAML → JSON 変換(tests/fixtures/valid-json/ の生成)
scripts/build_pack.py     配信パックのビルド CLI(実装は scripts/contentpack/)
scripts/sign_manifest.py  Ed25519 署名 CLI
scripts/build_catalog.py  配信カタログの生成 CLI
tests/                    pytest と fixture(valid-json/ は Swift テストが直接参照する)
```

## Schema

### ファイル分割と `$ref`

- 各 Schema の `$id` は `https://examprep-content.invalid/schemas/<name>.schema.json` です。
  - `.invalid` は予約済みの TLD なので、外部への名前解決は起きません。
  - validate.py は `referencing.Registry` に全 Schema を事前に登録し、オフラインで解決します。
- 共通の定義は `common.schema.json#/$defs/...` にまとめ、各 Schema から `$ref` で参照します。
- 各ファイル用の Schema は「YAML 1ファイル分のルート」を表します。
- すべてのオブジェクトに `additionalProperties: false` を付けているので、キーの typo は CI-01 で検出されます。

| Schema | 対象 | 主な内容 |
|---|---|---|
| `common` | — | `LocalizedText`、`ExamID`、`VendorID`、`QuestionKind`、`CaseStudyID`、`WAFPillarID`、`MistakeTag`、`License`、`Reference`、`SubObjective`、`Domain`、`QuestionID`、`CardID`、`SemVer`、`HttpsURL` |
| `question` | `questions/**/*.yaml` | 問題。`type` は `kind` に応じて `if/then/else` で分岐する(single は `count` 不可、multiple は `count ≥ 2` が必須) |
| `flashcard` | `flashcards/*.yaml` | `{ cards: Flashcard[] }` |
| `case` | `cases/*.yaml` | ケーススタディと要件マッピング |
| `decision` | `decisions/*.yaml` | ツリー。各 option は `next` と `result` のどちらか一方を持つ(`oneOf`) |
| `drill` | `drills/*.yaml` | `{ drills: KeywordDrill[] }`。ID は `^K-[0-9]{4}$` |
| `exam` | `exams/<examID>/exam.yaml` | 試験の定義(ドメインと比重、サブ項目、模試の形式、有効な機能、WAF の柱、ケースの表示順) |
| `vendors` | `vendors.yaml` | ベンダーの定義 |
| `exam-sets` | `exam-sets.yaml` | 模試の定義(`caseStudies` は `minItems: 0`。個数が `caseStudiesPerSet` と一致するかは CI-02 が確認する。`questionIDs` は重複なし) |
| `docs-frontmatter` | `docs/*.md` のフロントマター | `title`、`subObjective`、`references`(1つ以上) |
| `manifest` | 配信パックの `manifest.json` | 生成は `build_pack.py`、署名は `sign_manifest.py`(P2-S03) |
| `pack-question-index` | 配信パックの `questions/index.json` | 問題の要約(`QuestionIndexEntry`)の配列。各項目の制約は `question` と同じで、`type` の代わりに `kind` だけを持つ |
| `pack-docs-index` | 配信パックの `docs/index.json` | `DocEntry`(フロントマターの内容と本文の `path`)の配列。`path` は `docs/` 直下の `.md` に限る |
| `catalog` | 配信する試験の一覧 `catalog.json` | `status` は `available` / `comingSoon` / `retired`。パックがまだない試験は `latestPackVersion`・`minAppVersion` が `null`(キーは必須。`available` では `null` 不可) |
| `catalog-source` | `catalog.yaml` | カタログの元データ(`id`、`status`、`productIDs`)。試験 ID の実在と重複は Schema では確認しない |

### Schema と validate.py の役割分担

| 担当 | 内容 |
|---|---|
| Schema | 1ファイル内の構造(型、必須項目、列挙値、パターン、個数、重複なし) |
| validate.py(ファイル内) | Schema では表現しにくい条件(CI-01 の追加条件、CI-05、CI-08、CI-11) |
| validate.py(ファイル間) | 模試の構成、統計、重複、参照の整合性、試験定義の整合(CI-02、03、04、07、09、10、12) |
| validate.py(外部) | リンク切れ(CI-06) |

- Schema に違反したファイルは、ファイル間のルールの対象から外します。型が崩れたデータが原因で、別のルールでも違反が連鎖して報告されるのを防ぐためです。
- 例外として、`choices[*].rationale` に関する Schema 違反は CI-01 では報告しません。CI-05 だけが報告します(二重報告の防止)。

## 検証ルール

閾値はすべて `validation.yaml` にあります。設定は2階層です。

- 全体の `content/validation.yaml` に、試験ごとの `exams/<examID>/validation.yaml` を深いマージで重ねます。マッピングはキーごとにマージし、リストとスカラーは試験側の値で置き換えます。
- 模試の構成(`examSet`)は試験ごとの設定にだけ書けます。`examSet` がない試験では、CI-02 のドメイン配分・ケース問題数・既定の割り当ての確認を省略します。
- サブ項目の一覧と模試の問題数は `exam.yaml` が正です(全体の設定に `examGuide` や `examSet` があると、終了コード 2)。
- 未知のキーは typo とみなし、終了コード 2 にします。

| ID | ルール | 深刻度 | 設定キー |
|---|---|---|---|
| CI-01 | 全ファイルの Schema 適合、YAML 構文、キーの重複、必須ファイルの有無。加えて、`subObjective` と `domain` の整合(問題とカード。exam.yaml のサブ項目とドメインの対応で判定する)、single の正解がちょうど 1 つ、誤答の `mistakeTags` が 1 つ以上、正解に `mistakeTags` がない、選択肢 ID・模試 ID・ノード ID の重複 | error | — |
| CI-02 | 模試の問題数、ドメイン配分、ケース数(exam.yaml の `caseStudiesPerSet`)、ケース問題数(`caseStudiesPerSet` が 0 なら 0 問)、ケース問題の `caseStudy` が模試のケースに含まれること、問題の `examSets` と `questionIDs` の双方向の一致、存在しない模試番号の参照 | complete は error、draft は warning(存在しない模試番号は常に error) | 試験ごとの `examSet.*`、exam.yaml の `format.mockExam` |
| CI-02 | 既定のケース割り当て・level との違い | warning | `examSet.defaultAssignments` |
| CI-03 | 単一選択問題の正解位置(元の並び順)A〜D がそれぞれ 20〜30% | complete は error、draft は warning | `answerPosition.*`、`statistics.draftMinSample` |
| CI-04 | 最長の選択肢(`ja` の文字数)が正解である問題の割合が 35% 以下 | complete は error、draft は warning | `longestChoice.*`、`statistics.draftMinSample` |
| CI-05 | 全選択肢に `rationale.ja` があり、空白だけでない | error | — |
| CI-06 | 参照 URL(`references[].url`、`officialURL`)のリンク切れ。`--check-links` を指定したときだけ実行する。HEAD を送り、405 なら GET で再試行する | warning | `links.*` |
| CI-07 | 試験内での問題 ID・カード ID・ドリル ID・ケース ID・ツリー ID の重複(試験が異なれば同じ ID でもよい) | error | — |
| CI-07 | `stem.ja` の文字 3-gram の Jaccard 係数が 0.8 を超える組 | warning | `similarity.*` |
| CI-08 | multiple の問題で `type.count` と正解数が一致する | error | — |
| CI-09 | `relatedQuestionIDs`、`questionIDs`、ツリーの `rootNodeID` と `next`、docs・問題・カードの `subObjective` が実在する。問題・カードの `domain`、問題の `caseStudy` と `wafPillars`、模試の `caseStudies` が exam.yaml にある | error | exam.yaml の `domains`、`caseStudies`、`taxonomies.wafPillars` |
| CI-10 | exam.yaml の `domains[*].weight` の合計が 1.0 ± 0.001 | error | `weights.*` |
| CI-11 | `LocalizedText` の `en` の欠落(空文字を含む) | warning | — |
| CI-12 | 試験定義の整合: `exam.yaml` の `id` がディレクトリ名と一致する、`vendor` が `vendors.yaml` にある、`domains[*].id` が 1 から始まる連番、サブ項目 ID が試験内で一意、`caseStudies` と `cases/*.yaml` の id の集合が一致する、無効な機能(`features.*: false`)のファイルがない(ケースが無効なら、問題の `caseStudy` と模試の `caseStudies` も空)、問題の `type.kind` が `format.questionKinds` に含まれる | error | — |
| CI-12 | 問題の `examGuideVersion` が `exam.yaml` の `guideVersion` と一致する。試験ガイドの改訂時は、`guideVersion` を上げてから `--exam <examID> --only CI-12` を実行すると、見直しが必要な問題の一覧が得られる | warning | — |
| CI-13 | `catalog.yaml` にある試験 ID が `exams/` に実在し、重複しない。全体ルールで、`--exam` による絞り込みの対象外。ファイルがない場合は何も報告しない。構文・Schema 違反は CI-01 | error | — |

### ルールの追加方法

1. `scripts/contentvalidate/rules/ciNN_xxx.py` を作成し、`check` 関数と `RULE` を定義する
   - 試験ごとのルール(既定): `check(ctx: ExamContext) -> Iterable[Issue]` と `RULE = Rule("CI-NN", "名前", check)`。試験の数だけ実行される
   - 全体のルール(CI-01、CI-06、CI-11): `check(ctx: GlobalContext)` と `RULE = Rule("CI-NN", "名前", check_global=check)`。1回だけ実行される
2. `scripts/contentvalidate/rules/__init__.py` の `ALL_RULES` に1行追加する
3. `tests/fixtures/generate.py` の `INVALID_CASES`(`test-beta` の上で作るケースは `BETA_INVALID_CASES`)に違反ケースを追加し、fixture を再生成する

`ExamContext` からは、その試験のコンテンツ(`ctx.docs`、`ctx.questions`、`ctx.question_by_id`、`ctx.exam_sets`)、試験ごとの設定(`ctx.config`)、試験定義(`ctx.definition`。`exam.yaml` が Schema 違反なら `None` で、その場合は何も報告しない)を利用できます。ルールは `exam.yaml` の生データを直接読まず、`ctx.definition`(`ExamDefinitionView`)を使います。`GlobalContext` は全ファイル(`ctx.docs`)と各試験のコンテキスト(`ctx.exam(exam_id)`)を持ちます。行番号は `doc.issue(..., path)` で付きます。

## テスト

| ファイル | 内容 |
|---|---|
| `tests/fixtures/valid/` | 全ルールを error・warning ゼロで通過する一式。形の違う 2 つの試験を持つ。`test-beta` はケースなし・single のみ・ドメイン 4・サブ項目 `NET.1` など(拡張性の確認用)。以下は `test-alpha` の内容: complete の模試 1 回分(55 問: D1=14、D2=10、D3=10、D4=8、D5+D6=13、ケース問題 13、うち multiple 4 問)と、練習用の問題、カード、ケース、ツリー、ドリル、docs |
| `tests/fixtures/invalid/<ケース名>/` | valid に対する差分(overlay)。`expected.yaml` に、検出されるべきルール ID と深刻度を書く。`_delete.txt` があれば、そこに列挙したファイルを valid から削除する |
| `tests/test_rules.py` | valid が 0 件であること、各 invalid ケースで期待するルールだけが検出されること、`--only`、`--strict`、行番号、リンク確認(モック) |
| `tests/test_cli.py` | 終了コード、3種類の出力形式、エスケープ、引数エラー |
| `tests/test_schemas.py` | Schema 自体の妥当性、manifest や QuestionType などの正例と負例 |
| `tests/test_perf.py` | 問題 500 件で 10 秒以内に終わること |
| `tests/test_extensibility.py` | 各試験を `--exam` で1つずつ検証できること、検証ツールのコードに試験固有の値(`gcp-pca`、ケース ID など)がないこと、試験が異なれば同じ ID を使えること |
| `tests/fixtures/valid-json/` | valid を JSON に変換したもの。`packages/DomainModels` のテストが `../../content/tests/fixtures/valid-json` として直接読む(パッケージ内にはコピーしない) |
| `tests/test_generated.py` | コミット済みの fixture と valid-json が、生成スクリプトの出力と一致すること |
| `packages/DomainModels/Tests/` | Swift Testing。valid fixture の JSON のデコード(`valid-json/exams/*/` を列挙し、試験ごとに全ファイル)、試験定義(`ExamDefinitionTests`)、文字列 ID(`IdentifierTests`)、`QuestionType` などのカスタムデコード、エンコードと再デコードの往復 |

fixture は `tests/fixtures/generate.py` が固定 seed で決定論的に生成します。手で編集せず、生成スクリプトを変更してから再生成してください。

## CI(ルートの `.github/` に配置)

| ワークフロー | トリガー | 内容 |
|---|---|---|
| `content-validate.yml` | `pull_request`、`main` への push(`content/**`、`packages/DomainModels/**` の変更時) | Python 3.14 で `pytest` と `validate.py --format github` を実行する |
| `domainmodels-test.yml` | `pull_request`、`main` への push(`packages/DomainModels/**`、`content/schemas/**`、`content/tests/fixtures/**` の変更時) | macOS で `swift test --package-path packages/DomainModels` を実行する |
| `content-link-check.yml` | 毎週月曜 00:00 UTC、手動実行 | `validate.py --only CI-06 --check-links --strict --format github` を実行する(リンク切れがあればジョブが失敗する) |
| `dependabot.yml` | 毎週 | pip と GitHub Actions のバージョン更新 PR を作る |

## 前提と判断

仕様に明記がない点や曖昧な点は、次のように判断しました。

1. **ファイルの粒度。** 問題、ケース、ツリーは 1ファイル1件です。カードとドリルは件数が多く、1件あたりが小さいので、配列のラッパー(`cards` / `drills`)で 1ファイルに複数件を持ちます。
2. **LocalizedText とプレーン文字列の使い分け。**
   - LocalizedText にする項目: 利用者に表示する文章(問題文、選択肢、解説、ケースの各要件、ツリーの質問やラベル、ドリルのフレーズや解説、カードの表と裏)。
   - プレーン文字列にする項目: サービス名(`recommendedServices`、`service`、`correct`、`distractor`)、`Reference.title`、docs の `title`(docs の本文は日本語のみのため)。
3. **QuestionType の Schema は `oneOf` ではなく `if/then/else` で表現しました。** エラーメッセージが具体的になるためです。
4. **CI-01 の追加条件の実装場所。** `mistakeTags` の条件は Schema の `if/then` でも書けますが、メッセージを分かりやすくするため validate.py 側で検証します。Schema では `mistakeTags` を任意項目としています。
5. **rationale の Schema エラーは CI-05 に委ねます。** `LocalizedText.ja` には `minLength: 1` があるため、空の rationale は本来 CI-01 にも該当します。ルール ID を一意にするため、CI-01 からは除外します。また、rationale のエラーだけであれば、そのファイルはファイル間ルールの対象に残します。
6. **`--only` は「報告するルール」の絞り込みです。** CI-01 を外しても Schema 検証自体は行い、Schema に違反したファイルはファイル間ルールの対象外のままです。
7. **CI-02 の双方向チェック。** 問題が存在しない模試番号を `examSets` に持つ場合は、模試の status が決まらないため常に error にします。`questionIDs` にある問題が存在しない場合は CI-09 で報告します。
8. **CI-03 は A〜D だけを集計します。** 分母は、その模試の単一選択問題の数です。5〜6 択の問題で E や F が正解の場合は、分母には入りますが、どの位置としても集計しません。
9. **CI-04 は multiple の問題も対象にします。** 最長の選択肢が正解のいずれかであれば該当とします。最長が同率で複数ある場合も、その中に正解があれば該当と数えます(`countTies: true` で変更できます)。
10. **draft の模試の統計チェック(CI-03・CI-04)。** 単一選択問題(CI-04 では全問題)が `statistics.draftMinSample`(20)未満の draft 模試では、統計チェックを省略します。数問の段階で偏りの warning が出続けるのを避けるためです。complete の模試は常に検査します。
11. **CI-07 の対象範囲。** 仕様の「問題 ID・カード ID」に加えて、ドリル・ケース・ツリーの ID の重複も検出します。類似度の判定前に、NFKC 正規化と空白の除去を行います。
12. **CI-09 の subObjective の実在確認。** 試験の `exam.yaml` の `domains[*].subObjectives` と照合します。仕様の docs に加えて、問題とカードにも適用します。
    **この一覧は暫定値です。公式の試験ガイド(v6.1)との照合が必要です。**
13. **CI-06 の対象。** `references[].url` に加えて、ケースの `officialURL` も対象にします。同じ URL は1回だけ確認し、検出された問題はその URL のすべての出現箇所に報告します。
14. **`--strict` は出力の深刻度も error に書き換えます。** GitHub のアノテーションも error になります。
15. **終了コード 2。** 引数の不備や `validation.yaml`(全体・試験ごと)の不備は、コンテンツの違反と区別するため 2 にします。argparse の慣例にも合わせています。
16. **YAML の正規化。** キーはすべて文字列にし(`1:` は `"1"` になります)、日付は ISO 8601 の文字列にします。`examGuideVersion: 6.1` のように引用符を付け忘れると数値として読まれ、CI-01 になります。
17. **行番号。** マッピングの要素ではキーの行を、配列の要素では要素の先頭行を指します。docs ではフロントマターの開始行(`---`)からのずれを補正します。
18. **Python のバージョン。** 依頼では 3.12 でしたが、セキュリティ修正の状況を踏まえて 3.14 を採用しました(依頼者と合意済み)。コードは 3.12 でも動くように書いており、`requires-python >= 3.12` としています。直接の依存は `==` で固定し、Dependabot で更新します。
19. **Swift の型。**
    - `Question.caseStudy` は Optional です。`Choice.mistakeTags` は省略時に空配列になり、エンコード時に空なら省略します。
    - 未知の列挙値はデコードエラーにしています。新しい列挙値を含むパックが古いアプリに配信されないよう、`manifest.minAppVersion` で制御する前提です。
    - 試験語彙の ID(`ExamID`、`VendorID`、`CaseStudyID`、`WAFPillarID`)は列挙ではなく、文字列をラップした型(`StringIdentifier`)です。デコード時は空文字だけを拒否し、実在は CI-09・CI-12 が確認します。
    - `exam.json` は `ExamDefinition` でデコードします。`ExamFeatures` は、フラグがなければ `false` として読みます(機能を追加したときに古い `exam.json` も読めるようにするため)。採点方式(`ScoringPolicyKind`)と出題形式(`QuestionKind`)は構造語彙なので、未知の値はデコードエラーです。
    - `Manifest.createdAt` は `Date` で、デコードには `ContentDecoder.make()`(ISO 8601)を使います。
20. **サンプルコンテンツ。** すべてオリジナルです。ケーススタディの要約は学習用に書き起こした短い文章です。正確な内容は公式のケーススタディを参照する前提です(`cases/ehr.yaml` の `officialURL` は暫定で試験ページを指しています)。

## 未対応事項

- 配信用リリースワークフロー(`release.yml`、P5-S01)
- ディシジョンツリーの循環検出と、到達できないノードの検出
- `questions/domainN/` のディレクトリと `domain` の一致、ファイル名と `id` の一致のチェック
- docs のフロントマターに対応する Swift モデル(アプリ側で Markdown と一緒に扱う想定)
- `exam.yaml` のサブ項目と公式試験ガイドの照合、ドメイン 5・6 の比重の確定
- gcp-pca のケーススタディ `altostrat`・`cymbal`・`knightMotives` の作成(作成したら `exam.yaml` の `caseStudies` に加え、`caseStudiesPerSet` を 2 に、模試 1 の `caseStudies` と `validation.yaml` の既定の割り当てを `[ehr, altostrat]` に戻す。現在は `ehr` のみで、`caseStudiesPerSet` は暫定で 1)
- GitHub Actions のアクションを SHA で固定すること(現在はメジャーバージョンのタグを指定し、Dependabot で更新)
