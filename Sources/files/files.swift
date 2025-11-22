import ArgumentParser
import FilesKit
import Foundation

@main
struct Files: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "files",
        abstract: "Files Toolbox",
        discussion: """
            - Directory comparison and difference reporting
            - Snapshot comparison
            - One-way and two-way directory synchronization
            - Copy new and modified files without deletion
            - Conflict resolution strategies
            - Dry-run mode for previewing changes
            """,
        version: "1.5.1",
        subcommands: [
            CompareCommand.self,
            CompareSnapshotCommand.self,
            SyncCommand.self,
            CopyCommand.self,
        ],
        defaultSubcommand: CompareCommand.self
    )
}
