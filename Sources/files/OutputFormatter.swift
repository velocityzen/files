import ArgumentParser
import FilesKit
import Foundation

enum OutputFormat: String, ExpressibleByArgument {
    case text
    case json
    case summary
}

enum OutputFormatter {
    // MARK: - Error Printing

    static func printError(_ error: DirectorySyncError) {
        switch error {
            case .invalidDirectory(let path):
                FileHandle.standardError.write(Data("Error: Invalid directory: \(path)\n".utf8))
            case .accessDenied(let message):
                FileHandle.standardError.write(Data("Error: Access denied: \(message)\n".utf8))
            case .operationFailed(let message):
                FileHandle.standardError.write(Data("Error: Operation failed: \(message)\n".utf8))
        }
    }

    static func printError(_ error: DirectoryDifferenceError) {
        switch error {
            case .invalidDirectory(let path):
                FileHandle.standardError.write(Data("Error: Invalid directory: \(path)\n".utf8))
            case .accessDenied(let message):
                FileHandle.standardError.write(Data("Error: Access denied: \(message)\n".utf8))
        }
    }

    // MARK: - Sync Results Printing

    static func printSyncResults(
        result: SyncResult, format: OutputFormat, verbose: Bool, dryRun: Bool
    ) {
        switch format {
            case .text:
                printSyncTextFormat(result: result, verbose: verbose, dryRun: dryRun)
            case .json:
                printSyncJSONFormat(result: result)
            case .summary:
                printSyncSummaryFormat(result: result, dryRun: dryRun)
        }
    }

    private static func printSyncTextFormat(result: SyncResult, verbose: Bool, dryRun: Bool) {
        if result.operations.isEmpty {
            print("✓ No operations needed")
            return
        }
        let (copies, updates, deletes, infos) = groupOperations(result.operations)

        let verb = dryRun ? "Would perform" : "Performed"
        print("\(verb) \(result.totalOperations) operation(s)")
        print()

        if !copies.isEmpty {
            printOperationList("Copy", operations: copies, verbose: verbose)
            print()
        }

        if !updates.isEmpty {
            printOperationList("Update", operations: updates, verbose: verbose)
            print()
        }

        if !deletes.isEmpty {
            printOperationList("Delete", operations: deletes, verbose: verbose)
            print()
        }

        if !infos.isEmpty {
            printOperationList("Info", operations: infos, verbose: verbose)
            print()
        }

        if !dryRun {
            print(
                "Summary: \(result.succeeded) succeeded, \(result.failed) failed, \(result.skipped) skipped"
            )
        }
    }

    static func printOperationList(
        _ title: String, operations: [SyncOperation], verbose: Bool
    ) {
        print("\(title) (\(operations.count))")
        if verbose {
            for operation in operations {
                printOperation(operation)
            }
        }
    }

    static func printOperation(_ operation: SyncOperation) {
        let prefix =
            switch operation.type {
                case .copy:
                    " +"
                case .delete:
                    " -"
                case .update:
                    " ^"
                case .info:
                    " i"
            }

        print("\(prefix) \(operation.relativePath)")
    }

    private static func printSyncJSONFormat(result: SyncResult) {
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

        printJSON(resultDict)
    }

    private static func printSyncSummaryFormat(result: SyncResult, dryRun: Bool) {
        let (copies, updates, deletes, infos) = groupOperations(result.operations)

        print("Total operations: \(result.operations.count)")
        print("Copy: \(copies.count)")
        print("Update: \(updates.count)")
        print("Delete: \(deletes.count)")
        print("Info: \(infos.count)")

        if !dryRun {
            print("Succeeded: \(result.succeeded)")
            print("Failed: \(result.failed)")
            print("Skipped: \(result.skipped)")
        }
    }

    // MARK: - Difference Results Printing

    static func printDifferenceResults(
        diff: DirectoryDifference, format: OutputFormat, verbose: Bool
    ) {
        switch format {
            case .text:
                printDifferenceTextFormat(diff: diff, verbose: verbose)
            case .json:
                printDifferenceJSONFormat(diff: diff)
            case .summary:
                printDifferenceSummaryFormat(diff: diff)
        }
    }

    private static func printDifferenceTextFormat(diff: DirectoryDifference, verbose: Bool) {
        let totalDifferences =
            diff.onlyInLeft.count + diff.onlyInRight.count + diff.modified.count

        if totalDifferences == 0 {
            print("✓ Directories are identical")
            if verbose {
                print("  Common files: \(diff.common.count)")
            }
            return
        }

        print("✗ Directories differ")
        print()

        printFileList("Only in LEFT", prefix: " +", files: diff.onlyInLeft, verbose: verbose)
        print()
        printFileList("Only in RIGHT", prefix: " +", files: diff.onlyInRight, verbose: verbose)
        print()
        printFileList("Modified", prefix: " ^", files: diff.modified, verbose: verbose)
        print()
        printFileList("Unchanged", prefix: " ~", files: diff.common, verbose: verbose)
        print()

        print(
            "Summary: \(diff.onlyInLeft.count) left-only, \(diff.onlyInRight.count) right-only, \(diff.modified.count) modified, \(diff.common.count) unchanged"
        )
    }

    static func printFileList(_ message: String, prefix: String, files: Set<String>, verbose: Bool)
    {
        if files.isEmpty {
            return
        }

        print("\(message): (\(files.count)):")
        if verbose {
            for file in files.sorted() {
                print("\(prefix) \(file)")
            }
        } else {
            print("  Use --verbose to see file list")
        }
    }

    private static func printDifferenceJSONFormat(diff: DirectoryDifference) {
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

        printJSON(result)
    }

    private static func printDifferenceSummaryFormat(diff: DirectoryDifference) {
        let identical =
            diff.onlyInLeft.isEmpty && diff.onlyInRight.isEmpty && diff.modified.isEmpty
        print("Identical: \(identical ? "yes" : "no")")
        print("Only in left: \(diff.onlyInLeft.count)")
        print("Only in right: \(diff.onlyInRight.count)")
        print("Modified: \(diff.modified.count)")
        print("Unchanged: \(diff.common.count)")
        print(
            "Total files: \(diff.onlyInLeft.count + diff.onlyInRight.count + diff.modified.count + diff.common.count)"
        )
    }

    // MARK: - Utility Functions

    private static func printJSON(_ object: [String: Any]) {
        if let jsonData = try? JSONSerialization.data(
            withJSONObject: object, options: .prettyPrinted),
            let jsonString = String(data: jsonData, encoding: .utf8)
        {
            print(jsonString)
        }
    }

    private static func groupOperations(_ operations: [SyncOperation]) -> (
        copies: [SyncOperation],
        updates: [SyncOperation],
        deletes: [SyncOperation],
        infos: [SyncOperation]
    ) {
        let grouped = operations.reduce(
            into: [SyncOperation.OperationType: [SyncOperation]]()
        ) { dict, operation in
            dict[operation.type, default: []].append(operation)
        }

        return (
            copies: grouped[.copy] ?? [],
            updates: grouped[.update] ?? [],
            deletes: grouped[.delete] ?? [],
            infos: grouped[.info] ?? []
        )
    }
}
