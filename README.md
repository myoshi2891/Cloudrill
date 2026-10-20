# Google Cloud Professional Cloud Architect 試験対策アプリ

PCA 試験対策 iOS アプリと、その学習コンテンツを1つのリポジトリで管理するモノレポです。
コンテンツの JSON Schema と、Swift の `Codable` 定義を、1つのコミット・PR で同時に変更できます。

## ディレクトリ構成

```
Google Cloud Professional Cloud Architect/
├── Google Cloud Professional Cloud Architect/       # iOS アプリのソース
├── Google Cloud Professional Cloud Architect.xcodeproj
├── Documentation.docc/                              # 要件定義書(RDD.md)、基本設計書(BDD.md)
├── packages/
│   └── DomainModels/                                # コンテンツの値型(SwiftPM、Swift Testing)
├── content/                                         # 学習コンテンツ、JSON Schema、検証ツール
│   ├── schemas/                                     # JSON Schema(Draft 2020-12)
│   ├── questions/ flashcards/ cases/ decisions/ drills/ docs/
│   ├── exam-sets.yaml  weights.yaml  validation.yaml
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
| `Google Cloud Professional Cloud Architect/` と `.xcodeproj` | iOS アプリ本体。Xcode の参照パスや署名設定を壊さないよう、ルート直下に置いたままにしています |
| `Documentation.docc/` | 要件定義書と基本設計書 |
| `packages/DomainModels/` | `content/schemas` に対応する Swift の値型(`Question`、`Choice`、`Flashcard`、`CaseStudy` など) |
| `content/` | 学習コンテンツ(YAML / Markdown)、JSON Schema、検証スクリプト。詳細は [content/README.md](content/README.md) |
| `.github/workflows/` | CI。変更されたパスに応じて、必要なワークフローだけが動きます |

## ローカルでの検証

ルートのディレクトリ名にスペースが含まれるため、パスは必ずクォートしてください。

```sh
cd "/path/to/Google Cloud Professional Cloud Architect"

# 初回のみ: Python 3.14 の仮想環境を作る
python3.14 -m venv content/.venv
content/.venv/bin/pip install -r content/requirements.txt

# コンテンツのテスト
(cd content && .venv/bin/pytest)

# コンテンツの検証(どのディレクトリから実行しても対象は content/)
content/.venv/bin/python content/scripts/validate.py
content/.venv/bin/python content/scripts/validate.py --check-links   # リンク切れの確認も行う

# Swift のテスト
swift test --package-path packages/DomainModels
```

`swift test` が `plugin for module 'TestingMacros' not found` で失敗する場合は、Xcode のツールチェーンを指定してください。
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/DomainModels`
(恒久的に切り替える場合は `sudo xcode-select -s /Applications/Xcode.app`)

## CI

| ワークフロー | 実行条件 | 内容 |
|---|---|---|
| `content-validate.yml` | PR、`main` への push(`content/**`、`packages/DomainModels/**` の変更時) | `pytest` と `validate.py --format github` |
| `domainmodels-test.yml` | PR、`main` への push(`packages/DomainModels/**`、`content/schemas/**`、`content/tests/fixtures/**` の変更時) | `swift test --package-path packages/DomainModels`(macOS) |
| `content-link-check.yml` | 毎週月曜 00:00 UTC、手動実行 | 参照 URL のリンク切れ確認 |

## リリースタグの命名規則

| 対象 | 形式 | 例 |
|---|---|---|
| コンテンツ | `content-vX.Y.Z` | `content-v1.2.0` |
| アプリ | `app-vX.Y.Z` | `app-v1.0.0` |

コンテンツのバージョンは、配信パックの `manifest.json` の `packVersion` と一致させます。

## 運用ルール

> [!IMPORTANT]
> **Schema を変更したら `packages/DomainModels` も同じ PR で更新し、両方のテストを通すこと。**
>
> 1. `content/schemas/*.schema.json` を変更する
> 2. `packages/DomainModels/Sources/` の型を更新する
> 3. fixture と JSON を再生成する(`content/tests/fixtures/generate.py`、`content/scripts/export_json.py`)
> 4. `pytest` と `swift test` の両方が通ることを確認する

## アプリから DomainModels を使う(Xcode での設定)

`project.pbxproj` は手で編集せず、Xcode から追加してください。

1. `Google Cloud Professional Cloud Architect.xcodeproj` を Xcode で開く
2. メニューの **File > Add Package Dependencies…** を選ぶ
3. ダイアログ左下の **Add Local…** をクリックし、`packages/DomainModels` フォルダを選ぶ
4. 追加先のターゲットに **Google Cloud Professional Cloud Architect**(アプリ)を選び、**Add Package** をクリックする
5. ソースで `import DomainModels` と書いてビルドできることを確認する

パッケージはリポジトリ内の相対パスで参照されるため、クローンした場所に関係なく動作します。
