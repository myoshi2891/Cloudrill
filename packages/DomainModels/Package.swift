// swift-tools-version: 6.0
// content/schemas の JSON Schema に対応する値型。Schema を変更したら、ここと Tests を同じ PR で更新すること。
import PackageDescription

let package = Package(
    name: "DomainModels",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DomainModels", targets: ["DomainModels"]),
    ],
    targets: [
        .target(name: "DomainModels"),
        // フィクスチャはパッケージにコピーせず、テストから ../../content/tests/fixtures/ を直接読む
        .testTarget(
            name: "DomainModelsTests",
            dependencies: ["DomainModels"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
