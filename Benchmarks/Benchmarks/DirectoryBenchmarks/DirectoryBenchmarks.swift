import Benchmark
import BenchmarkSupport
import FilesKit

// Comparing, sync planning and ignore matching on two directory trees on disk (see
// DirectoryFixture). Files are 4 KB and sit in the disk cache after warmup, so the numbers are
// FilesKit's own scanning, matching and the reads it asks for. Every call gets an explicit
// `Ignore()`, so a ~/.filesignore on the machine running them can't change the results.

let benchmarks: @Sendable () -> Void = {
    for count in [100, 1000] {
        onDirectories("directoryDifference", files: count) { fixture in
            await directoryDifference(left: fixture.left, right: fixture.right, ignore: Ignore())
        }

        onDirectories("directoryDifference fuzzy 0.8", files: count) { fixture in
            await directoryDifference(
                left: fixture.left, right: fixture.right, ignore: Ignore(), matchPrecision: 0.8)
        }

        // A dry run plans the operations without copying anything, so it measures the
        // comparison plus planning
        onDirectories("directorySync one-way dry run", files: count) { fixture in
            let plan = await directorySync(
                left: fixture.left, right: fixture.right, mode: .oneWay, dryRun: true,
                ignore: Ignore())
            return await plan.reduce(into: 0) { count, _ in count += 1 }
        }

        let paths = projectPaths(count)
        let ignore = Ignore(patterns: readmePatterns)
        // About 0.4 µs a path, so a call takes 40 µs at 100 paths: long enough to time one
        // call at a time
        Benchmark("Ignore.shouldIgnore", configuration: .files(["n": "\(count)"])) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(paths.filter { ignore.shouldIgnore($0) }.count)
            }
        }
    }
}

/// Registers a benchmark that calls `body` on its own directory fixture of `count` files,
/// created before the benchmark runs and removed after
func onDirectories<Result>(
    _ name: String,
    files count: Int,
    _ body: @escaping (DirectoryFixture) async -> Result
) {
    let fixture = DirectoryFixture(count: count)
    Benchmark(name, configuration: .files(["n": "\(count)"])) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(await body(fixture))
        }
    } setup: {
        try fixture.create()
    } teardown: {
        fixture.remove()
    }
}

/// The example .filesignore from the README
let readmePatterns = [
    "*.o", "*.class", "build/", "node_modules/", "vendor/", ".git/", ".svn/", ".DS_Store",
    "Thumbs.db", "*.log", "!important.log", "/config.json", "build/**/*.txt",
]

/// Paths of the kinds a project tree holds, a quarter each: photos and sources, which no
/// pattern ignores, and build output and logs, which patterns do
func projectPaths(_ count: Int) -> [String] {
    (0..<count).map { index in
        switch index % 4 {
            case 0: "album \(index / 10)/photo-\(index).jpg"
            case 1: "Sources/Module\(index / 10)/File\(index).swift"
            case 2: "build/out \(index / 10)/notes-\(index).txt"
            default: "logs/run-\(index).log"
        }
    }
}
