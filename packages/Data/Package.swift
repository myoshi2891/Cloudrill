// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Data",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "ContentKit", targets: ["ContentKit"])],
    dependencies: [.package(path: "../DomainModels"), .package(path: "../Domain")],
    targets: [
        .target(name: "ContentKit", dependencies: ["DomainModels", .product(name: "DomainInterfaces", package: "Domain")]),
        .testTarget(name: "ContentKitTests", dependencies: ["ContentKit"]),
    ],
    swiftLanguageModes: [.v6]
)
