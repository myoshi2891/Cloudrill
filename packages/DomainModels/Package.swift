// swift-tools-version: 6.0
// pca-content の JSON Schema に対応する値型。Schema を変更したら、ここと Tests を同時に更新すること。
import PackageDescription

let package = Package(
    name: "DomainModels",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DomainModels", targets: ["DomainModels"]),
    ],
    targets: [
        .target(name: "DomainModels"),
        .testTarget(
            name: "DomainModelsTests",
            dependencies: ["DomainModels"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
