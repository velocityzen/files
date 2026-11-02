import Foundation
import Testing

@testable import FilesKit

@Suite("Copy safety")
struct CopySafetyTests {
    /// Size just over the threshold where copies switch to chunked streaming
    let largeFileSize = minSizeToChunk + copyChunkSize

    @Test("A failed update leaves the destination file intact")
    func failedUpdateKeepsDestination() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: ["a.txt": "new content"])
        let rightDir = try TestHelpers.createTestDirectory(files: ["a.txt": "old but precious"])

        let source = leftDir.appendingPathComponent("a.txt").path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source)

        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: source)
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        // Permissions don't stop root, so there is nothing to test there
        guard !FileManager.default.isReadableFile(atPath: source) else {
            return
        }

        let results = await TestHelpers.collect(
            await directorySync(
                left: leftDir.path(percentEncoded: false),
                right: rightDir.path(percentEncoded: false),
                mode: .oneWay,
                ignore: Ignore(patterns: [])
            ))

        #expect(results.failed == 1)
        #expect(
            try TestHelpers.readFile(at: rightDir.appendingPathComponent("a.txt"))
                == "old but precious")
        #expect(try TestHelpers.leftoverTempFiles(in: rightDir).isEmpty)
    }

    @Test("A large file copy keeps permissions and modification date")
    func largeCopyKeepsMetadata() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [:])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let source = leftDir.appendingPathComponent("big.bin")
        let modificationDate = Date(timeIntervalSince1970: 1_577_836_800)
        try Data(repeating: 7, count: largeFileSize).write(to: source)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755, .modificationDate: modificationDate],
            ofItemAtPath: source.path(percentEncoded: false)
        )

        let results = await TestHelpers.collect(
            await directorySync(
                left: leftDir.path(percentEncoded: false),
                right: rightDir.path(percentEncoded: false),
                mode: .oneWay,
                ignore: Ignore(patterns: [])
            ))

        #expect(results.failed == 0)
        #expect(
            results.contains {
                if case .success(let success) = $0 {
                    return success.bytesTransferred == Int64(largeFileSize)
                }
                return false
            })

        let attrs = try FileManager.default.attributesOfItem(
            atPath: rightDir.appendingPathComponent("big.bin").path(percentEncoded: false))
        #expect((attrs[.size] as? Int64) == Int64(largeFileSize))
        #expect((attrs[.posixPermissions] as? Int) == 0o755)
        #expect((attrs[.modificationDate] as? Date) == modificationDate)
        #expect(try TestHelpers.leftoverTempFiles(in: rightDir).isEmpty)
    }

    @Test("A large file update replaces the existing destination file")
    func largeUpdateReplacesDestination() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [:])
        let rightDir = try TestHelpers.createTestDirectory(files: ["big.bin": "old"])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let content = Data(repeating: 3, count: largeFileSize)
        try content.write(to: leftDir.appendingPathComponent("big.bin"))

        let results = await TestHelpers.collect(
            await directorySync(
                left: leftDir.path(percentEncoded: false),
                right: rightDir.path(percentEncoded: false),
                mode: .oneWay,
                ignore: Ignore(patterns: [])
            ))

        #expect(results.failed == 0)
        #expect(results.operations.allSatisfy { $0.type == .update })
        #expect(try Data(contentsOf: rightDir.appendingPathComponent("big.bin")) == content)
        #expect(try TestHelpers.leftoverTempFiles(in: rightDir).isEmpty)
    }

    @Test(
        "Files with names near the length limit are copied, small and large",
        arguments: [false, true])
    func longNames(large: Bool) async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [:])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        // 250 bytes leaves no room to add anything to the name
        let name = String(repeating: "n", count: 246) + ".bin"
        let content = Data(repeating: 5, count: large ? largeFileSize : 10)
        try content.write(to: leftDir.appendingPathComponent(name))

        let results = await TestHelpers.collect(
            await directorySync(
                left: leftDir.path(percentEncoded: false),
                right: rightDir.path(percentEncoded: false),
                mode: .oneWay,
                ignore: Ignore(patterns: [])
            ))

        #expect(results.failed == 0)
        #expect(try Data(contentsOf: rightDir.appendingPathComponent(name)) == content)
        #expect(try TestHelpers.leftoverTempFiles(in: rightDir).isEmpty)
    }

    @Test("Two-way newest copies a newer left file to the right")
    func twoWayNewestLeftNewer() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [:])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        try TestHelpers.createFile(
            at: leftDir.appendingPathComponent("doc.txt"), content: "newer left",
            modificationDate: Date(timeIntervalSince1970: 2_000_000))
        try TestHelpers.createFile(
            at: rightDir.appendingPathComponent("doc.txt"), content: "older right",
            modificationDate: Date(timeIntervalSince1970: 1_000_000))

        let results = await TestHelpers.collect(
            await directorySync(
                left: leftDir.path(percentEncoded: false),
                right: rightDir.path(percentEncoded: false),
                mode: .twoWay(conflictResolution: .keepNewest),
                ignore: Ignore(patterns: [])
            ))

        #expect(results.failed == 0)
        #expect(
            try TestHelpers.readFile(at: rightDir.appendingPathComponent("doc.txt"))
                == "newer left")
        #expect(
            try TestHelpers.readFile(at: leftDir.appendingPathComponent("doc.txt"))
                == "newer left")
    }

    @Test("Show-more-right sync reports extra files only in the source's leaf folders")
    func showMoreRightInfoOperations() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: ["photos/a.jpg": "a"])
        let rightDir = try TestHelpers.createTestDirectory(files: [
            "photos/a.jpg": "a",
            "photos/extra.jpg": "extra",
            "other/x.txt": "x",
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
                showMoreRight: true,
                ignore: Ignore(patterns: [])
            ))

        #expect(results.failed == 0)
        #expect(results.operations.map(\.relativePath) == ["photos/extra.jpg"])
        #expect(results.operations.first?.type == .info)
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("photos/extra.jpg")))
    }
}
