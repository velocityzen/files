import ArgumentParser
import FilesKit
import Foundation

extension Files {
    struct CompareCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "compare",
            abstract: "Compare two directories and find differences",
            discussion: """
                Recursively compares two directories and reports files that are:
                - Only in the left directory
                - Only in the right directory
                - Modified (different content)
                - Unchanged (identical)

                Options can also be set in a .files configuration file placed in either directory.
                CLI flags override .files settings. Use --no-config to disable .files loading.
                """
        )

        @Argument(help: "The left directory to compare")
        var leftPath: String

        @Argument(help: "The right directory to compare")
        var rightPath: String

        @Flag(
            name: .long, inversion: .prefixedNo,
            help: "Scan subdirectories recursively (default: on)")
        var recursive: Bool?

        @Flag(
            name: [.short, .long], inversion: .prefixedNo,
            help: "Show detailed output with all file paths")
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
            let config =
                noConfig
                ? Config()
                : await Config.load(leftPath: leftPath, rightPath: rightPath)

            // CLI flags take precedence over .files, then built-in defaults
            let recursive = recursive ?? config.recursive ?? true
            let verbose = verbose ?? config.verbose ?? false
            let format =
                format ?? config.format.flatMap { OutputFormat(rawValue: $0) } ?? .text
            let matchPrecision = matchPrecision ?? config.matchPrecision ?? 1.0
            let sizeTolerance = sizeTolerance ?? config.sizeTolerance ?? 0.0
            let noIgnore = useIgnore.map { !$0 } ?? config.noIgnore ?? false

            let ignore =
                noIgnore
                ? Ignore()
                : await Ignore.load(leftPath: leftPath, rightPath: rightPath)

            OutputFormatter.printConfig(config, ignore: ignore, verbose: verbose)

            let diffResult = await directoryDifference(
                left: leftPath,
                right: rightPath,
                recursive: recursive,
                ignore: ignore,
                matchPrecision: matchPrecision,
                sizeTolerance: sizeTolerance
            )

            switch diffResult {
                case .success(let diff):
                    OutputFormatter.printDifferenceResults(
                        diff: diff, format: format, verbose: verbose)
                    throw diff.hasDifferences ? ExitCode(1) : ExitCode.success

                case .failure(let error):
                    OutputFormatter.printError(error)
                    throw ExitCode(2)
            }
        }
    }
}
