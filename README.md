# Google Cloud Professional Cloud Architect 試験対策アプリ

クラウド認定試験対策 iOS アプリ「Cloudrill」(最初の対象は Google Cloud PCA)と、その学習コンテンツを1つのリポジトリで管理するモノレポです。
コンテンツの JSON Schema と、Swift の `Codable` 定義を、1つのコミット・PR で同時に変更できます。

## ディレクトリ構成

```
google-cloud-professional-cloud-architect/
├── ExamPrepApp/                                     # iOS アプリのソース
├── ExamPrepApp.xcodeproj                            # DomainModels をローカルパッケージとして参照
├── Documentation.docc/                              # 要件定義書(RDD.md)、基本設計書(BDD.md)
├── packages/
│   ├── DomainModels/                                # コンテンツの値型(SwiftPM、Swift Testing)
│   ├── Domain/                                      # 学習・採点ロジック、DomainInterfaces
│   └── Data/                                        # ContentKit: パック検証・読み込み・保存・起動処理
├── content/                                         # 学習コンテンツ、JSON Schema、検証ツール
│   ├── schemas/                                     # JSON Schema(Draft 2020-12)
│   ├── vendors.yaml  validation.yaml                # ベンダー定義、検証の閾値(全体)
│   ├── exams/<examID>/                              # 試験ごと: exam.yaml、validation.yaml、問題などのコンテンツ
│   ├── scripts/                                     # validate.py、export_json.py
│   └── tests/                                       # pytest と fixture(valid-json/ は Swift テストも使う)
├── .github/
│   ├── workflows/                                   # content-validate / content-link-check / domainmodels-test
│   └── dependabot.yml
├── .gitignore
└── README.md
```

| ディレクトリ | 役割 |
|---|---|
| `ExamPrepApp/` と `ExamPrepApp.xcodeproj` | iOS アプリ本体。ホーム画面の表示名は「Cloudrill」(`INFOPLIST_KEY_CFBundleDisplayName`) |
| `Documentation.docc/` | 要件定義書、基本設計書、詳細設計書 |
| `packages/DomainModels/` | `content/schemas` に対応する Swift の値型(`Question`、`Choice`、`Flashcard`、`CaseStudy` など) |
| `packages/Domain/` | 学習・採点ロジックとコンテンツ提供のインターフェース |
| `packages/Data/` | `ContentKit`。署名付きパックの検証、遅延読み込み、整合チェック、保存・ロールバック、同梱カタログと起動処理 |
| `content/` | 学習コンテンツ(YAML / Markdown)、JSON Schema、検証スクリプト。詳細は [content/README.md](content/README.md) |
| `.github/workflows/` | CI。変更されたパスに応じて、必要なワークフローだけが動きます |

起動時は同梱版と現在有効なインストール版を SemVer で比較し、新しい方を使います。同じ優先順位ならインストール版を維持し、内容の整合確認後に有効化します。実装状況と検証結果は [P2 コンテンツパック](Documentation.docc/DDD/DDD-P2-ContentPack.md) を参照してください。

## ローカルでの検証

```sh
cd /path/to/google-cloud-professional-cloud-architect

# 初回のみ: uv で Python 3.14 の仮想環境(content/.venv)を作る
uv sync --project content

# コンテンツのテスト
(cd content && .venv/bin/pytest)

# コンテンツの検証(どのディレクトリから実行しても対象は content/)
content/.venv/bin/python content/scripts/validate.py
content/.venv/bin/python content/scripts/validate.py --exam gcp-pca  # 試験を絞る
content/.venv/bin/python content/scripts/validate.py --check-links   # リンク切れの確認も行う

# Swift のテスト
swift test --package-path packages/DomainModels
swift test --package-path packages/Domain
swift test --package-path packages/Data
```

`swift test` が `plugin for module 'TestingMacros' not found` で失敗する場合は、Xcode のツールチェーンを指定してください。
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/DomainModels`
(恒久的に切り替える場合は `sudo xcode-select -s /Applications/Xcode.app`)

## CI

| ワークフロー | 実行条件 | 内容 |
|---|---|---|
| `content-validate.yml` | PR、`main` への push(`content/**`、`packages/DomainModels/**` の変更時) | `pytest` と `validate.py --format github` |
| `domainmodels-test.yml` | PR、`main` への push(`packages/DomainModels/**`、`content/schemas/**`、`content/tests/fixtures/**` の変更時) | `swift test --package-path packages/DomainModels`(macOS) |
| `data-test.yml` | PR、`main` への push（Data・Domain・DomainModels・fixture の変更時） | `swift test --package-path packages/Data`。Python製パックをSwiftで検証 |
| `content-link-check.yml` | 毎週月曜 00:00 UTC、手動実行 | 参照 URL のリンク切れ確認 |

## リリースタグの命名規則

| 対象 | 形式 | 例 |
|---|---|---|
| コンテンツ(試験ごと) | `content/<examID>/vX.Y.Z` | `content/gcp-pca/v1.2.0` |
| アプリ | `app-vX.Y.Z` | `app-v1.0.0` |

コンテンツは試験ごとにパックを作り、版を管理します。バージョンは、その試験の配信パックの `manifest.json` の `packVersion` と一致させます。

## 運用ルール

> [!IMPORTANT]
> **Schema を変更したら `packages/DomainModels` も同じ PR で更新し、両方のテストを通すこと。**
>
> 1. `content/schemas/*.schema.json` を変更する
> 2. `packages/DomainModels/Sources/` の型を更新する
> 3. fixture と JSON を再生成する(`content/tests/fixtures/generate.py`、`content/scripts/export_json.py`)
> 4. `pytest` と `swift test` の両方が通ることを確認する

## アプリから DomainModels を使う

`ExamPrepApp.xcodeproj` には、`packages/DomainModels` がローカルパッケージとして登録済みです(ExamPrepApp ターゲットにリンク済み)。
アプリのソースで `import DomainModels` と書けば使えます。Xcode のナビゲーターでは **Package Dependencies** の下に表示されます。

パッケージはリポジトリ内の相対パス(`relativePath = packages/DomainModels`)で参照されるため、クローンした場所に関係なく動作します。
別のパッケージを追加する場合は、`project.pbxproj` を手で編集せず、Xcode の **File > Add Package Dependencies… > Add Local…** から追加してください。

## 命名規則

| 対象 | 規則 | 例 |
|---|---|---|
| リポジトリのフォルダ | 小文字の kebab-case(GitHub のリポジトリ名に対応) | `google-cloud-professional-cloud-architect` |
| Xcode のプロジェクト・ターゲット・ソースフォルダ | PascalCase、スペースや記号なし。表示名と切り離した中立な名前にする | `ExamPrepApp` |
| Swift パッケージ | PascalCase | `DomainModels` |
| 利用者に見せるアプリ名 | `INFOPLIST_KEY_CFBundleDisplayName` で設定(日本語・スペース可)。表示名を変えるときはここだけを変更する | `Cloudrill` |
