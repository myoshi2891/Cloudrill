# pca-content

Google Cloud Professional Cloud Architect(PCA)試験対策 iOS アプリの学習コンテンツを管理するリポジトリです。
問題、フラッシュカード、ケーススタディなどを YAML / Markdown で管理し、CI で検証してから JSON に変換して配信します。

このリポジトリで定める **JSON Schema と検証ルール** は、iOS アプリ側の Swift `Codable` 定義(`swift/DomainModels/`)と CI の両方の基準になります。

> [!IMPORTANT]
> **運用ルール: Schema を変更したら Swift 側も更新し、両方のテストを通すこと。**
> `schemas/*.schema.json` を変更したときは、次の作業を同じ PR で行ってください。
> 1. `swift/DomainModels/Sources/` の型を更新する
> 2. 必要に応じて `tests/fixtures/generate.py` を更新し、fixture を再生成する
> 3. `scripts/export_json.py` で Swift 用 JSON を再生成する
> 4. `pytest` と `swift test` の両方が通ることを確認する
>
> CI(`validate.yml`)はこの両方を実行します。

## ローカルでの実行

```sh
# Python 3.14(pyenv の例)
pyenv install -s 3.14.7
python3.14 -m venv .venv
.venv/bin/pip install -r requirements.txt

# コンテンツの検証
.venv/bin/python scripts/validate.py                    # リポジトリ直下を検証
.venv/bin/python scripts/validate.py --check-links      # リンク切れ確認(CI-06)も行う
.venv/bin/python scripts/validate.py --only CI-02,CI-03 --format json

# テスト
.venv/bin/pytest

# fixture と Swift 用 JSON の再生成(コミット対象)
.venv/bin/python tests/fixtures/generate.py
.venv/bin/python scripts/export_json.py

# Swift のテスト
cd swift/DomainModels && swift test
```

`swift test` が `plugin for module 'TestingMacros' not found` で失敗する場合は、Command Line Tools ではなく Xcode のツールチェーンを使ってください。
例: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

### validate.py

```
python scripts/validate.py [--root .] [--config validation.yaml] [--check-links] [--strict]
                           [--format text|json|github] [--only CI-02,CI-03]
```

| 項目 | 仕様 |
|---|---|
| 終了コード | `0` = error なし / `1` = error あり(`--strict` では warning も含む)/ `2` = 引数や設定の不備 |
| `--format text` | `path:line: [CI-xx] severity: message`。最後に件数の集計とルール別の内訳を出す |
| `--format json` | `[{"rule","severity","file","line","message"}]`。`file` は `--root` からの相対パス |
| `--format github` | `::error file=...,line=...,title=CI-xx::message`。`file` はカレントディレクトリからの相対パス |
| `--only` | 指定したルールだけを報告する。Schema 検証そのものは常に行う(後述) |
| `--strict` | warning を error に昇格する。出力の深刻度と終了コードの両方に反映される |
| `--config` | 省略時は `<root>/validation.yaml` を使い、なければリポジトリの `validation.yaml` を使う |

## ディレクトリ構成

```
schemas/                  JSON Schema(Draft 2020-12)
validation.yaml           検証の閾値と設定
weights.yaml              ドメイン比重
exam-sets.yaml            模試ごとの問題 ID とケースの割り当て
questions/domain{1..6}/   問題(1ファイル1問。ファイル名は <id>.yaml)
flashcards/*.yaml         フラッシュカード(1ファイルに複数枚: { cards: [...] })
cases/*.yaml              ケーススタディ(1ファイル1ケース)
decisions/*.yaml          ディシジョンツリー(1ファイル1ツリー)
drills/keywords.yaml      キーワード反射ドリル({ drills: [...] })
docs/*.md                 YAML フロントマター + Markdown 本文
scripts/validate.py       検証 CLI(実装は scripts/pcavalidate/)
scripts/export_json.py    YAML → JSON 変換(Swift テスト用 fixture の生成)
tests/                    pytest と fixture
swift/DomainModels/       Schema に対応する Swift の Codable 定義(SwiftPM)
```

## Schema

### ファイル分割と `$ref`

- 各 Schema の `$id` は `https://pca-content.invalid/schemas/<name>.schema.json` です。
  - `.invalid` は予約済みの TLD なので、外部への名前解決は起きません。
  - validate.py は `referencing.Registry` に全 Schema を事前に登録し、オフラインで解決します。
- 共通の定義は `common.schema.json#/$defs/...` にまとめ、各 Schema から `$ref` で参照します。
- 各ファイル用の Schema は「YAML 1ファイル分のルート」を表します。
- すべてのオブジェクトに `additionalProperties: false` を付けているので、キーの typo は CI-01 で検出されます。

