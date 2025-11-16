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

        @Flag(
            name: .long,
            help: "Scan leaf directories on the right side for additional diff information")
        var showMoreRight: Bool = false

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

                // Setup progress display for text format
                let progressDisplay: ProgressFormatter? =
                    (format == .text && !dryRun) ? ProgressFormatter() : nil

                let syncResult = await directorySync(
                    left: sourcePath,
                    right: destinationPath,
                    mode: .oneWay,
                    recursive: true,
                    deletions: false,
                    showMoreRight: showMoreRight,
                    dryRun: dryRun,
                    ignore: noIgnore ? Ignore() : nil
                )

                // Consume the stream and collect results
                var results: [OperationResult] = []

                for await operationResult in syncResult {
                    results.append(operationResult)

                    // Display completed operation if enabled
                    if let display = progressDisplay {
                        switch operationResult {
                            case .success(let success):
                                OutputFormatter.printOperation(success.operation)
                            case .failure(let failure):
                                OutputFormatter.printOperation(failure.operation)
                        }
                    }
                }

                if let display = progressDisplay {
                    await display.complete()
                }

                OutputFormatter.printSyncResults(
                    results: results,
                    format: format,
                    verbose: verbose,
                    dryRun: dryRun
                )

                if !dryRun && results.failed > 0 {
                    throw ExitCode(1)
                }
            } catch let error as DirectorySyncError {
                OutputFormatter.printError(error)
                throw ExitCode(2)
            }
        }

    }
}
