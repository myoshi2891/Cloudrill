// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Presentation",
    defaultLocalization: "ja",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "HomeFeature", targets: ["HomeFeature"]),
        .library(name: "ExamFeature", targets: ["ExamFeature"]),
        .library(name: "PracticeFeature", targets: ["PracticeFeature"]),
        .library(name: "FlashcardFeature", targets: ["FlashcardFeature"]),
        .library(name: "LearnFeature", targets: ["LearnFeature"]),
    ],
    dependencies: [.package(path: "../DomainModels"), .package(path: "../Domain"),
                   // Markdown のパースだけに使う。描画は DesignSystem.MarkdownView(DDD 8 章)
                   .package(url: "https://github.com/swiftlang/swift-markdown.git", .upToNextMinor(from: "0.9.0"))],
    targets: [
        .target(name: "DesignSystem", dependencies: ["DomainModels", .product(name: "Markdown", package: "swift-markdown")],
                resources: [.process("Resources")]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem", "DomainModels"]),
        .target(name: "AppCore", dependencies: [
            "DomainModels", .product(name: "DomainInterfaces", package: "Domain"),
            .product(name: "StudyModels", package: "Domain"), .product(name: "ExamEngine", package: "Domain"),
        ]),
        .target(name: "HomeFeature", dependencies: [
            "AppCore", "DomainModels", "DesignSystem", .product(name: "DomainInterfaces", package: "Domain"),
            .product(name: "StudyModels", package: "Domain"),
        ], resources: [.process("Resources")]),
        .target(name: "ExamFeature", dependencies: ["AppCore", "DomainModels", "DesignSystem",
            .product(name: "DomainInterfaces", package: "Domain"),
            .product(name: "StudyModels", package: "Domain"), .product(name: "ExamEngine", package: "Domain"),
        ], resources: [.process("Resources")]),
        .target(name: "PracticeFeature", dependencies: ["AppCore", "ExamFeature", "DesignSystem", "DomainModels",
            .product(name: "DomainInterfaces", package: "Domain"), .product(name: "StudyModels", package: "Domain"),
            .product(name: "QuestionSelector", package: "Domain"), .product(name: "ExamEngine", package: "Domain")
        ], resources: [.process("Resources")]),
        .target(name: "FlashcardFeature", dependencies: ["AppCore", "DesignSystem", "DomainModels",
            .product(name: "DomainInterfaces", package: "Domain"), .product(name: "StudyModels", package: "Domain"),
            .product(name: "FSRS", package: "Domain")
        ], resources: [.process("Resources")]),
        .target(name: "LearnFeature", dependencies: ["AppCore", "DesignSystem", "DomainModels",
            .product(name: "DomainInterfaces", package: "Domain")
        ], resources: [.process("Resources")]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore", "HomeFeature", "ExamFeature", "PracticeFeature", "FlashcardFeature",
            "LearnFeature",
            .product(name: "DomainTestSupport", package: "Domain")]),
    ],
    swiftLanguageModes: [.v6]
)
