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
        var conflictResolution: ConflictResolutionOption = .newest

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
        var matchPrecision: Double = 1.0

        @Flag(name: .long, help: "Disable .filesignore pattern matching")
        var noIgnore: Bool = false

        mutating func run() async throws {
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
                ignore: noIgnore ? Ignore() : nil,
                matchPrecision: matchPrecision
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
