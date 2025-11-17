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

        @Flag(name: .long, help: "Disable .filesignore pattern matching")
        var noIgnore: Bool = false

        mutating func run() async throws {
            let diffResult = await directoryDifference(
                left: leftPath,
                right: rightPath,
                recursive: recursive,
                ignore: noIgnore ? Ignore() : nil
            )

            switch diffResult {
                case .success(let diff):
                    OutputFormatter.printDifferenceResults(
                        diff: diff, format: format, verbose: verbose)
                    // Exit with non-zero if there are differences
                    throw diff.hasDifferences ? ExitCode(1) : ExitCode.success

                case .failure(let error):
                    OutputFormatter.printError(error)
                    throw ExitCode(2)
            }
        }
    }
}
