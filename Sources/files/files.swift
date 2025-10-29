import ArgumentParser
import FilesKit
import Foundation

@main
struct Files: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "files",
        abstract: "Compare and synchronize directories",
        discussion: """
            A tool for comparing and synchronizing directories with support for:
            - Directory comparison and difference reporting
            - One-way and two-way directory synchronization
            - Conflict resolution strategies
            - Dry-run mode for previewing changes
            """,
        version: "1.1.0",
        subcommands: [CompareCommand.self, SyncCommand.self],
        defaultSubcommand: CompareCommand.self
    )
}
