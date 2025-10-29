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

        @Flag(name: .long, help: "Preview changes without applying them")
        var dryRun: Bool = false

        @Flag(name: [.short, .long], help: "Show detailed output with all operations")
        var verbose: Bool = false

        @Option(name: .long, help: "Output format: text (default), json")
        var format: OutputFormat = .text

        mutating func run() async throws {
            do {
                let syncMode: SyncMode =
                    twoWay
                    ? .twoWay(conflictResolution: conflictResolution.toConflictResolution())
                    : .oneWay

                if dryRun {
                    print("🔍 DRY RUN - No changes will be made")
                    print()
                }

                let result = try await directorySync(
                    left: sourcePath,
                    right: destinationPath,
                    mode: syncMode,
                    recursive: recursive,
                    dryRun: dryRun
                )

                printResults(result: result, format: format, verbose: verbose, dryRun: dryRun)

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
                print("✓ Directories are in sync - no operations needed")
                return
            }

            let verb = dryRun ? "Would perform" : "Performed"
            print("\(verb) \(result.operations.count) operation(s)")
            print()

            // Group operations by type
            let copies = result.operations.filter { $0.type == .copy }
            let updates = result.operations.filter { $0.type == .update }
            let deletes = result.operations.filter { $0.type == .delete }

            if !copies.isEmpty {
                printOperationList(
                    "Copy", verb: dryRun ? "would copy" : "copied", operations: copies,
                    verbose: verbose
                )
                print()
            }

            if !updates.isEmpty {
                printOperationList(
                    "Update", verb: dryRun ? "would update" : "updated", operations: updates,
                    verbose: verbose)
                print()
            }

            if !deletes.isEmpty {
                printOperationList(
                    "Delete", verb: dryRun ? "would delete" : "deleted", operations: deletes,
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
                    "left": op.left ?? "",
                    "right": op.right,
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
            let deletes = result.operations.filter { $0.type == .delete }.count

            print("Total operations: \(result.operations.count)")
            print("Copy: \(copies)")
            print("Update: \(updates)")
            print("Delete: \(deletes)")

            if !dryRun {
                print("Succeeded: \(result.succeeded)")
                print("Failed: \(result.failed)")
                print("Skipped: \(result.skipped)")
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
