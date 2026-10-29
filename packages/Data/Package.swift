// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Data",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ContentKit", targets: ["ContentKit"]),
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    dependencies: [.package(path: "../DomainModels"), .package(path: "../Domain")],
    targets: [
        .target(name: "ContentKit", dependencies: ["DomainModels", .product(name: "DomainInterfaces", package: "Domain")]),
        .testTarget(name: "ContentKitTests", dependencies: ["ContentKit"]),
        .target(name: "Persistence", dependencies: [
            "DomainModels", .product(name: "DomainInterfaces", package: "Domain"),
            .product(name: "StudyModels", package: "Domain"), .product(name: "ExamEngine", package: "Domain"),
            .product(name: "FSRS", package: "Domain"), .product(name: "QuestionSelector", package: "Domain"),
        ]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    ],
    swiftLanguageModes: [.v6]
)
