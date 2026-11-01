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
            name: .long, inversion: .prefixedNo,
            help: "Scan leaf directories on the right side for additional diff information")
        var showMoreRight: Bool?

        @Flag(
            name: .long, inversion: .prefixedNo,
            help: "Preview changes without applying them")
        var dryRun: Bool?

        @Flag(
            name: [.short, .long], inversion: .prefixedNo,
            help: "Show detailed output with all operations")
        var verbose: Bool?

        @Option(name: .long, help: "Output format: text (default), json, summary")
        var format: OutputFormat?

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

        @Flag(
            name: .customLong("ignore"), inversion: .prefixedNo,
            help: "Apply .filesignore patterns (default: on)")
        var useIgnore: Bool?

        @Flag(name: .long, help: "Disable .files configuration loading")
        var noConfig: Bool = false

        mutating func run() async throws {
            // The source .files is not trusted with settings that delete or overwrite files
            let config =
                noConfig
                ? Config()
                : await Config.load(
                    leftPath: sourcePath, rightPath: destinationPath, trustLeft: false)

            // CLI flags take precedence over .files, then built-in defaults
            let showMoreRight = showMoreRight ?? config.showMoreRight ?? false
            let dryRun = dryRun ?? config.dryRun ?? false
            let verbose = verbose ?? config.verbose ?? false
            let format =
                format ?? config.format.flatMap { OutputFormat(rawValue: $0) } ?? .text
            let matchPrecision = matchPrecision ?? config.matchPrecision ?? 1.0
            let sizeTolerance = sizeTolerance ?? config.sizeTolerance ?? 0.0
            let noIgnore = useIgnore.map { !$0 } ?? config.noIgnore ?? false

            let ignore =
                noIgnore
                ? Ignore()
                : await Ignore.load(leftPath: sourcePath, rightPath: destinationPath)

            OutputFormatter.printConfig(config, ignore: ignore, verbose: verbose)

            if dryRun {
                OutputFormatter.printDiagnostic("🔍 DRY RUN - No changes will be made\n")
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

            if results.failed > 0 {
                throw ExitCode(1)
            }
        }
    }
}
