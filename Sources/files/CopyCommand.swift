import ArgumentParser
import FilesKit
import Foundation

extension Files {
    struct CopyCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "cp",
            abstract: "Copy new and modified files from source to destination",
            discussion: """
                Copies files from source to destination directory.

                This command will:
                - Copy files that exist only in source
                - Update files that are modified (different content)

                Options can also be set in a .files configuration file placed in either directory.
                CLI flags override .files settings. Use --no-config to disable .files loading.
                """
        )

        @Argument(help: "The source directory")
        var sourcePath: String

        @Argument(help: "The destination directory")
        var destinationPath: String

        @Flag(
            name: .long,
            help: "Scan leaf directories on the right side for additional diff information")
        var showMoreRight: Bool = false

        @Flag(name: .long, help: "Preview changes without applying them")
        var dryRun: Bool = false

        @Flag(name: [.short, .long], help: "Show detailed output with all operations")
        var verbose: Bool = false

        @Option(name: .long, help: "Output format: text (default), json, summary")
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

            let showMoreRight = config.showMoreRight ?? showMoreRight
            let dryRun = config.dryRun ?? dryRun
            let verbose = config.verbose ?? verbose
            let format =
                config.format.flatMap { OutputFormat(rawValue: $0) } ?? format
            let matchPrecision = matchPrecision ?? config.matchPrecision ?? 1.0
            let sizeTolerance = sizeTolerance ?? config.sizeTolerance ?? 0.0
            let noIgnore = config.noIgnore ?? noIgnore

            if dryRun {
                print("🔍 DRY RUN - No changes will be made\n")
            }

            // Setup progress display for text format
            let progress = getPrintProgress(format != .text || dryRun)

            let progressStream = await directorySync(
                left: sourcePath,
                right: destinationPath,
                mode: .oneWay,
                recursive: true,
                deletions: false,
                showMoreRight: showMoreRight,
                dryRun: dryRun,
                ignore: noIgnore ? Ignore() : nil,
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
}
