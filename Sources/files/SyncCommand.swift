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

        @Flag(
            name: .long,
            help: "Delete files in destination that don't exist in source (one-way sync only)")
        var deletions: Bool = false

        @Flag(name: .long, help: "Preview changes without applying them")
        var dryRun: Bool = false

        @Flag(name: [.short, .long], help: "Show detailed output with all operations")
        var verbose: Bool = false

        @Option(name: .long, help: "Output format: text (default), json")
        var format: OutputFormat = .text

        @Flag(name: .long, help: "Disable .filesignore pattern matching")
        var noIgnore: Bool = false

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

                // Setup progress display for text format
                let progressDisplay: ProgressFormatter? =
                    (format == .text && !dryRun) ? ProgressFormatter() : nil

                let progressHandler: ProgressHandler? =
                    if let display = progressDisplay {
                        { progress in
                            Task {
                                await display.display(progress)
                            }
                        }
                    } else {
                        nil
                    }

                let result = try await directorySync(
                    left: sourcePath,
                    right: destinationPath,
                    mode: syncMode,
                    recursive: recursive,
                    deletions: deletions,
                    dryRun: dryRun,
                    ignore: noIgnore ? Ignore() : nil,
                    progress: progressHandler
                )

                // Complete progress display
                if let display = progressDisplay {
                    await display.complete()
                }

                printSyncResults(result: result, format: format, verbose: verbose, dryRun: dryRun)

                if !dryRun && result.failed > 0 {
                    throw ExitCode(1)
                }
            } catch let error as DirectorySyncError {
                OutputFormatter.printError(error)
                throw ExitCode(2)
            }
        }

        func printSyncResults(
            result: SyncResult, format: OutputFormat, verbose: Bool, dryRun: Bool
        ) {
            switch format {
            case .text:
                printSyncTextFormat(result: result, verbose: verbose, dryRun: dryRun)
            case .json, .summary:
                OutputFormatter.printSyncResults(
                    result: result, format: format, verbose: verbose, dryRun: dryRun)
            }
        }

        func printSyncTextFormat(result: SyncResult, verbose: Bool, dryRun: Bool) {
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
                OutputFormatter.printOperationList(
                    "Copy", prefix: " +", operations: copies,
                    verbose: verbose
                )
                print()
            }

            if !updates.isEmpty {
                OutputFormatter.printOperationList(
                    "Update", prefix: " ^", operations: updates,
                    verbose: verbose)
                print()
            }

            if !deletes.isEmpty {
                OutputFormatter.printOperationList(
                    "Delete", prefix: " -", operations: deletes,
                    verbose: verbose)
                print()
            }

            if !dryRun {
                print(
                    "Summary: \(result.succeeded) succeeded, \(result.failed) failed, \(result.skipped) skipped"
                )
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
