import ArgumentParser
import Foundation
import Testing

@testable import FilesKit
@testable import files

@Suite("CLI output")
struct CLIOutputTests {
    @Test("compare --format json writes only JSON to stdout, even with a .files present")
    func compareJSONIsClean() async throws {
        let workDir = try TestHelpers.createTestDirectory(files: [
            "left/.files": "recursive = true\n",
            "left/a.txt": "a",
            "right/b.txt": "b",
        ])

        defer {
            try? TestHelpers.cleanupTestDirectory(workDir)
        }

        let compare = try TestHelpers.runFiles(
            ["compare", "left", "right", "--format", "json"], in: workDir)

        #expect(compare.status == 1)
        #expect(compare.stderr.contains("Using config:"))
        let json = try #require(
            try JSONSerialization.jsonObject(with: compare.stdout) as? [String: Any])
        #expect(json["onlyInLeft"] as? [String] == ["a.txt"])

        // The documented snapshot workflow works on that output
        try compare.stdout.write(to: workDir.appendingPathComponent("snapshot.json"))
        let snapshot = try TestHelpers.runFiles(
            ["compare-snapshot", "snapshot.json", "snapshot.json"], in: workDir)
        #expect(snapshot.status == 0)
    }

    @Test("sync --format json writes only JSON to stdout in a dry run")
    func syncJSONIsClean() async throws {
        let workDir = try TestHelpers.createTestDirectory(files: [
            "left/.files": "verbose = true\n",
            "left/a.txt": "a",
        ])
        try FileManager.default.createDirectory(
            at: workDir.appendingPathComponent("right"), withIntermediateDirectories: true)

        defer {
            try? TestHelpers.cleanupTestDirectory(workDir)
        }

        let sync = try TestHelpers.runFiles(
            ["sync", "left", "right", "--format", "json", "--dry-run"], in: workDir)

        #expect(sync.status == 0)
        #expect(sync.stderr.contains("DRY RUN"))
        let json = try #require(
            try JSONSerialization.jsonObject(with: sync.stdout) as? [String: Any])
        #expect((json["operations"] as? [[String: String]])?.count == 1)
    }

    @Test("sync --dry-run reports a comparison error and exits non-zero")
    func dryRunReportsFailures() async throws {
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        var command = try Files.SyncCommand.parse([
            "/nonexistent-\(UUID().uuidString)", rightDir.path(percentEncoded: false),
            "--dry-run",
        ])

        await #expect(throws: ExitCode(1)) {
            try await command.run()
        }
    }
}