| Schema | 対象 | 主な内容 |
|---|---|---|
| `common` | — | `LocalizedText`、`CaseStudyID`、`WAFPillar`、`MistakeTag`、`License`、`Reference`、`SubObjective`、`Domain`、`QuestionID`、`CardID`、`SemVer`、`HttpsURL` |
| `question` | `questions/**/*.yaml` | 問題。`type` は `kind` に応じて `if/then/else` で分岐する(single は `count` 不可、multiple は `count ≥ 2` が必須) |
| `flashcard` | `flashcards/*.yaml` | `{ cards: Flashcard[] }` |
| `case` | `cases/*.yaml` | ケーススタディと要件マッピング |
| `decision` | `decisions/*.yaml` | ツリー。各 option は `next` と `result` のどちらか一方を持つ(`oneOf`) |
| `drill` | `drills/*.yaml` | `{ drills: KeywordDrill[] }`。ID は `^K-[0-9]{4}$` |
| `exam-sets` | `exam-sets.yaml` | 模試の定義(`caseStudies` はちょうど 2 つ、`questionIDs` は重複なし) |
| `weights` | `weights.yaml` | ドメイン比重(キー 1〜6 はすべて必須) |
| `docs-frontmatter` | `docs/*.md` のフロントマター | `title`、`subObjective`、`references`(1つ以上) |
| `manifest` | 配信パックの `manifest.json` | 定義のみ。生成と署名はこのリポジトリの対象外 |

### Schema と validate.py の役割分担

| 担当 | 内容 |
|---|---|
| Schema | 1ファイル内の構造(型、必須項目、列挙値、パターン、個数、重複なし) |
| validate.py(ファイル内) | Schema では表現しにくい条件(CI-01 の追加条件、CI-05、CI-08、CI-11) |
| validate.py(ファイル間) | 模試の構成、統計、重複、参照の整合性(CI-02、03、04、07、09、10) |
| validate.py(外部) | リンク切れ(CI-06) |

- Schema に違反したファイルは、ファイル間のルールの対象から外します。型が崩れたデータが原因で、別のルールでも違反が連鎖して報告されるのを防ぐためです。
- 例外として、`choices[*].rationale` に関する Schema 違反は CI-01 では報告しません。CI-05 だけが報告します(二重報告の防止)。

## 検証ルール

閾値はすべて `validation.yaml` にあります。

| ID | ルール | 深刻度 | 設定キー |
|---|---|---|---|
| CI-01 | 全ファイルの Schema 適合、YAML 構文、キーの重複、必須ファイルの有無。加えて、`subObjective` と `domain` の整合(問題とカード)、single の正解がちょうど 1 つ、誤答の `mistakeTags` が 1 つ以上、正解に `mistakeTags` がない、選択肢 ID・模試 ID・ノード ID の重複 | error | — |
| CI-02 | 模試の問題数、ドメイン配分、ケース問題数、ケース問題の `caseStudy` が模試のケースに含まれること、問題の `examSets` と `questionIDs` の双方向の一致、存在しない模試番号の参照 | complete は error、draft は warning(存在しない模試番号は常に error) | `examSet.*` |
| CI-02 | 既定のケース割り当て・level との違い | warning | `examSet.defaultAssignments` |
| CI-03 | 単一選択問題の正解位置(元の並び順)A〜D がそれぞれ 20〜30% | complete は error、draft は warning | `answerPosition.*`、`statistics.draftMinSample` |
| CI-04 | 最長の選択肢(`ja` の文字数)が正解である問題の割合が 35% 以下 | complete は error、draft は warning | `longestChoice.*`、`statistics.draftMinSample` |
| CI-05 | 全選択肢に `rationale.ja` があり、空白だけでない | error | — |
| CI-06 | 参照 URL(`references[].url`、`officialURL`)のリンク切れ。`--check-links` を指定したときだけ実行する。HEAD を送り、405 なら GET で再試行する | warning | `links.*` |
| CI-07 | 問題 ID・カード ID・ドリル ID・ケース ID・ツリー ID の重複 | error | — |
| CI-07 | `stem.ja` の文字 3-gram の Jaccard 係数が 0.8 を超える組 | warning | `similarity.*` |
| CI-08 | multiple の問題で `type.count` と正解数が一致する | error | — |
| CI-09 | `relatedQuestionIDs`、`questionIDs`、ツリーの `rootNodeID` と `next`、docs・問題・カードの `subObjective` が実在する | error | `examGuide.subObjectives` |
| CI-10 | `weights.yaml` の合計が 1.0 ± 0.001 | error | `weights.*` |
| CI-11 | `LocalizedText` の `en` の欠落(空文字を含む) | warning | — |

### ルールの追加方法

1. `scripts/pcavalidate/rules/ciNN_xxx.py` を作成し、`check(ctx: Context) -> Iterable[Issue]` と `RULE = Rule("CI-NN", "名前", check)` を定義する
2. `scripts/pcavalidate/rules/__init__.py` の `ALL_RULES` に1行追加する
3. `tests/fixtures/generate.py` の `INVALID_CASES` に違反ケースを追加し、fixture を再生成する

`ctx` から、ロード済みのコンテンツ(`ctx.docs`、`ctx.questions`、`ctx.question_by_id`、`ctx.exam_sets`)と、各要素の行番号(`doc.issue(..., path)`)を利用できます。

