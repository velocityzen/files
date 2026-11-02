import Benchmark

/// Metrics recorded by every FilesKit benchmark: time, instructions, heap traffic and ARC
/// traffic. Every value is reported per call of the API under test.
public let filesMetrics: [BenchmarkMetric] = [
    .wallClock,
    .cpuTotal,
    .throughput,
    .instructions,
    .mallocCountTotal,
    .mallocBytesCount,
    .memoryLeakedBytes,
    .objectAllocCount,
    .retainCount,
    .releaseCount,
]

/// The metrics `baseline check` fails on. Allocation and ARC counts barely move between runs
/// of the same code, while times swing with the machine's load and the disk cache, so times
/// are reported but never fail a check.
public let checkedMetrics: [BenchmarkMetric] = [
    .mallocCountTotal,
    .objectAllocCount,
    .retainCount,
    .releaseCount,
]

/// How far, in percent, a checked metric's median may move before `baseline check` reports it
public let checkedTolerance = 5.0

func filesThresholds(tolerance: Double) -> [BenchmarkMetric: BenchmarkThresholds] {
    Dictionary(
        uniqueKeysWithValues: filesMetrics.map { metric in
            let thresholds =
                checkedMetrics.contains(metric)
                ? BenchmarkThresholds(relative: [.p50: tolerance])
                : BenchmarkThresholds()
            return (metric, thresholds)
        }
    )
}

extension Benchmark.Configuration {
    /// The configuration every FilesKit benchmark uses.
    ///
    /// Each sample runs `scaling` calls in a `benchmark.scaledIterations` loop, and the scaled
    /// metrics are divided back to a single call. Use `.kilo` for calls in the micro- or
    /// nanosecond range, so timer and sampling overhead stays out of the numbers, and `.one`
    /// for calls that already take a millisecond or so, which is most calls that touch disk.
    public static func files(
        _ tags: [String: String] = [:],
        scaling: BenchmarkScalingFactor = .one,
        tolerance: Double = checkedTolerance
    ) -> Self {
        .init(
            metrics: filesMetrics,
            tags: tags,
            warmupIterations: 5,
            scalingFactor: scaling,
            maxDuration: .seconds(1),
            maxIterations: 10_000,
            thresholds: filesThresholds(tolerance: tolerance)
        )
    }
}
