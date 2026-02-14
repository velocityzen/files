import ArgumentParser
import FilesKit
import Foundation

extension Files {
    struct SyncCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "sync",
            abstract: "Synchronize two directories",
            discussion: """
                Synchronizes two directories with support for one-way and two-way sync modes.

                One-way sync: Mirrors source to destination (source -> destination)
                Two-way sync: Bidirectional sync with conflict resolution for modified files

                Conflict resolution strategies for two-way sync:
                - newest: Keep the file with the most recent modification time (default)
                - source: Always prefer the source file
                - destination: Always prefer the destination file
                - skip: Skip conflicting files, leave both unchanged

                Options can also be set in a .files configuration file placed in either directory.
                CLI flags override .files settings. Use --no-config to disable .files loading.
                """
        )

        @Argument(help: "The source directory")
        var sourcePath: String

        @Argument(help: "The destination directory")
        var destinationPath: String

        @Flag(name: .long, help: "Enable two-way sync (bidirectional)")
        var twoWay: Bool = false

        @Option(
            name: .long, help: "Conflict resolution: newest (default), source, destination, skip")
        var conflictResolution: ConflictResolutionOption?

        @Flag(name: .long, inversion: .prefixedNo, help: "Scan subdirectories recursively")
        var recursive: Bool = true

        @Flag(
            name: .long,
            help: "Delete files in destination that don't exist in source (one-way sync only)")
        var deletions: Bool = false

        @Flag(
            name: .long,
            help:
                "Scan leaf directories on the right side for additional diff information (one-way sync without deletions only)"
        )
        var showMoreRight: Bool = false

        @Flag(name: .long, help: "Preview changes without applying them")
        var dryRun: Bool = false

        @Flag(name: [.short, .long], help: "Show detailed output with all operations")
        var verbose: Bool = false

        @Option(name: .long, help: "Output format: text (default), json")
        var format: OutputFormat = .text

        @Option(
            name: .long,
            help:
                "Fuzzy filename matching threshold from 0.0 to 1.0 (default: 1.0 for exact matching)"
        )
        var matchPrecision: Double?

        @Option(
            name: .long,
            help:
                "File size difference tolerance for fuzzy matches from 0.0 to 1.0 (default: 0.0 for exact comparison)"
        )
        var sizeTolerance: Double?

        @Flag(name: .long, help: "Disable .filesignore pattern matching")
        var noIgnore: Bool = false

        @Flag(name: .long, help: "Disable .files configuration loading")
        var noConfig: Bool = false

        mutating func run() async throws {
            let config =
                noConfig
                ? Config()
                : await Config.load(leftPath: sourcePath, rightPath: destinationPath)

            let twoWay = config.twoWay ?? twoWay
            let conflictResolution =
                conflictResolution
                ?? config.conflictResolution.flatMap { ConflictResolutionOption(rawValue: $0) }
                ?? .newest
            let recursive = config.recursive ?? recursive
            let deletions = config.deletions ?? deletions
            let showMoreRight = config.showMoreRight ?? showMoreRight
            let dryRun = config.dryRun ?? dryRun
            let verbose = config.verbose ?? verbose
            let format =
                config.format.flatMap { OutputFormat(rawValue: $0) } ?? format
            let matchPrecision = matchPrecision ?? config.matchPrecision ?? 1.0
            let sizeTolerance = sizeTolerance ?? config.sizeTolerance ?? 0.0
            let noIgnore = config.noIgnore ?? noIgnore

            let ignore =
                noIgnore
                ? Ignore()
                : await Ignore.load(leftPath: sourcePath, rightPath: destinationPath)

            OutputFormatter.printConfig(config, ignore: ignore, verbose: verbose)

            if dryRun {
                print("🔍 DRY RUN - No changes will be made\n")
            }

            let syncMode: SyncMode =
                twoWay
                ? .twoWay(conflictResolution: conflictResolution.toConflictResolution())
                : .oneWay

            // Setup progress display for text format
            let progress = getPrintProgress(format != .text || dryRun)

            let progressStream = await directorySync(
                left: sourcePath,
                right: destinationPath,
                mode: syncMode,
                recursive: recursive,
                deletions: deletions,
                showMoreRight: showMoreRight,
                dryRun: dryRun,
                ignore: ignore,
                matchPrecision: matchPrecision,
                sizeTolerance: sizeTolerance
            )

            var latestResults: [FileOperation: OperationResult] = [:]
            for await result in progressStream {
                let operation =
                    switch result {
                        case .success(let success): success.operation
                        case .failure(let failure): failure.operation
                    }
                latestResults[operation] = result
                progress(result)
            }

            let results = Array(latestResults.values)

            OutputFormatter.printResults(
                format: format,
                results: results,
                verbose: verbose,
                dryRun: dryRun
            )

            if !dryRun && results.failed > 0 {
                throw ExitCode(1)
            }
        }
    }

    enum ConflictResolutionOption: String, ExpressibleByArgument {
        case newest
        case left
        case right
        case skip

        func toConflictResolution() -> ConflictResolution {
            switch self {
                case .newest: return .keepNewest
                case .left: return .keepLeft
                case .right: return .keepRight
                case .skip: return .skip
            }
        }
    }
}
