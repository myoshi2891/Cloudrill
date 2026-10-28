// swift-tools-version: 6.0
import PackageDescription

// アプリ専用の組み立て層。Presentation 自体には Data を依存させない。
let package = Package(
    name: "AppComposition",
    defaultLocalization: "ja",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "AppComposition", targets: ["AppComposition"])],
    dependencies: [.package(path: "../Presentation"), .package(path: "../Data"),
                   .package(path: "../Domain"), .package(path: "../DomainModels")],
    targets: [
        .target(name: "AppComposition", dependencies: ["DomainModels",
            .product(name: "AppCore", package: "Presentation"),
            .product(name: "HomeFeature", package: "Presentation"),
            .product(name: "ExamFeature", package: "Presentation"),
            .product(name: "ContentKit", package: "Data"), .product(name: "Persistence", package: "Data"),
            .product(name: "DomainInterfaces", package: "Domain"), .product(name: "StudyModels", package: "Domain"),
            .product(name: "ExamEngine", package: "Domain")], resources: [.process("Resources")]),
        .testTarget(name: "AppCompositionTests", dependencies: ["AppComposition"]),
    ],
    swiftLanguageModes: [.v6]
)
