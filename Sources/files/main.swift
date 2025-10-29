import ArgumentParser
import FilesKit
import Foundation

@main
struct Files: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "files",
        abstract: "Compare two directories and find differences",
        discussion: """
            Recursively compares two directories and reports files that are:
            - Only in the left directory
            - Only in the right directory
            - Modified (different content)
            - Unchanged (identical)
            """,
        version: "1.0.0"
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

    mutating func run() async throws {
        do {
            let diff = try await directoryDifference(
                left: leftPath,
                right: rightPath,
                recursive: recursive
            )

            printResults(diff: diff, format: format, verbose: verbose)

            // Exit with non-zero if there are differences
            throw diff.hasDifferences ? ExitCode(1) : ExitCode.success
        } catch let error as DirectoryDifferenceError {
            printError(error)
            throw ExitCode(2)
        }
    }

    func printError(_ error: DirectoryDifferenceError) {
        switch error {
        case .invalidDirectory(let path):
            FileHandle.standardError.write(Data("Error: Invalid directory: \(path)\n".utf8))
        case .accessDenied(let message):
            FileHandle.standardError.write(Data("Error: Access denied: \(message)\n".utf8))
        }
    }

    func printResults(diff: DirectoryDifference, format: OutputFormat, verbose: Bool) {
        switch format {
        case .text:
            printTextFormat(diff: diff, verbose: verbose)
        case .json:
            printJSONFormat(diff: diff)
        case .summary:
            printSummaryFormat(diff: diff)
        }
    }

    func printTextFormat(diff: DirectoryDifference, verbose: Bool) {
        let totalDifferences = diff.onlyInLeft.count + diff.onlyInRight.count + diff.modified.count

        if totalDifferences == 0 {
            print("✓ Directories are identical")
            if verbose {
                print("  Common files: \(diff.common.count)")
            }
            return
        }

        print("✗ Directories differ")
        print()

        printFileList("Only in LEFT", prefix: " +", files: diff.onlyInLeft)
        print()
        printFileList("Only in RIGHT", prefix: " +", files: diff.onlyInRight)
        print()
        printFileList("Modified", prefix: " ~", files: diff.modified)
        print()
        printFileList("Unchanged", prefix: " ~", files: diff.common)
        print()

        print(
            "Summary: \(diff.onlyInLeft.count) left-only, \(diff.onlyInRight.count) right-only, \(diff.modified.count) modified, \(diff.common.count) unchanged"
        )
    }

    func printFileList(_ message: String, prefix: String, files: Set<String>) {
        if files.isEmpty {
            return
        }

        print("\(message): (\(files.count)):")
        if verbose {
            for file in files.sorted() {
                print("\(prefix)\(file)")
            }
        } else {
            print("  Use --verbose to see file list")
        }
    }

    func printJSONFormat(diff: DirectoryDifference) {
        let result: [String: Any] = [
            "onlyInLeft": Array(diff.onlyInLeft).sorted(),
            "onlyInRight": Array(diff.onlyInRight).sorted(),
            "modified": Array(diff.modified).sorted(),
            "common": Array(diff.common).sorted(),
            "summary": [
                "onlyInLeftCount": diff.onlyInLeft.count,
                "onlyInRightCount": diff.onlyInRight.count,
                "modifiedCount": diff.modified.count,
                "commonCount": diff.common.count,
                "identical": diff.onlyInLeft.isEmpty && diff.onlyInRight.isEmpty
                    && diff.modified.isEmpty,
            ],
        ]

        if let jsonData = try? JSONSerialization.data(
            withJSONObject: result, options: .prettyPrinted),
            let jsonString = String(data: jsonData, encoding: .utf8)
        {
            print(jsonString)
        }
    }

    func printSummaryFormat(diff: DirectoryDifference) {
        let identical = diff.onlyInLeft.isEmpty && diff.onlyInRight.isEmpty && diff.modified.isEmpty
        print("Identical: \(identical ? "yes" : "no")")
        print("Only in left: \(diff.onlyInLeft.count)")
        print("Only in right: \(diff.onlyInRight.count)")
        print("Modified: \(diff.modified.count)")
        print("Unchanged: \(diff.common.count)")
        print(
            "Total files: \(diff.onlyInLeft.count + diff.onlyInRight.count + diff.modified.count + diff.common.count)"
        )
    }
}

enum OutputFormat: String, ExpressibleByArgument {
    case text
    case json
    case summary
}
