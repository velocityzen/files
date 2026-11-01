import Foundation
import Testing

@testable import FilesKit

@Suite("Ignore patterns during scans")
struct ScanIgnoreTests {
    @Test("Directory-only pattern ignores files inside the directory at any depth")
    func directoryPatternIgnoresContents() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [
            "node_modules/a.js": "a",
            "pkg/node_modules/deep/b.js": "b",
            "keep.txt": "keep",
        ])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            ignore: Ignore(patterns: ["node_modules/"])
        ).unwrap()

        #expect(diff.onlyInLeft == ["keep.txt"])
    }

    @Test("Directory-only pattern does not ignore a file with that name")
    func directoryPatternKeepsSameNamedFile() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [
            "build": "a file named build",
            "src/build/out.o": "object",
        ])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            ignore: Ignore(patterns: ["build/"])
        ).unwrap()

        #expect(diff.onlyInLeft == ["build"])
    }

    @Test("Like .gitignore, a negation can't re-include a file inside an ignored directory")
    func negationInsideIgnoredDirectory() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [
            "logs/keep.txt": "keep",
            "logs/debug.txt": "debug",
        ])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            ignore: Ignore(patterns: ["logs/", "!logs/keep.txt"])
        ).unwrap()

        #expect(diff.onlyInLeft.isEmpty)
    }

    @Test("Files in an ignored destination directory are not deleted")
    func ignoredDirectoryProtectedFromDeletions() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: ["a.txt": "a"])
        let rightDir = try TestHelpers.createTestDirectory(files: [
            "a.txt": "a",
            "cache/local.db": "local only",
        ])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let results = await TestHelpers.collect(
            await directorySync(
                left: leftDir.path(percentEncoded: false),
                right: rightDir.path(percentEncoded: false),
                mode: .oneWay,
                deletions: true,
                ignore: Ignore(patterns: ["cache/"])
            ))

        #expect(results.operations.isEmpty)
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("cache/local.db")))
    }
}
