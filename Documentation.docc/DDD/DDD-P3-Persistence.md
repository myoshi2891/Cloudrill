# Cloudrill 詳細設計書 P3: 学習履歴の永続化

| 項目 | 内容 |
|---|---|
| 文書バージョン | 0.1(初版ドラフト) |
| 作成日 | 2026-10-21 |
| 上位文書 | [詳細設計書(索引・共通設計)](../DDD.md) |
| 対象 | `packages/Data` の `Persistence`、`packages/Domain` の `DomainInterfaces`(リポジトリのプロトコル) |
| ステータス | P3-S01〜S09 の実装・ローカル検証完了。リモート CI は利用者側で確認する |

---

## 目次

1. [目的とスコープ](#1-目的とスコープ)
2. [前提](#2-前提)
3. [設計](#3-設計)
4. [ステップ](#4-ステップ)
5. [フェーズの完了条件](#5-フェーズの完了条件)
6. [申し送り](#6-申し送り)

---

## 1. 目的とスコープ

学習履歴を SwiftData に保存するリポジトリを作る。最初から CloudKit との同期を前提にしたモデルにし、すべての記録を試験ごとに分ける([DDD 2 章 C-08](../DDD.md#2-基本設計書からの変更点))。

| 区分 | 内容 |
|---|---|
| スコープ内 | SwiftData のモデル(V1)、リポジトリのプロトコルと実装、同期後の重複の統合、データのエクスポートと全削除、移行計画の配線 |
| スコープ外 | CloudKit 同期の有効化(P6-S15。モデルは本フェーズで同期できる形にしておく)、画面(P4) |

---

## 2. 前提

- P1 が完了している(`AnswerFact`、`ExamSession.Snapshot`、`FSRSCard`、`ReviewOutcome` を使う)。
- P2 と並行して進めてよい。
- ブランチは利用者の指定により `dev` を維持する。プッシュ・PR 操作は利用者が担当する。

---

## 3. 設計

### 3.1 モデル(SchemaV1)

BDD 5.3 のエンティティに `examID` を加え、試験ごとの設定を `ExamPreference` に分ける。

```mermaid
erDiagram
    ExamAttempt ||--o{ AnswerRecord : has
    CardState ||--o{ ReviewLog : has
    ExamAttempt {
        UUID id
        string examID
        int examSet
        string packVersion
        date startedAt
        string statusRaw
        string submitReasonRaw
        date submittedAt
        int correctCount
        int totalCount
        data sessionSnapshotJSON
    }
    AnswerRecord {
        UUID id
        string examID
        string questionID
        int questionRevision
        int domain
        string subObjective
        string caseStudy
        data selectionJSON
        bool isCorrect
        string modeRaw
        int elapsedSeconds
        date answeredAt
    }
    CardState {
        UUID id
        string examID
        string cardID
        data fsrsCardJSON
        date due
        date lastReview
    }
    ReviewLog {
        UUID id
        string examID
        string cardID
        int rating
        double elapsedDays
        date reviewedAt
    }
    PracticeServeLog {
        UUID id
        string examID
        string questionID
        date servedAt
    }
    Flag {
        UUID id
        string examID
        string questionID
        date createdAt
    }
    Bookmark {
        UUID id
        string examID
        string targetType
        string targetID
        date createdAt
    }
    ReadMark {
        UUID id
        string examID
        string docSubObjective
        date readAt
    }
    UserSettings {
        UUID id
        string currentExamID
        string displayLanguage
        bool notificationsEnabled
        bool shuffleChoices
        date updatedAt
    }
    ExamPreference {
        UUID id
        string examID
        date examDate
        int dailyNewCards
        int dailyReviewLimit
        double desiredRetention
        bool autoCardFromMistakes
        date updatedAt
    }
```

| 方針 | 内容 | 理由 |
|---|---|---|
| CloudKit の制約 | `@Attribute(.unique)` を使わない。すべてのプロパティに既定値を付けるか、省略可能にする。リレーションはすべて省略可能 | BDD 5.3 の注記 |
| 列挙値 | `String` で保存し、`…Raw` の名前にする。読み出し時に enum に変換し、未知の値は `PersistenceError.corrupted` にする | SwiftData の列挙値の扱いと、移行のしやすさ |
| 構造を持つ値 | `AnswerSelection`、`ExamSession.Snapshot`、`FSRSCard` は JSON(`Data`)で保存する | 出題形式を追加しても、モデルの移行が要らない |
| 検索に使う値 | `examID`、`questionID`、`due` などは、JSON の外に列として持つ | `#Predicate` で絞り込むため |
| 追記のみの記録 | `AnswerRecord`、`ReviewLog`、`PracticeServeLog` は更新しない | 同期の競合を起こさない(BDD 6.9) |
| 試験ごとの分離 | すべての検索に `examID` の条件を付ける | X-02 |

`Flag`(見直し用ではなく、練習の「フラグ付きのみ」用)と `PracticeServeLog`(直近 24 時間の出題の除外用)は、BDD 5.3 にない。P1-S10 の `PracticeHistory` を作るために追加した。

### 3.2 リポジトリのプロトコル(DomainInterfaces)

```swift
public enum PersistenceError: Error, Equatable, Sendable {
    case notFound
    case corrupted(String)
    case saveFailed(String)
}

public protocol ExamAttemptRepository: Sendable {
    func start(examID: ExamID, examSet: Int, packVersion: String, snapshot: ExamSession.Snapshot) async throws(PersistenceError) -> UUID
    func save(snapshot: ExamSession.Snapshot, for attemptID: UUID) async throws(PersistenceError)
    func record(_ answer: AnswerFact, in attemptID: UUID) async throws(PersistenceError)
    func finalize(attemptID: UUID, result: ExamResult, reason: SubmitReason, at date: Date) async throws(PersistenceError)
    func abandon(attemptID: UUID) async throws(PersistenceError)
    func inProgress(examID: ExamID) async throws(PersistenceError) -> AttemptSnapshot?
    func history(examID: ExamID) async throws(PersistenceError) -> [AttemptSummary]
}

public protocol AnswerHistoryRepository: Sendable {
    func record(_ answer: AnswerFact) async throws(PersistenceError)
    func answers(examID: ExamID) async throws(PersistenceError) -> [AnswerFact]
    func practiceHistory(examID: ExamID, now: Date) async throws(PersistenceError) -> PracticeHistory
    func markServed(questionIDs: [String], examID: ExamID, at date: Date) async throws(PersistenceError)
    func setFlag(_ flagged: Bool, questionID: String, examID: ExamID, at date: Date) async throws(PersistenceError)
}

public protocol CardStateRepository: Sendable {
    func card(id: String, examID: ExamID) async throws(PersistenceError) -> FSRSCard?
    func apply(_ outcome: ReviewOutcome, cardID: String, examID: ExamID) async throws(PersistenceError)
    func scheduledCards(examID: ExamID) async throws(PersistenceError) -> [(id: String, card: FSRSCard)]
    func reviewCount(examID: ExamID, on day: DateInterval) async throws(PersistenceError) -> (introduced: Int, reviewed: Int)
    func addCardFromQuestion(questionID: String, examID: ExamID, at date: Date) async throws(PersistenceError)
}
```

`BookmarkRepository`、`SettingsRepository`、`DataManagementRepository`(エクスポートと全削除)も、同じ形で定義する(P3-S05〜S08)。

- 問題由来のカードの ID は `Q:` + 問題 ID とする([DDD 4.7](../DDD.md#47-id-と一意性))。
- `AnswerHistoryRepository.record` と `ExamAttemptRepository.record` の両方が `AnswerRecord` を作る。前者は練習、後者は模試の記録で、`modeRaw` で区別する。

### 3.3 実装の方式

| 項目 | 方式 |
|---|---|
| 並行性 | 各リポジトリは `@ModelActor` の actor にする。`ModelContext` を actor の外に出さない |
| 返す値 | `@Model` のオブジェクトではなく、StudyModels の値型(`AnswerFact`、`AttemptSnapshot` など)に変換して返す |
| 保存 | 書き込みのたびに `save()` する(NFR-04)。失敗したら1回だけ再試行し、それでも失敗したら `PersistenceError.saveFailed` を投げる(E-05) |
| コンテナ | `ModelContainerFactory.make(inMemory:cloudKitContainer:storeDirectory:)`。テストはインメモリ、アプリは App Group の URL を `storeDirectory` に渡す。ディスク保存で保存先を省略するとエラー |

---

## 4. ステップ

### P3-S01 SchemaV1 とコンテナ

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-ACCT-01、NFR-09、BDD 5.3 |
| 前提 | P1 の完了 |
| 成果物 | `packages/Data/Sources/Persistence/SchemaV1.swift`、`ModelContainerFactory.swift`、`Tests/PersistenceTests/SchemaV1Tests.swift` |

**Red**:

| テスト | 条件(Arrange) | 期待(Assert) |
|---|---|---|
| `containerOpensInMemory` | `make(inMemory: true, cloudKitContainer: nil)` | 例外なく開ける |
| `allPropertiesHaveDefaults` | `SchemaV1.models` の各型を、引数なしの初期化子で作る | 作れる(CloudKit の制約。既定値の付け忘れを検出する) |
| `noUniqueAttributes` | `Schema(SchemaV1.models)` のエンティティを走査する | `unique` の制約がない |
| `relationshipsAreOptional` | 同上 | すべてのリレーションが省略可能 |
| `storeIsInAppGroup` | `make(inMemory: false, …)` に一時ディレクトリを渡す | ストアのファイルがそのディレクトリの中に作られる |

**Green**: [3.1](#31-モデルschemav1) のモデルを `enum SchemaV1: VersionedSchema` の中に定義する。

**Refactor**: 既定値(空文字、`.distantPast`)を定数にまとめる。

**完了条件**: `swift test --package-path packages/Data --filter SchemaV1Tests` が通る。

**実装メモ**(2026-10-27、P3-S01 完了):

- `Persistence` の library/target と `PersistenceTests` を追加した。空のターゲット用ファイルは削除し、`SchemaV1.swift` と `ModelContainerFactory.swift` に置き換えた。
- `SchemaV1` は 3.1 の10モデルと全列を持つ。構造値は Data、列挙値は文字列で保存する。`currentExamID`、`examDate`、`caseStudy`、提出情報、最終復習日時など、未設定がある列は Optional にした。UUID はレコードごとに生成する。
- `ExamAttempt.answers` ↔ `AnswerRecord.attempt`、`CardState.reviewLogs` ↔ `ReviewLog.cardState` のリレーションを明示し、両側を Optional にした。削除規則は `.nullify`（同期後の重複統合で親を削除しても追記のみの履歴を巻き添えにしないため）。CloudKit の実同期は P6-S15 で確認する。
- 引数なしのモデル生成に加えて、`Schema.Attribute.defaultValue` または Optional、unique 制約なし、逆リレーションをテストした。共通の空文字・Data・日時は内部の `SchemaV1Defaults` に集約した。JSON の初期値は空の Data なので、S02 以降のリポジトリが保存前に実際の値をエンコードして設定する。
- ファクトリーは `storeDirectory: URL? = nil` を追加した。ディスクでは指定先に `StudyHistory.store` を作る。保存先なしは `ModelContainerFactoryError.storeDirectoryRequired`、非 file URL は `.invalidStoreDirectory`。ディレクトリ作成や SwiftData の I/O エラーは呼び出し側へ伝える。App Group の URL は P4 のアプリ側で解決する。
- インメモリでは保存先の指定があってもファイルを作らず、CloudKit も無効にする。ディスクでは `cloudKitContainer: nil` を明示的な同期無効として扱い、ID があるときは private database の設定に渡す。実アカウントを使った同期は今回のテスト対象外。

TDD の確認記録:

| コミット | 段階・結果 |
|---|---|
| `528d461` | 6テストを先行追加。型未定義の最初のコンパイル Red |
| `87d5180` | 最小モデルと常にインメモリを返す仮実装で assertion Red を確認。列不足10件、リレーション不足1件、保存設定の不一致2件。既存 ContentKit 70テストは成功 |
| `a9698b0` | 保存先の指定漏れ・非 file URL・再オープン後のデータ保持を追加し、3テスト4件の assertion 失敗を確認。インメモリでファイルも CloudKit 接続も作らないテストも追加 |
| `ca10468` | 10モデルとコンテナ生成を実装。SchemaV1Tests 10件と既存 ContentKit 70件が成功 |
| `45bd033` | 共通の既定値を整理し、同じ全80テストの成功を再確認 |

最初の仮実装で型が解決した際、Swift Testing のマクロ展開で `allSatisfy(\.isOptional)` がコンパイルエラーになったため、同じ条件の明示的なクロージャへ変更した。期待値は変更していない。

検証コマンド:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/Data --filter SchemaV1Tests
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/Data
```

P3-S02〜S09 の実装内容は各節、最終検証は第5節を参照。リモート CI は利用者が実施するため、フェーズ全体の完了判定はその確認後に行う。

---

### P3-S02 模試の受験の記録(ExamAttemptRepository)

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-EXAM-04、FR-EXAM-07、NFR-04、AC-02、E-05、E-07 |
| 前提 | P3-S01 |
| 成果物 | `Sources/Persistence/SwiftDataExamAttemptRepository.swift`、`DomainInterfaces/ExamAttemptRepository.swift`、`Tests/PersistenceTests/ExamAttemptRepositoryTests.swift` |

**Red**:

| テスト | 条件(Arrange) | 期待(Assert) |
|---|---|---|
| `startAndFindInProgress` | `test-alpha` の模試1を開始する | `inProgress(examID: test-alpha)` がその受験を返す |
| `inProgressIsPerExam` | `test-alpha` だけ開始する | `inProgress(examID: test-beta)` は `nil` |
| `snapshotRoundTrip` | 解答・フラグ・現在位置・タイマーを持つスナップショットを保存し、読み直す | 元の値と等しい(AC-02 の前提) |
| `recordEachAnswer` | 3 回 `record` する | `AnswerRecord` が 3 件。`modeRaw == "exam"` |
| `recordSurvivesNewContainer` | ファイルのストアで記録し、別のコンテナで開き直す | 記録が読める(強制終了後の復元の代わり) |
| `finalizeSetsResult` | `finalize` | `statusRaw == "submitted"`、`correctCount`・`totalCount` が結果と一致、`inProgress` は `nil` |
| `finalizeTwiceFails` | 提出済みの受験に `finalize` | `PersistenceError.corrupted` |
| `packVersionIsKept` | 1.0.0 で開始した受験 | 読み出した `packVersion == "1.0.0"`(E-07。P2 の `pin` と組み合わせる) |
| `history` | 提出済み 2 件、放棄 1 件 | `history` は提出済みの 2 件を新しい順に返す |
| `saveRetriesOnce` | 1回目の保存だけ失敗する `ModelContext` の代替(`FailingSaver`) | 2回目で成功し、エラーにならない |
| `saveFailsAfterRetry` | 2回とも失敗する | `PersistenceError.saveFailed` |

`save()` の失敗を再現するため、保存処理を `Saver` プロトコルで包み、テストで差し替える。

**Green**: [3.2](#32-リポジトリのプロトコルdomaininterfaces) の `ExamAttemptRepository` を実装する。

**Refactor**: `@Model` と値型の変換を `…Mapper` に分ける。

**完了条件**: `swift test --package-path packages/Data --filter ExamAttemptRepositoryTests` が通る。

**実装メモ**:

- `24a0ccb` の仮実装で6テスト・15件の assertion 失敗を確認し、`788af27` で Green。テストは表の関連する条件をまとめて確認する（再開・スナップショット・版の保持、3件の解答と提出、提出後の再提出拒否、履歴の順序と放棄の除外、ファイルストアの再オープン、保存の再試行、試験の取り違え・存在しない受験）。
- `SwiftDataExamAttemptRepository` は `@ModelActor`。`AttemptMapper`・`AnswerMapper` がモデルと値型の変換を担当する。開始日時は開始時の snapshot の `timer.deadline - duration` から復元する。開始 API は模試開始時に呼び、後から既存の受験を作り直す用途には使わない。
- `AttemptSnapshot`・`AttemptSummary` は `DomainInterfaces` に置いた。`ExamSession.Snapshot` を参照するため、StudyModels に置くと ExamEngine との循環依存になる。DomainInterfaces の依存に ExamEngine・StudyModels・FSRS・QuestionSelector を追加した。ContentKit の検証器から採点レジストリを直接参照する変更はしていない。
- `Storage.write` を各リポジトリで共用する。自動保存を止め、actor 内の同期処理で変更と保存を行い、保存は1回だけ再試行する。最終失敗では `rollback()` して `.saveFailed` を返す。`Saver` を受験リポジトリの初期化時に差し替え、失敗後に未保存の受験が残らないことも確認した。
- 試験の一覧検索は `examID` で絞る。`save`・`record`・`finalize`・`abandon` は設計の API に従って受験 UUID で検索する例外で、`record` は受験の試験 ID と解答の試験 ID・モード・問題 ID も確認する。未知の status・submitReason・JSON は `.corrupted` にする。

---

### P3-S03 練習の解答履歴(AnswerHistoryRepository)

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-PRAC-03、FR-ANLY-01、BDD 6.7 |
| 前提 | P3-S02 |
| 成果物 | `Sources/Persistence/SwiftDataAnswerHistoryRepository.swift`、`Tests/PersistenceTests/AnswerHistoryRepositoryTests.swift` |

**Red**:

| テスト | 条件(Arrange) | 期待(Assert) |
|---|---|---|
| `lastResultUsesLatestAnswer` | 同じ問題に、不正解 → 正解の順で解答 | `practiceHistory.lastResult[Q] == true` |
| `examAnswersCountInHistory` | 模試で不正解だった問題 | 「間違えた問題のみ」の対象になる(`lastResult[Q] == false`) |
| `servedWithinWindow` | 25 時間前と 1 時間前に出題した問題 | 両方の `lastServedAt` が入る(24 時間の判定は QuestionSelector が行う) |
| `flagToggle` | `setFlag(true)` → `setFlag(false)` | `flagged` から外れる |
| `perExam` | `test-alpha` と `test-beta` に同じ問題 ID の記録 | 互いの履歴に混ざらない |
| `answersForReadiness` | 練習 2 件、模試 3 件、ドリル 1 件 | `answers(examID:)` が 6 件を返す(ドリルを除くのは Readiness の責務) |

**Green**: `AnswerHistoryRepository` を実装する。

**Refactor**: 検索条件(`#Predicate`)の組み立てを補助関数にまとめる。

**完了条件**: `swift test --package-path packages/Data --filter AnswerHistoryRepositoryTests` が通る。

**実装メモ**:

- `cb9ebda` で3テスト・6件の assertion Red、`4137202` で Green。練習・模試・ドリルの全モードを読み、直近の解答結果・出題時刻・フラグを試験ごとに返す。未知の保存モードは `.corrupted`。
- 出題時刻は24時間より古いものも返し、期間の判定を QuestionSelector に任せる。フラグの重複設定は増殖させず、解除では同期後の重複行もすべて消す。解答は時刻と UUID で決定論的に並べる。

---

### P3-S04 カードの状態と復習ログ(CardStateRepository)

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-CARD-02、FR-CARD-04、FR-CARD-05 |
| 前提 | P3-S01 |
| 成果物 | `Sources/Persistence/SwiftDataCardStateRepository.swift`、`Tests/PersistenceTests/CardStateRepositoryTests.swift` |

**Red**:

| テスト | 条件(Arrange) | 期待(Assert) |
|---|---|---|
| `applyCreatesStateAndLog` | 新規カードに Good を適用 | `CardState` が 1 件、`ReviewLog` が 1 件 |
| `applyUpdatesExisting` | 同じカードに 2 回適用 | `CardState` は 1 件のまま、`ReviewLog` は 2 件 |
| `fsrsCardRoundTrip` | 適用した `FSRSCard` を読み直す | 等しい |
| `dueColumnMatchesJSON` | 適用後 | `due` 列と、JSON の中の `due` が一致する |
| `reviewCountForDay` | 今日 3 枚の新規、5 回の復習、昨日 2 回 | `(introduced: 3, reviewed: 5)` |
| `cardFromQuestion` | 問題 Q-1.1-0001 からカードを作る | ID が `Q:Q-1.1-0001` の新規カード |
| `cardFromQuestionIsIdempotent` | 同じ問題から 2 回作る | 1 件のまま |

**Green**: `CardStateRepository` を実装する。

**Refactor**: 日付の範囲(今日)の計算は、呼び出し側から `DateInterval` で受け取り、リポジトリでは計算しない。

**完了条件**: `swift test --package-path packages/Data --filter CardStateRepositoryTests` が通る。

**実装メモ**:

- `637489c` で3テスト・8件の assertion Red、`c462d80` で Green。FSRSCard の往復、状態1件に対するログの追記、due 列との一致、問題カードの重複防止、試験分離を確認した。
- 日別の新規数はカードごとの最初の復習ログが範囲に入る件数、復習数は範囲内の残りのログ数とする。範囲は `start <= reviewedAt < end`。過去のログも参照して新規かどうかを判定するため、昨日に導入したカードを今日の新規には数えない。
- 同期直後の重複した CardState は `lastReview` が新しい行（同時刻なら UUID の小さい行）を読んで更新する。重複行自体の削除は S07。ログの rating が未知なら `.corrupted` にする。

---

### P3-S05 ブックマークと既読

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-DOCS-05 |
| 前提 | P3-S01 |
| 成果物 | `Sources/Persistence/SwiftDataBookmarkRepository.swift`、`DomainInterfaces/BookmarkRepository.swift`、`Tests/PersistenceTests/BookmarkRepositoryTests.swift` |

**Red**:

| テスト | 条件(Arrange) | 期待(Assert) |
|---|---|---|
| `toggleBookmark` | 問題を 2 回ブックマークする | 2 回目で外れる |
| `bookmarksByType` | 問題 2 件、ドキュメント 1 件 | 種別で絞り込める |
| `markRead` | ドキュメント 3.2 を既読にする | `isRead(3.2) == true` |
| `markReadIsIdempotent` | 2 回既読にする | `ReadMark` は 1 件 |
| `unknownTargetType` | 保存されていた `targetType` が未知の値 | `PersistenceError.corrupted` |

**Green**: `BookmarkRepository` を実装する。`targetType` は `question` / `doc` の enum にする。

**Refactor**: なし。

**完了条件**: `swift test --package-path packages/Data --filter BookmarkRepositoryTests` が通る。

**実装メモ**:

- `4c823ac` で3テスト・8件の assertion Red、`3bd433d` で Green。`BookmarkTarget` は question/doc、公開 API は `toggleBookmark(targetType:targetID:examID:at:)`、`bookmarks(examID:type:)`、`markRead(_:examID:at:)`、`isRead(_:examID:)` とした。
- `toggleBookmark` は追加時 true、解除時 false を返す。既読は何度呼んでも1件。種別・試験分離・未知の保存種別の拒否を確認した。返り値はモデルではなく `BookmarkEntry`。

---

### P3-S06 設定と試験ごとの設定

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-CARD-05、FR-EXAM-12、FR-PLAN-01、[DDD 4.1 X-02](../DDD.md#41-拡張性の設計方針) |
| 前提 | P3-S01 |
| 成果物 | `Sources/Persistence/SwiftDataSettingsRepository.swift`、`DomainInterfaces/SettingsRepository.swift`、`StudyModels/Settings.swift`、`Tests/PersistenceTests/SettingsRepositoryTests.swift` |

**Red**:

| テスト | 条件(Arrange) | 期待(Assert) |
|---|---|---|
| `defaultsWhenEmpty` | 何も保存していない | `UserSettings` の既定値(表示言語 `ja`、シャッフルなし)と、`ExamPreference` の既定値(新規 20 枚、復習 200 枚、保持率 0.90、誤答のカード化 ON) |
| `preferenceIsPerExam` | `test-alpha` の試験日だけを設定する | `test-beta` の試験日は `nil` |
| `currentExam` | `currentExamID` を `test-beta` にする | 読み直すと `test-beta` |
| `retentionValidated` | `ExamPreference(desiredRetention: 0.99)` を作る | `SettingsError.outOfRange`(値の検証は StudyModels の初期化子で行い、リポジトリには不正な値が届かない) |
| `duplicateRowsResolvedByUpdatedAt` | 同じ試験の `ExamPreference` が 2 件ある(同期後の状態を再現) | `updatedAt` の新しい方を返す(統合そのものは P3-S07) |

既定値(新規 20 枚、復習 200 枚)は BDD に記載がないため、本書で決める。設定画面で変更できる(FR-CARD-05)。

**Green**: `SettingsRepository` を実装する。

**Refactor**: 既定値を `ExamPreference.default` に集める。

**完了条件**: `swift test --package-path packages/Data --filter SettingsRepositoryTests` が通る。

**実装メモ**:

- `aa9cd56` で4テスト・7件の assertion Red を確認し、`bdbf40f` で Green。空のストアの既定値、選択中の試験の保存、試験日の分離、重複設定の最新版の選択、未知の保存言語の拒否を確認した。保持率のテストは 0.99・0.79・NaN の3ケース。
- `StudyModels.UserSettings` と `ExamPreference` は値型。保持率とカード数は外から直接変更できず、初期化時に検証する。SchemaV1 の試験設定の既定値も `ExamPreference.default` を参照する。スキーマの列は変えていない。
- 公開 API は `settings()`、`preference(examID:)`、`save(settings:at:)`、`save(preference:examID:at:)`。全体設定のみ試験 ID で絞らず、試験設定は必ず絞る。重複時は updatedAt の新しい行、同日時は UUID の小さい行を使う。重複の削除は S07。

---

### P3-S07 同期後の重複の統合

| 項目 | 内容 |
|---|---|
| 対応要件 | BDD 6.9、FR-ACCT-01 |
| 前提 | P3-S02〜S06 |
| 成果物 | `Sources/Persistence/SyncMerge.swift`(純粋関数)、`SyncDeduplicator.swift`(SwiftData への適用)、`Tests/PersistenceTests/SyncMergeTests.swift` |

統合の規則は純粋関数にし、表形式で確認する。SwiftData への適用は薄い層にする。

| 対象 | 重複の判定 | 残す方 |
|---|---|---|
| `CardState` | `(examID, cardID)` | `lastReview` が新しい方。同じなら `id` の小さい方(決定論のため) |
| `ExamPreference` | `examID` | `updatedAt` が新しい方 |
| `UserSettings` | 常に1件 | `updatedAt` が新しい方 |
| `ExamAttempt`(進行中) | `(examID, examSet)` かつ `statusRaw == inProgress` | スナップショットの `currentIndex` が大きい方。もう一方は `abandoned` にし、利用者に通知する(BDD 6.9) |
| `Flag`、`Bookmark`、`ReadMark` | `(examID, 対象)` | `createdAt`（`ReadMark` は `readAt`）が古い方 |
| `AnswerRecord`、`ReviewLog`、`PracticeServeLog` | 統合しない(UUID で区別され、追記のみ) | — |

**Red**:

| テスト | 条件(Arrange) | 期待(Assert) |
|---|---|---|
| `cardStateKeepsLatestReview`(表形式) | `lastReview` が異なる 2 件 / 同じ 2 件 / 片方が `nil` | 上の規則のとおり |
| `preferenceKeepsLatest` | `updatedAt` が異なる 2 件 | 新しい方 |
| `inProgressAttemptsResolved` | 同じ模試の進行中が 2 件(`currentIndex` 12 と 30) | 30 の方が残り、12 の方は `abandoned`。結果に `notifyUser == true` |
| `differentExamsAreNotDuplicates` | `test-alpha` と `test-beta` の同じ `cardID` | どちらも残る |
| `appendOnlyUntouched` | `AnswerRecord` が 2 件(内容が同じ) | 2 件とも残る |
| `deduplicatorAppliesPlan` | インメモリのストアに重複を作り、`SyncDeduplicator.run()` | 規則どおりに削除・更新される |

**Green**: `SyncMerge`(入力は値型の配列、出力は「残す ID」と「変更する ID」の計画)と、それを適用する `SyncDeduplicator` を実装する。

**Refactor**: 種類ごとの規則を、キーと比較関数の組の表にする。

**完了条件**: `swift test --package-path packages/Data --filter SyncMergeTests` が通る。

**実装メモ**(2026-10-28):

- `be43ebf` で7テスト・22件の assertion Red、`7b6b880` で統合テストを含む8テストが Green。`SyncMerge` は値型から計画を返し、`SyncDeduplicator` が ModelActor 内で適用する。
- 種類ごとの比較規則を表にまとめた。同時刻・同進捗は UUID の小さい行を残し、計画内の ID も整列する。`lastReview == nil` は実日時より古い。試験と対象の複合キーを使い、異なる試験を統合しない。
- 追記のみの記録と完了済み受験は残す。重複した CardState の削除後も ReviewLog は残る。受験の放棄は `statusRaw` とスナップショットの状態を同時に変更し、`Plan.notifyUser` で通知の必要性を返す。
- 変更前に進行中の全スナップショットを読み取り、破損時は削除・更新しない。保存は `Storage.write` を使う。全件の取得は、S08 と共用する内部型 `PersistenceRows` に集約した。

---

### P3-S08 エクスポートと全削除

| 項目 | 内容 |
|---|---|
| 対応要件 | FR-ACCT-03、BDD 8.3「データの削除」、NFR-09 |
| 前提 | P3-S07 |
| 成果物 | `Sources/Persistence/DataManagement.swift`、`DomainInterfaces/DataManagementRepository.swift`、`Tests/PersistenceTests/DataManagementTests.swift` |

**Red**:

| テスト | 条件(Arrange) | 期待(Assert) |
|---|---|---|
| `exportContainsAllEntities` | 各エンティティを 1 件以上保存する | エクスポートの JSON に、全エンティティの全件が含まれる |
| `exportIsVersioned` | エクスポート | 先頭に `"exportVersion": 1` と `"schema": "V1"` |
| `exportCanFilterByExam` | `examID: test-alpha` を指定 | `test-beta` の記録を含まない |
| `exportIsDeterministic` | 同じデータで 2 回 | キーの並びと配列の順(`id` の昇順)が同じ |
| `deleteAllRemovesEverything` | `deleteAll()` | 全エンティティが 0 件 |
| `deleteExamOnly` | `deleteAll(examID: test-alpha)` | `test-beta` の記録と `UserSettings` は残る |

CloudKit 上のデータも消えることは、同期を有効にする P6-S15 で、実機の手動テストで確認する。

**Green**: `DataManagementRepository` を実装する。エクスポートは `ExportDocument`(Codable)に変換して JSON にする。

**Refactor**: エンティティごとの変換を、エクスポートと統合(P3-S07)で共有できるようにする。

**完了条件**: `swift test --package-path packages/Data --filter DataManagementTests` が通る。

**実装メモ**(2026-10-28):

- `87ac42b` で4テストの assertion Red、`e1048f8` で Green。表の検証項目を4テストにまとめ、全10モデルの全属性・リレーション、試験間の分離、決定論、削除失敗時の取り消しを確認した。
- `DataManagementRepository` の `export(examID:)` は Data、`deleteAll(examID:)` は Void を返す。`nil` は全試験と UserSettings が対象。試験指定時は各検索を examID で絞り、エクスポートにも削除にも UserSettings を含めない。
- JSON は `exportVersion: 1`、`schema: "V1"`、`entities` にモデル名をキーとする配列を持つ。属性名は SchemaV1 と一致し、Date は小数を含む Unix 秒、Data は Base64、リレーションは UUID または UUID の配列、未設定値は null。レコードとリレーションの配列は UUID 順、オブジェクトのキーも整列する。
- `PersistenceRows` が取得を共用し、`ExportDocument` が JSON に変換する。削除には `Storage.write` の再試行・rollback を使い、保存が2回失敗しても元の全データが同一コンテキストと別のリポジトリの両方から読めることを確認した。

---

### P3-S09 移行計画の配線

| 項目 | 内容 |
|---|---|
| 対応要件 | 将来のモデル変更への備え |
| 前提 | P3-S08 |
| 成果物 | `Sources/Persistence/MigrationPlan.swift`、`Tests/PersistenceTests/MigrationPlanTests.swift` |

**Red**:

| テスト | 条件(Arrange) | 期待(Assert) |
|---|---|---|
| `planListsSchemas` | `ExamPrepMigrationPlan.schemas` | `[SchemaV1.self]` |
| `containerUsesPlan` | `ModelContainerFactory.make` で作ったコンテナ | 実コンテナの `migrationPlan` が `ExamPrepMigrationPlan`、スキーマの版が V1 |
| `reopenExistingStore` | V1 で作ったストアのファイルを、計画つきで開き直す | データが残っている |

**Green**: `enum ExamPrepMigrationPlan: SchemaMigrationPlan` を定義し、`stages` は空にする。

**Refactor**: なし。

**完了条件**: `swift test --package-path packages/Data` がすべて通る。

**実装メモ**(2026-10-28):

- `10674ef` で3テストの assertion Red、`de04959` で Green。`ExamPrepMigrationPlan.schemas` は V1 のみ、`stages` は空。ファクトリーは `Schema(versionedSchema: SchemaV1.self)` と移行計画を指定する。
- 当初予定の Spy に代えて、SwiftData が公開する実コンテナの `migrationPlan` を確認した。移行計画導入前と同じ方法で作ったディスク上の V1 ストアを新ファクトリーで開き、既存レコードが残ることも確認した。

モデルを変更するとき(V2 の追加)の手順:

1. `SchemaV2` を追加し、`schemas` に加える。
2. `stages` に移行の段階を追加する。
3. V1 のストアを fixture として作り、V2 で開いて内容が正しく移ることのテストを先に書く。

---

## 5. フェーズの完了条件

[DDD 7.8](../DDD.md#78-フェーズの完了条件共通) の共通条件に加えて、次を満たすこと。

| No. | 条件 | 確認方法 |
|---|---|---|
| 1 | 試験単位の検索が `examID` で絞り込まれている | `#Predicate` をレビューする。受験 UUID による操作、全体設定、全体を対象とする統合・エクスポート・削除は例外 |
| 2 | リポジトリが `@Model` のオブジェクトを外に返していない | 公開 API の戻り値の型をレビューする |
| 3 | CloudKit の制約を満たしている | P3-S01 のテスト |

**最終ローカル検証**(2026-10-28):

| 対象 | 結果 |
|---|---|
| Data | 全114テスト成功（Persistence 44、ContentKit 70）。行カバレッジ 97.74% |
| Domain | 全148テスト成功。行カバレッジ 95.96%（下限80%） |
| DomainModels | 全38テスト成功 |
| Python | 全351テスト成功 |
| コンテンツ検証 | error 0 件、既存の CI-02 warning 7 件（draft 試験の問題不足） |

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/coverage.sh packages/Data
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/coverage.sh packages/Domain 80
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/DomainModels
(cd content && .venv/bin/pytest -q)
content/.venv/bin/python content/scripts/validate.py
```

`SchemaV1Tests` の10テストを含め回帰確認済み。試験単位の検索条件と公開 API の戻り値をレビューした。永続化操作は ModelActor 内で ModelContext を使い、公開操作は値型または Data を返す。`PersistenceRows` のモデルは内部でのみ扱う。

P3-S01〜S09 の実装とローカル検証は完了。S02〜S09 は先行テストと仮実装による assertion Red を確認・コミットしてから Green をコミットした。ブランチは `dev` のまま。プッシュ・PR 操作とリモート CI は利用者が担当するため、リモート CI を含むフェーズ全体の完了判定は未実施。CloudKit の実機確認は P6-S15 で行う。

---

## 6. 申し送り

| 宛先 | 内容 |
|---|---|
| P4 | 模試の画面は、解答を選ぶたびに `ExamAttemptRepository.record` と `save(snapshot:)` を呼ぶ。開始時に `PackStore.pin`、提出・放棄時に `unpin` を呼ぶ |
| P4 | 起動時(と、同期の通知を受けたとき)に `SyncDeduplicator.run()` を呼ぶ。返された `Plan.notifyUser` が true の場合は、進行中の受験を統合したことを利用者に通知する |
| P4 | `DataManagementRepository.export(examID:)`・`deleteAll(examID:)` の `nil` は全体、指定時はその試験のみ。試験指定時は UserSettings を除外する。エクスポート形式は S08 の実装メモを参照 |
| P4 | App Group の保存先 URL はアプリ側で解決し、`ModelContainerFactory.make` の `storeDirectory` に渡す |
| モデル変更時 | V2 の追加、移行計画への登録、既存ストアを使う先行テストは S09 の手順に従う |
| P6-S15 | 同期を有効にするときは、`ModelContainerFactory.make` に CloudKit のコンテナ ID(`iCloud.<逆ドメイン>.examprep`)を渡す。全削除が CloudKit 上でも反映されることを実機で確認する |
