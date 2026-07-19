// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TextMorph",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "TextMorph",
            targets: ["TextMorph"]
        )
    ],
    targets: [
        .target(
            name: "TextMorph"
        ),
        .testTarget(
            name: "TextMorphTests",
            dependencies: ["TextMorph"]
        ),
    ]
)
