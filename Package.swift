// swift-tools-version:5.3
//
// Extension manifest. The FlagsEngine evaluation engine lives in-repo under AEPFlagsEngine/
// and is compiled locally as an internal target -- it is never downloaded and is not published
// as its own product; only AEPFlags is a public product.

import PackageDescription

let package = Package(
    name: "AEPFlags",
    platforms: [.iOS(.v12)],
    products: [
        .library(name: "AEPFlags", targets: ["AEPFlags"])
    ],
    dependencies: [
        .package(url: "https://github.com/adobe/aepsdk-core-ios.git", .upToNextMajor(from: "5.8.0")),
        .package(url: "https://github.com/adobe/aepsdk-edge-ios.git", .upToNextMajor(from: "5.0.2")),
        .package(url: "https://github.com/adobe/aepsdk-edgeidentity-ios.git", .upToNextMajor(from: "5.0.0")),
    ],
    targets: [
        .target(
            name: "FlagsEngine",
            dependencies: [],
            path: "AEPFlagsEngine/Sources",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "FlagsEngineTests",
            dependencies: ["FlagsEngine"],
            path: "AEPFlagsEngine/Tests"
        ),
        .target(
            name: "AEPFlags",
            dependencies: [
                "FlagsEngine",
                .product(name: "AEPCore", package: "aepsdk-core-ios"),
                .product(name: "AEPServices", package: "aepsdk-core-ios"),
                .product(name: "AEPEdge", package: "aepsdk-edge-ios"),
                .product(name: "AEPEdgeIdentity", package: "aepsdk-edgeidentity-ios"),
            ],
            path: "AEPFlags/Sources"
        ),
        .testTarget(
            name: "AEPFlagsTests",
            dependencies: [
                "AEPFlags",
                "FlagsEngine",
                .product(name: "AEPServices", package: "aepsdk-core-ios"),
                .product(name: "AEPEdgeIdentity", package: "aepsdk-edgeidentity-ios"),
            ],
            path: "AEPFlags/Tests/UnitTests"
        )
    ]
)
