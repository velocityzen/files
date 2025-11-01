import ArgumentParser
import FilesKit
import Foundation

extension Files {
    struct CompareSnapshotCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "compare-snapshot",
            abstract: "Compare two snapshot JSON files",
            discussion: """
                Compares two JSON files produced by the 'compare' command with --format json.
                This allows you to track how directory differences have changed over time.

                The comparison shows:
                - Files that appeared or disappeared in the comparison results
                - Files whose status changed (e.g., from 'modified' to 'common')
                - Files whose status remained the same

                Example workflow:
                  1. files compare dir1 dir2 --format json > snapshot1.json
                  2. # Make changes to directories
                  3. files compare dir1 dir2 --format json > snapshot2.json
                  4. files compare-snapshot snapshot1.json snapshot2.json
                """
        )

        @Argument(help: "The left snapshot JSON file")
        var leftPath: String

        @Argument(help: "The right snapshot JSON file")
        var rightPath: String

        @Flag(name: [.short, .long], help: "Show detailed output with all file paths")
        var verbose: Bool = false

        @Option(name: .long, help: "Output format: text (default), json, summary")
        var format: OutputFormat = .text

        mutating func run() async throws {
            do {
                let diff = try await compareSnapshots(
                    left: leftPath,
                    right: rightPath
                )

                OutputFormatter.printDifferenceResults(
                    diff: diff,
                    format: format,
                    verbose: verbose
                )

                // Exit with non-zero if there are differences
                throw diff.hasDifferences ? ExitCode(1) : ExitCode.success
            } catch let error as DirectoryDifferenceError {
                OutputFormatter.printError(error)
                throw ExitCode(2)
            }
        }
    }
}
