// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Presentation",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "HomeFeature", targets: ["HomeFeature"]),
    ],
    dependencies: [.package(path: "../DomainModels"), .package(path: "../Domain")],
    targets: [
        .target(name: "AppCore", dependencies: [
            "DomainModels", .product(name: "DomainInterfaces", package: "Domain"),
            .product(name: "StudyModels", package: "Domain"), .product(name: "ExamEngine", package: "Domain"),
        ]),
        .target(name: "HomeFeature", dependencies: ["AppCore", "DomainModels"]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore", "HomeFeature",
            .product(name: "DomainTestSupport", package: "Domain")]),
    ],
    swiftLanguageModes: [.v6]
)
