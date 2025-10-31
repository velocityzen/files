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

        @Flag(name: .long, help: "Disable .filesignore pattern matching")
        var noIgnore: Bool = false

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
                    dryRun: dryRun,
                    ignore: noIgnore ? Ignore() : nil
                )

                printCopyResults(
                    result: result,
                    format: format,
                    verbose: verbose,
                    dryRun: dryRun
                )

                if !dryRun && result.failed > 0 {
                    throw ExitCode(1)
                }
            } catch let error as DirectorySyncError {
                OutputFormatter.printError(error)
                throw ExitCode(2)
            }
        }

        func printCopyResults(
            result: SyncResult, format: OutputFormat, verbose: Bool, dryRun: Bool
        ) {
            switch format {
            case .text:
                printCopyTextFormat(result: result, verbose: verbose, dryRun: dryRun)
            case .json:
                OutputFormatter.printSyncResults(
                    result: result, format: format, verbose: verbose, dryRun: dryRun)
            case .summary:
                printCopySummaryFormat(result: result, dryRun: dryRun)
            }
        }

        func printCopyTextFormat(result: SyncResult, verbose: Bool, dryRun: Bool) {
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
                OutputFormatter.printOperationList(
                    "New files", verb: dryRun ? "would copy" : "copied", operations: copies,
                    verbose: verbose
                )
                print()
            }

            if !updates.isEmpty {
                OutputFormatter.printOperationList(
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

        func printCopySummaryFormat(result: SyncResult, dryRun: Bool) {
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
