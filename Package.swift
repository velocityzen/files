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
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "FilesKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "files",
            dependencies: [
                "FilesKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "FilesTests",
            dependencies: ["FilesKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