## テスト

| ファイル | 内容 |
|---|---|
| `tests/fixtures/valid/` | 全ルールを error・warning ゼロで通過する一式。complete の模試 1 回分(55 問: D1=14、D2=10、D3=10、D4=8、D5+D6=13、ケース問題 13、うち multiple 4 問)と、練習用の問題、カード、ケース、ツリー、ドリル、docs |
| `tests/fixtures/invalid/<ケース名>/` | valid に対する差分(overlay)。`expected.yaml` に、検出されるべきルール ID と深刻度を書く。`_delete.txt` があれば、そこに列挙したファイルを valid から削除する |
| `tests/test_rules.py` | valid が 0 件であること、各 invalid ケースで期待するルールだけが検出されること、`--only`、`--strict`、行番号、リンク確認(モック) |
| `tests/test_cli.py` | 終了コード、3種類の出力形式、エスケープ、引数エラー |
| `tests/test_schemas.py` | Schema 自体の妥当性、manifest や QuestionType などの正例と負例 |
| `tests/test_perf.py` | 問題 500 件で 10 秒以内に終わること |
| `tests/test_generated.py` | コミット済みの fixture と Swift 用 JSON が、生成スクリプトの出力と一致すること |
| `swift/DomainModels/Tests/` | Swift Testing。valid fixture の JSON のデコード、`QuestionType` などのカスタムデコード、エンコードと再デコードの往復 |

fixture は `tests/fixtures/generate.py` が固定 seed で決定論的に生成します。手で編集せず、生成スクリプトを変更してから再生成してください。

## CI

| ワークフロー | トリガー | 内容 |
|---|---|---|
| `validate.yml` | `pull_request`、`main` への push | Python 3.14 で `pytest` と `validate.py --format github` を実行する。macOS で `swift test` を実行する |
| `link-check.yml` | 毎週月曜 00:00 UTC、手動実行 | `validate.py --only CI-06 --check-links --strict --format github` を実行する(リンク切れがあればジョブが失敗する) |
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
12. **CI-09 の subObjective の実在確認。** `validation.yaml` の `examGuide.subObjectives` と照合します。仕様の docs に加えて、問題とカードにも適用します。
    **この一覧は暫定値です。公式の試験ガイド(v6.1)との照合が必要です。**
13. **CI-06 の対象。** `references[].url` に加えて、ケースの `officialURL` も対象にします。同じ URL は1回だけ確認し、検出された問題はその URL のすべての出現箇所に報告します。
14. **`--strict` は出力の深刻度も error に書き換えます。** GitHub のアノテーションも error になります。
15. **終了コード 2。** 引数の不備や `validation.yaml` の不備は、コンテンツの違反と区別するため 2 にします。argparse の慣例にも合わせています。
16. **YAML の正規化。** キーはすべて文字列にし(`weights.yaml` の `1:` は `"1"` になります)、日付は ISO 8601 の文字列にします。`examGuideVersion: 6.1` のように引用符を付け忘れると数値として読まれ、CI-01 になります。
17. **行番号。** マッピングの要素ではキーの行を、配列の要素では要素の先頭行を指します。docs ではフロントマターの開始行(`---`)からのずれを補正します。
18. **Python のバージョン。** 依頼では 3.12 でしたが、セキュリティ修正の状況を踏まえて 3.14 を採用しました(依頼者と合意済み)。コードは 3.12 でも動くように書いており、`requires-python >= 3.12` としています。直接の依存は `==` で固定し、Dependabot で更新します。
19. **Swift の型。**
    - `Question.caseStudy` は Optional です。`Choice.mistakeTags` は省略時に空配列になり、エンコード時に空なら省略します。
    - 未知の列挙値はデコードエラーにしています。新しい列挙値を含むパックが古いアプリに配信されないよう、`manifest.minAppVersion` で制御する前提です。
    - `DomainWeights.weights` は `[Int: Double]` です。
    - `Manifest.createdAt` は `Date` で、デコードには `ContentDecoder.make()`(ISO 8601)を使います。
20. **サンプルコンテンツ。** すべてオリジナルです。ケーススタディの要約は学習用に書き起こした短い文章です。正確な内容は公式のケーススタディを参照する前提です(`cases/ehr.yaml` の `officialURL` は暫定で試験ページを指しています)。

## 未対応事項

- manifest の生成と署名、配信パックのビルド(`build_pack.py`、`sign_manifest.py`、`release.yml`)
- ディシジョンツリーの循環検出と、到達できないノードの検出
- `questions/domainN/` のディレクトリと `domain` の一致、ファイル名と `id` の一致のチェック
- docs のフロントマターに対応する Swift モデル(アプリ側で Markdown と一緒に扱う想定)
- `examGuide.subObjectives` と公式試験ガイドの照合、ドメイン 5・6 の比重の確定
- GitHub Actions のアクションを SHA で固定すること(現在はメジャーバージョンのタグを指定し、Dependabot で更新)
