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

        @Flag(name: .long, inversion: .prefixedNo, help: "Scan subdirectories recursively")
        var recursive: Bool = true

        @Flag(name: [.short, .long], help: "Show detailed output with all file paths")
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
                : await Config.load(leftPath: leftPath, rightPath: rightPath)

            let recursive = config.recursive ?? recursive
            let verbose = config.verbose ?? verbose
            let format =
                config.format.flatMap { OutputFormat(rawValue: $0) } ?? format
            let matchPrecision = matchPrecision ?? config.matchPrecision ?? 1.0
            let sizeTolerance = sizeTolerance ?? config.sizeTolerance ?? 0.0
            let noIgnore = config.noIgnore ?? noIgnore

            let diffResult = await directoryDifference(
                left: leftPath,
                right: rightPath,
                recursive: recursive,
                ignore: noIgnore ? Ignore() : nil,
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
