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
                """
        )

        @Argument(help: "The source directory")
        var sourcePath: String

        @Argument(help: "The destination directory")
        var destinationPath: String

        @Flag(name: .long, help: "Preview changes without applying them")
        var dryRun: Bool = false

        @Flag(name: [.short, .long], help: "Show detailed output with all operations")
        var verbose: Bool = false

        @Option(name: .long, help: "Output format: text (default), json, summary")
        var format: OutputFormat = .text

        mutating func run() async throws {
            do {
                if dryRun {
                    print("🔍 DRY RUN - No changes will be made")
                    print()
                }

                let result = try await directorySync(
                    left: sourcePath,
                    right: destinationPath,
                    mode: .oneWay,
                    recursive: true,
                    deletions: false,
                    dryRun: dryRun
                )

                printResults(
                    result: result,
                    format: format,
                    verbose: verbose,
                    dryRun: dryRun
                )

                if !dryRun && result.failed > 0 {
                    throw ExitCode(1)
                }
            } catch let error as DirectorySyncError {
                printError(error)
                throw ExitCode(2)
            }
        }

        func printError(_ error: DirectorySyncError) {
            switch error {
            case .invalidDirectory(let path):
                FileHandle.standardError.write(Data("Error: Invalid directory: \(path)\n".utf8))
            case .accessDenied(let message):
                FileHandle.standardError.write(Data("Error: Access denied: \(message)\n".utf8))
            case .operationFailed(let message):
                FileHandle.standardError.write(Data("Error: Operation failed: \(message)\n".utf8))
            }
        }

        func printResults(result: SyncResult, format: OutputFormat, verbose: Bool, dryRun: Bool) {
            switch format {
            case .text:
                printTextFormat(result: result, verbose: verbose, dryRun: dryRun)
            case .json:
                printJSONFormat(result: result)
            case .summary:
                printSummaryFormat(result: result, dryRun: dryRun)
            }
        }

        func printTextFormat(result: SyncResult, verbose: Bool, dryRun: Bool) {
            if result.operations.isEmpty {
                print("✓ No files need to be copied - destination is up to date")
                return
            }

            let verb = dryRun ? "Would copy/update" : "Copied/Updated"
            print("\(verb) \(result.operations.count) file(s)")
            print()

            // Group operations by type
            let copies = result.operations.filter { $0.type == .copy }
            let updates = result.operations.filter { $0.type == .update }

            if !copies.isEmpty {
                printOperationList(
                    "New files", verb: dryRun ? "would copy" : "copied", operations: copies,
                    verbose: verbose
                )
                print()
            }

            if !updates.isEmpty {
                printOperationList(
                    "Modified files", verb: dryRun ? "would update" : "updated",
                    operations: updates,
                    verbose: verbose)
                print()
            }

            if !dryRun {
                print(
                    "Summary: \(result.succeeded) succeeded, \(result.failed) failed, \(result.skipped) skipped"
                )
            }
        }

        func printOperationList(
            _ title: String, verb: String, operations: [SyncOperation], verbose: Bool
        ) {
            print("\(title) (\(operations.count)):")
            if verbose {
                for op in operations.sorted(by: { $0.relativePath < $1.relativePath }) {
                    print("  \(verb) \(op.relativePath)")
                }
            } else {
                print("  Use --verbose to see file list")
            }
        }

        func printJSONFormat(result: SyncResult) {
            let operations = result.operations.map { op in
                [
                    "type": String(describing: op.type),
                    "path": op.relativePath,
                    "source": op.left ?? "",
                    "destination": op.right,
                ]
            }

            let resultDict: [String: Any] = [
                "operations": operations,
                "summary": [
                    "total": result.totalOperations,
                    "succeeded": result.succeeded,
                    "failed": result.failed,
                    "skipped": result.skipped,
                ],
            ]

            if let jsonData = try? JSONSerialization.data(
                withJSONObject: resultDict, options: .prettyPrinted),
                let jsonString = String(data: jsonData, encoding: .utf8)
            {
                print(jsonString)
            }
        }

        func printSummaryFormat(result: SyncResult, dryRun: Bool) {
            let copies = result.operations.filter { $0.type == .copy }.count
            let updates = result.operations.filter { $0.type == .update }.count

            print("Total operations: \(result.operations.count)")
            print("New files: \(copies)")
            print("Modified files: \(updates)")

            if !dryRun {
                print("Succeeded: \(result.succeeded)")
                print("Failed: \(result.failed)")
                print("Skipped: \(result.skipped)")
            }
        }
    }
}
