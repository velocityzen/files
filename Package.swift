// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Files",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "FilesKit",
            targets: ["FilesKit"]
        ),
        .executable(
            name: "files",
            targets: ["files"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        // 4.x and bracket 2.x need macOS 26 and Swift tools 6.3
        .package(url: "https://github.com/velocityzen/fp-swift", from: "3.3.0"),
        .package(url: "https://github.com/velocityzen/fp-swift-bracket", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "FilesKit",
            dependencies: [
                .product(name: "FP", package: "fp-swift"),
                .product(name: "FPBracket", package: "fp-swift-bracket"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "files",
            dependencies: [
                "FilesKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "FP", package: "fp-swift"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "FilesTests",
            dependencies: [
                "FilesKit",
                "files",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "FP", package: "fp-swift"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
