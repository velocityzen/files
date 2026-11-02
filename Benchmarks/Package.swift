// swift-tools-version: 6.3

import PackageDescription

// A separate package so FilesKit never depends on the benchmark package: run
// `swift package benchmark` from this directory.
let package = Package(
    name: "files-benchmarks",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "Files", path: ".."),
        .package(
            url: "https://github.com/ordo-one/benchmark",
            .upToNextMajor(from: "1.38.1")
        ),
    ],
    targets: [
        .target(
            name: "BenchmarkSupport",
            dependencies: [
                .product(name: "Benchmark", package: "benchmark")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

// Each suite is its own executable under Benchmarks/, which is where the benchmark plugin
// discovers them.
for suite in ["DirectoryBenchmarks", "CueBenchmarks"] {
    package.targets.append(
        .executableTarget(
            name: suite,
            dependencies: [
                "BenchmarkSupport",
                .product(name: "FilesKit", package: "Files"),
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/\(suite)",
            swiftSettings: [.swiftLanguageMode(.v6)],
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        )
    )
}
