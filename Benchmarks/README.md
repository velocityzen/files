# Benchmarks

Performance benchmarks for FilesKit, built on [ordo-one/benchmark](https://github.com/ordo-one/benchmark) the same way as [fp-swift's](https://github.com/velocityzen/fp-swift/tree/main/Benchmarks). They live in their own package so FilesKit never depends on the benchmark package.

Every benchmark records wall clock and CPU time, instructions, malloc count and bytes, bytes not freed, object allocations, and retain and release counts. All values are **per call** of the API under test.

## Suites

| Target | Covers |
| --- | --- |
| `DirectoryBenchmarks` | `directoryDifference` exact and fuzzy (`matchPrecision: 0.8`), a one-way `directorySync` dry run, and `Ignore.shouldIgnore` with the README's example patterns |
| `CueBenchmarks` | `CueSheet.parse` and `CueSheet.plan` at 12 and 99 tracks, and `cutTracks` of 30 seconds of WAV and FLAC in 10 tracks |

The directory benchmarks run at `n: 100` and `n: 1000` files on two real trees of 4 KB files, ten per folder. 80% of the files are the same on both sides, so their contents are read and compared. 10% differ only in their last byte, and 10% are renamed on the right with two letters swapped, so fuzzy matching has pairs to find. The files sit in the disk cache after warmup, so the numbers are FilesKit's scanning, matching and the reads it asks for. Every call gets an explicit `Ignore()`, so a `~/.filesignore` on the machine can't change the results.

Fixtures are created in each benchmark's setup, in the temporary directory, and removed in its teardown.

## Running

Requires Swift 6.3 or later. Malloc statistics come from the benchmark package's malloc interposer, so there is nothing to install.

Run everything from this directory:

```bash
swift package --allow-writing-to-package-directory benchmark
```

SwiftPM runs benchmarks in a sandbox that blocks the Core Audio services `AVAudioFile` needs, so the `cutTracks` benchmarks are left out unless the sandbox is off:

```bash
swift package --disable-sandbox benchmark --target CueBenchmarks
```

Run one suite, or the benchmarks whose names match a regular expression. The expression must match the whole name without its `(n: …)` tags, so a filter selects every size of a benchmark:

```bash
swift package benchmark --target DirectoryBenchmarks
```

```bash
swift package benchmark --filter "directoryDifference.*"
```

List the benchmarks without running them:

```bash
swift package benchmark list
```

## Comparing before and after a change

Record a baseline, make the change, then compare the new code against it:

```bash
swift package --allow-writing-to-package-directory benchmark baseline update main
```

```bash
swift package benchmark baseline compare main
```

Baselines are saved in `.benchmarkBaselines/`, which is not committed: they are only comparable on the machine that recorded them.

Malloc, object-allocation and ARC counts are stable from run to run, even where comparison runs a task per file, so they are the numbers to watch first. Times move with the machine's load and the disk; close other work before comparing them.

`baseline check` fails only when one of those four counts gets worse; times and the other metrics are reported by `compare` but never fail a check. The tolerance is `checkedTolerance` in [BenchmarkSupport.swift](Sources/BenchmarkSupport/BenchmarkSupport.swift).

```bash
swift package benchmark baseline check main
```

## Continuous integration

The [Benchmarks workflow](../.github/workflows/benchmarks.yml) benchmarks every push to `main` against the commit it was pushed on top of, and every pull request against its base branch. The job summary lists every metric's change, and the job fails when an allocation or ARC count regresses. It runs in SwiftPM's sandbox, so it leaves out `cutTracks`.

## Finding where allocations come from

Print the call stacks behind each benchmark's allocations, most frequent first:

```bash
swift package benchmark --target CueBenchmarks --filter "CueSheet.parse" --allocation-stacks
```

## Profiling

Each suite is an ordinary executable that runs all of its benchmarks when launched on its own, outside SwiftPM's sandbox, so it can be profiled in Instruments or debugged in lldb:

```bash
swift build -c release --product CueBenchmarks
```
