import Foundation
import Testing

@testable import FilesKit
@testable import files

@Suite("Config precedence and trust")
struct ConfigPrecedenceTests {
    // MARK: - Untrusted left .files

    @Test("Untrusted left .files drops settings that delete or overwrite files")
    func untrustedLeftDropsDestructiveSettings() async throws {
        let leftFiles = [
            ".files":
                "deletions = true\ntwoWay = true\nconflictResolution = left\nnoIgnore = true\nmatchPrecision = 0.8\n"
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let config = await Config.load(
            leftPath: leftDir.path(percentEncoded: false),
            rightPath: rightDir.path(percentEncoded: false),
            trustLeft: false
        )

        #expect(config.deletions == nil)
        #expect(config.twoWay == nil)
        #expect(config.conflictResolution == nil)
        #expect(config.noIgnore == nil)
        #expect(config.matchPrecision == 0.8)
        #expect(
            config.ignoredSettings.map(\.setting) == [
                "deletions = true", "twoWay = true", "conflictResolution = left",
                "noIgnore = true",
            ])
        #expect(config.ignoredSettings.allSatisfy { $0.file.hasSuffix("/.files") })
    }

    @Test("Untrusted left .files does not affect right .files")
    func untrustedLeftKeepsRightSettings() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [".files": "deletions = false\n"])
        let rightDir = try TestHelpers.createTestDirectory(files: [
            ".files": "deletions = true\ntwoWay = true\n"
        ])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let config = await Config.load(
            leftPath: leftDir.path(percentEncoded: false),
            rightPath: rightDir.path(percentEncoded: false),
            trustLeft: false
        )

        #expect(config.deletions == true)
        #expect(config.twoWay == true)
        #expect(config.ignoredSettings.map(\.setting) == ["deletions = false"])
        #expect(config.loadedFiles.count == 2)
    }

    @Test("Left .files is trusted by default")
    func leftTrustedByDefault() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [".files": "deletions = true\n"])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let config = await Config.load(
            leftPath: leftDir.path(percentEncoded: false),
            rightPath: rightDir.path(percentEncoded: false)
        )

        #expect(config.deletions == true)
        #expect(config.ignoredSettings.isEmpty)
    }

    // MARK: - CLI

    @Test("sync: source .files cannot enable deletions")
    func syncSourceConfigCannotDelete() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [
            ".files": "deletions = true\n",
            "a.txt": "a",
        ])
        let rightDir = try TestHelpers.createTestDirectory(files: ["precious.txt": "keep me"])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        var command = try Files.SyncCommand.parse([
            leftDir.path(percentEncoded: false), rightDir.path(percentEncoded: false),
        ])
        try await command.run()

        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("a.txt")))
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("precious.txt")))
    }

    @Test("sync: source .files cannot enable two-way sync")
    func syncSourceConfigCannotEnableTwoWay() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [".files": "twoWay = true\n"])
        let rightDir = try TestHelpers.createTestDirectory(files: ["b.txt": "b"])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        var command = try Files.SyncCommand.parse([
            leftDir.path(percentEncoded: false), rightDir.path(percentEncoded: false),
        ])
        try await command.run()

        #expect(!TestHelpers.fileExists(at: leftDir.appendingPathComponent("b.txt")))
    }

    @Test("sync: --dry-run overrides dryRun = false in .files")
    func syncDryRunFlagOverridesConfig() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [
            ".files": "dryRun = false\n",
            "new.txt": "new",
        ])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        var command = try Files.SyncCommand.parse([
            leftDir.path(percentEncoded: false), rightDir.path(percentEncoded: false),
            "--dry-run",
        ])
        try await command.run()

        #expect(!TestHelpers.fileExists(at: rightDir.appendingPathComponent("new.txt")))
    }

    @Test("sync: --no-deletions overrides deletions = true in destination .files")
    func syncNoDeletionsFlagOverridesConfig() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: ["a.txt": "a"])
        let rightDir = try TestHelpers.createTestDirectory(files: [
            ".files": "deletions = true\n",
            "extra.txt": "extra",
        ])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let left = leftDir.path(percentEncoded: false)
        let right = rightDir.path(percentEncoded: false)

        var keep = try Files.SyncCommand.parse([left, right, "--no-deletions"])
        try await keep.run()
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("extra.txt")))

        // Without the flag the destination .files applies
        var delete = try Files.SyncCommand.parse([left, right])
        try await delete.run()
        #expect(!TestHelpers.fileExists(at: rightDir.appendingPathComponent("extra.txt")))
    }

    @Test("sync: --recursive overrides recursive = false in .files")
    func syncRecursiveFlagOverridesConfig() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [
            ".files": "recursive = false\n",
            "sub/nested.txt": "nested",
        ])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        var command = try Files.SyncCommand.parse([
            leftDir.path(percentEncoded: false), rightDir.path(percentEncoded: false),
            "--recursive",
        ])
        try await command.run()

        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("sub/nested.txt")))
    }

    @Test("cp: --dry-run overrides dryRun = false in .files")
    func copyDryRunFlagOverridesConfig() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [
            ".files": "dryRun = false\n",
            "new.txt": "new",
        ])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        var command = try Files.CopyCommand.parse([
            leftDir.path(percentEncoded: false), rightDir.path(percentEncoded: false),
            "--dry-run",
        ])
        try await command.run()

        #expect(!TestHelpers.fileExists(at: rightDir.appendingPathComponent("new.txt")))
    }

    @Test("compare, sync and cp reject --concurrent-reads below 1 and accept 1")
    func concurrentReadsIsValidated() throws {
        let paths = ["left", "right"]
        for value in ["0", "-2"] {
            let arguments = paths + ["--concurrent-reads", value]
            #expect(throws: (any Error).self) { try Files.CompareCommand.parse(arguments) }
            #expect(throws: (any Error).self) { try Files.SyncCommand.parse(arguments) }
            #expect(throws: (any Error).self) { try Files.CopyCommand.parse(arguments) }
        }

        let one = paths + ["--concurrent-reads", "1"]
        #expect(try Files.CompareCommand.parse(one).concurrentReads == 1)
        #expect(try Files.SyncCommand.parse(one).concurrentReads == 1)
        #expect(try Files.CopyCommand.parse(one).concurrentReads == 1)
    }

    @Test("cp: source .files cannot disable ignore patterns")
    func copySourceConfigCannotDisableIgnore() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [
            ".files": "noIgnore = true\n",
            "local.db": "source copy",
        ])
        let rightDir = try TestHelpers.createTestDirectory(files: [
            ".filesignore": "local.db\n",
            "local.db": "destination copy",
        ])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        var command = try Files.CopyCommand.parse([
            leftDir.path(percentEncoded: false), rightDir.path(percentEncoded: false),
        ])
        try await command.run()

        let content = try TestHelpers.readFile(at: rightDir.appendingPathComponent("local.db"))
        #expect(content == "destination copy")
    }
}
