// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Files",
    platforms: [
        .macOS(.v26)
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
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/velocityzen/fp-swift", from: "4.2.1"),
        .package(url: "https://github.com/velocityzen/fp-swift-bracket", from: "2.1.0"),
        .package(url: "https://github.com/velocityzen/ProgramStatus", from: "0.4.0"),
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
                .product(name: "ProgramStatus", package: "ProgramStatus"),
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
                .product(name: "ProgramStatus", package: "ProgramStatus"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
