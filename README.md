# Google Cloud Professional Cloud Architect 試験対策アプリ

クラウド認定試験対策 iOS アプリ「Cloudrill」(最初の対象は Google Cloud PCA)と、その学習コンテンツを1つのリポジトリで管理するモノレポです。
コンテンツの JSON Schema と、Swift の `Codable` 定義を、1つのコミット・PR で同時に変更できます。

## ディレクトリ構成

```
google-cloud-professional-cloud-architect/
├── ExamPrepApp/                                     # iOS アプリのソース
├── ExamPrepApp.xcodeproj                            # DomainModels・AppComposition をローカル参照
├── Documentation.docc/                              # 要件定義書(RDD.md)、基本設計書(BDD.md)
├── packages/
│   ├── DomainModels/                                # コンテンツの値型(SwiftPM、Swift Testing)
│   ├── Domain/                                      # 学習・採点ロジック、DomainInterfaces
│   ├── Data/                                        # ContentKit と Persistence: パック管理・学習履歴の永続化
│   ├── Presentation/                                # AppCore・HomeFeature・ExamFeature
│   └── AppComposition/                              # アプリ用の依存組み立て・起動画面
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
| `packages/Data/` | `ContentKit`（署名付きパックの検証・読み込み・保存・起動処理）と `Persistence`（SwiftData による学習履歴・設定の永続化） |
| `packages/Presentation/` | `AppCore`（依存注入、試験選択・切り替え、画面遷移）、`HomeFeature`（試験選択 ViewModel）、`ExamFeature`（選択式問題のレンダラー） |
| `packages/AppComposition/` | `AppEnvironment`（実リポジトリとコンテンツの組み立て）、DEBUG専用の起動引数、`AppRootView`（起動状態・試験選択・試験概要） |
| `content/` | 学習コンテンツ(YAML / Markdown)、JSON Schema、検証スクリプト。詳細は [content/README.md](content/README.md) |
| `.github/workflows/` | CI。変更されたパスに応じて、必要なワークフローだけが動きます |

起動時は同梱版と現在有効なインストール版を SemVer で比較し、新しい方を使います。同じ優先順位ならインストール版を維持し、内容の整合確認後に有効化します。実装状況と検証結果は [P2 コンテンツパック](Documentation.docc/DDD/DDD-P2-ContentPack.md) を参照してください。

永続化層は [P3-S01〜S09](Documentation.docc/DDD/DDD-P3-Persistence.md) の実装・ローカル検証を完了しています。モデル・コンテナ生成、受験記録（`SwiftDataExamAttemptRepository`）・解答履歴（`SwiftDataAnswerHistoryRepository`）・カード・ブックマーク／既読・設定のリポジトリ、同期後の重複統合、JSON エクスポート・削除、V1 の移行計画を備えています。保存には1回の再試行と失敗時の取り消しを設けています。ディスク保存先にはアプリ側で解決した App Group の URL を渡します。リモート CI の確認は別途必要です。

## ローカルでの検証

[P4 アプリ MVP](Documentation.docc/DDD/DDD-P4-AppMVP.md) は基盤と起動処理を実装中です。Presentation は Data に依存せず、アプリ専用の AppComposition で具体的なリポジトリを組み立てます。Xcodeへの依存追加と起動画面の接続は完了し、起動・試験選択のUIテストを追加しています。S05のホーム（今日の学習・弱点・復習期限のカード数・模試の再開）と5タブを接続済みです。遷移先の練習・模試・カード画面は後続作業です。

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
swift test --package-path packages/Presentation
swift test --package-path packages/AppComposition
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
| `presentation-test.yml` | PR、`main` への push（Presentation・Domain・DomainModels・JSON fixture の変更時） | `swift test --package-path packages/Presentation`。試験選択・画面遷移の状態管理を検証 |
| `app-test.yml` | PR、`main` への push（アプリ・packages・パック同梱スクリプトの変更時） | AppComposition の起動・永続化・同梱署名テストとReleaseビルド。PRではSimulator向けビルド、mainへのpush・手動実行では起動UIテストも実行 |
| `content-link-check.yml` | 毎週月曜 00:00 UTC、手動実行 | 参照 URL のリンク切れ確認 |

開発用パックは `bash scripts/bundle_packs.sh --development --out <新規ディレクトリ>` で再生成できます。出力先の既定値は `ExamPrepApp/Resources/Packs` です。既存出力は上書きしません。生成結果はコミット対象で、公開鍵のみを含み、秘密鍵は保存しません。開発用の印が付いたパックは `AppEnvironment.live` が拒否します。本番パック・App Group設定は別途必要です。

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

`ExamPrepApp.xcodeproj` には、`packages/DomainModels` と `packages/AppComposition` がローカルパッケージとして登録済みです(ExamPrepApp ターゲットにリンク済み)。
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
