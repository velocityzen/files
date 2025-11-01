import Foundation
import Testing

@testable import FilesKit

/// Thread-safe wrapper for mutable state in tests
final class LockIsolated<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self._value = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func withValue<T>(_ operation: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation(&_value)
    }
}

/// Test suite for copyFileWithProgress functionality
@Suite("CopyFileWithProgress")
struct CopyFileWithProgressTests {

    // MARK: - Basic Functionality Tests

    @Test("Copy small file successfully")
    func copySmallFile() async throws {
        let content = "This is a small test file."
        let sourceDir = try TestHelpers.createTestDirectory(files: ["source.txt": content])
        let destDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
            try? TestHelpers.cleanupTestDirectory(destDir)
        }

        let sourcePath = sourceDir.appendingPathComponent("source.txt").path(percentEncoded: false)
        let destPath = destDir.appendingPathComponent("dest.txt").path(percentEncoded: false)
        let fileSize = Int64(content.utf8.count)

        let progressUpdates = LockIsolated<[Int64]>([])

        try copyFileWithProgress(
            from: sourcePath,
            to: destPath,
            fileSize: fileSize
        ) { bytesTransferred in
            progressUpdates.withValue { $0.append(bytesTransferred) }
        }

        // Verify file was copied
        #expect(TestHelpers.fileExists(at: URL(fileURLWithPath: destPath)))
        #expect(try TestHelpers.readFile(at: URL(fileURLWithPath: destPath)) == content)

        // Verify progress was reported
        let updates = progressUpdates.value
        #expect(updates.count > 0)
        #expect(updates.last == fileSize)
    }

    @Test("Copy large file with chunked transfer")
    func copyLargeFile() async throws {
        // Create a file larger than COPY_CHUNK_SIZE (1MB)
        let chunkSize = 1024 * 1024  // 1MB
        let largeContent = String(repeating: "A", count: chunkSize * 2 + 500_000)  // ~2.5MB

        let sourceDir = try TestHelpers.createTestDirectory(files: [:])
        let destDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
            try? TestHelpers.cleanupTestDirectory(destDir)
        }

        let sourceURL = sourceDir.appendingPathComponent("large.txt")
        try largeContent.write(to: sourceURL, atomically: true, encoding: .utf8)

        let sourcePath = sourceURL.path(percentEncoded: false)
        let destPath = destDir.appendingPathComponent("large_copy.txt").path(percentEncoded: false)
        let fileSize = Int64(largeContent.utf8.count)

        let progressUpdates = LockIsolated<[Int64]>([])

        try copyFileWithProgress(
            from: sourcePath,
            to: destPath,
            fileSize: fileSize
        ) { bytesTransferred in
            progressUpdates.withValue { $0.append(bytesTransferred) }
        }

        // Verify file was copied correctly
        #expect(TestHelpers.fileExists(at: URL(fileURLWithPath: destPath)))
        let copiedContent = try TestHelpers.readFile(at: URL(fileURLWithPath: destPath))
        #expect(copiedContent.count == largeContent.count)
        #expect(copiedContent == largeContent)

        // Verify progress was reported multiple times (chunked transfer)
        let updates = progressUpdates.value
        #expect(updates.count > 1)

        // Verify progress is monotonically increasing
        for i in 1..<updates.count {
            #expect(updates[i] > updates[i - 1])
        }

        // Verify final progress matches file size
        #expect(updates.last == fileSize)
    }

    @Test("Copy empty file")
    func copyEmptyFile() async throws {
        let sourceDir = try TestHelpers.createTestDirectory(files: ["empty.txt": ""])
        let destDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
            try? TestHelpers.cleanupTestDirectory(destDir)
        }

        let sourcePath = sourceDir.appendingPathComponent("empty.txt").path(percentEncoded: false)
        let destPath = destDir.appendingPathComponent("empty_copy.txt").path(percentEncoded: false)

        let progressCallCount = LockIsolated<Int>(0)

        try copyFileWithProgress(
            from: sourcePath,
            to: destPath,
            fileSize: 0
        ) { bytesTransferred in
            progressCallCount.withValue { $0 += 1 }
        }

        // Verify empty file was created
        #expect(TestHelpers.fileExists(at: URL(fileURLWithPath: destPath)))
        #expect(try TestHelpers.readFile(at: URL(fileURLWithPath: destPath)) == "")

        // Progress callback may or may not be called for empty files
        // This is acceptable behavior
    }

    @Test("Copy file with special characters in name")
    func copyFileWithSpecialCharacters() async throws {
        let content = "Test content with special filename"
        let filename = "test file (1) [copy] & more!.txt"

        let sourceDir = try TestHelpers.createTestDirectory(files: [filename: content])
        let destDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
            try? TestHelpers.cleanupTestDirectory(destDir)
        }

        let sourcePath = sourceDir.appendingPathComponent(filename).path(percentEncoded: false)
        let destPath = destDir.appendingPathComponent(filename).path(percentEncoded: false)
        let fileSize = Int64(content.utf8.count)

        try copyFileWithProgress(
            from: sourcePath,
            to: destPath,
            fileSize: fileSize,
            progressCallback: nil
        )

        #expect(TestHelpers.fileExists(at: URL(fileURLWithPath: destPath)))
        #expect(try TestHelpers.readFile(at: URL(fileURLWithPath: destPath)) == content)
    }

    @Test("Copy binary file")
    func copyBinaryFile() async throws {
        let sourceDir = try TestHelpers.createTestDirectory(files: [:])
        let destDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
            try? TestHelpers.cleanupTestDirectory(destDir)
        }

        // Create binary data (not valid UTF-8)
        let binaryData = Data(
            [0x00, 0xFF, 0xAA, 0x55, 0xDE, 0xAD, 0xBE, 0xEF]
                + Array(repeating: UInt8(0x42), count: 1000))
        let sourceURL = sourceDir.appendingPathComponent("binary.dat")
        try binaryData.write(to: sourceURL)

        let sourcePath = sourceURL.path(percentEncoded: false)
        let destPath = destDir.appendingPathComponent("binary_copy.dat").path(percentEncoded: false)
        let fileSize = Int64(binaryData.count)

        try copyFileWithProgress(
            from: sourcePath,
            to: destPath,
            fileSize: fileSize,
            progressCallback: nil
        )

        // Verify binary file was copied correctly
        #expect(TestHelpers.fileExists(at: URL(fileURLWithPath: destPath)))
        let copiedData = try Data(contentsOf: URL(fileURLWithPath: destPath))
        #expect(copiedData == binaryData)
    }

    // MARK: - Progress Callback Tests

    @Test("Progress callback is called with nil callback parameter")
    func progressCallbackNil() async throws {
        let content = "Test content"
        let sourceDir = try TestHelpers.createTestDirectory(files: ["file.txt": content])
        let destDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
            try? TestHelpers.cleanupTestDirectory(destDir)
        }

        let sourcePath = sourceDir.appendingPathComponent("file.txt").path(percentEncoded: false)
        let destPath = destDir.appendingPathComponent("copy.txt").path(percentEncoded: false)
        let fileSize = Int64(content.utf8.count)

        // Should not crash with nil callback
        try copyFileWithProgress(
            from: sourcePath,
            to: destPath,
            fileSize: fileSize,
            progressCallback: nil
        )

        #expect(TestHelpers.fileExists(at: URL(fileURLWithPath: destPath)))
    }

    @Test("Progress callback reports accurate byte counts")
    func progressCallbackAccuracy() async throws {
        // Create a file of known size
        let testSize = 5 * 1024 * 1024  // 5MB
        let content = String(repeating: "B", count: testSize)

        let sourceDir = try TestHelpers.createTestDirectory(files: [:])
        let destDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
            try? TestHelpers.cleanupTestDirectory(destDir)
        }

        let sourceURL = sourceDir.appendingPathComponent("5mb.txt")
        try content.write(to: sourceURL, atomically: true, encoding: .utf8)

        let sourcePath = sourceURL.path(percentEncoded: false)
        let destPath = destDir.appendingPathComponent("5mb_copy.txt").path(percentEncoded: false)
        let fileSize = Int64(content.utf8.count)

        let progressUpdates = LockIsolated<[Int64]>([])

        try copyFileWithProgress(
            from: sourcePath,
            to: destPath,
            fileSize: fileSize
        ) { bytesTransferred in
            progressUpdates.withValue { $0.append(bytesTransferred) }
        }

        // Verify all progress values are within bounds
        let updates = progressUpdates.value
        for progress in updates {
            #expect(progress > 0)
            #expect(progress <= fileSize)
        }

        // Verify final progress equals file size
        #expect(updates.last == fileSize)
    }

    @Test("Progress callback is called multiple times for large files")
    func progressCallbackMultipleCalls() async throws {
        // Create a file larger than chunk size to ensure multiple callbacks
        let largeSize = COPY_CHUNK_SIZE * 3  // 3MB
        let content = String(repeating: "C", count: largeSize)

        let sourceDir = try TestHelpers.createTestDirectory(files: [:])
        let destDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
            try? TestHelpers.cleanupTestDirectory(destDir)
        }

        let sourceURL = sourceDir.appendingPathComponent("3mb.txt")
        try content.write(to: sourceURL, atomically: true, encoding: .utf8)

        let sourcePath = sourceURL.path(percentEncoded: false)
        let destPath = destDir.appendingPathComponent("3mb_copy.txt").path(percentEncoded: false)
        let fileSize = Int64(content.utf8.count)

        let callCount = LockIsolated<Int>(0)

        try copyFileWithProgress(
            from: sourcePath,
            to: destPath,
            fileSize: fileSize
        ) { _ in
            callCount.withValue { $0 += 1 }
        }

        // Should have multiple progress callbacks for a 3MB file
        #expect(callCount.value >= 3)
    }

    // MARK: - Error Handling Tests

    @Test("Throws error when destination directory doesn't exist and can't be created")
    func errorDestinationInvalid() async throws {
        let sourceDir = try TestHelpers.createTestDirectory(files: ["source.txt": "content"])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
        }

        let sourcePath = sourceDir.appendingPathComponent("source.txt").path(percentEncoded: false)
        // Use a path that can't be created (e.g., inside a file instead of a directory)
        let destPath = "/dev/null/impossible/path/dest.txt"

        #expect(throws: DirectorySyncError.self) {
            try copyFileWithProgress(
                from: sourcePath,
                to: destPath,
                fileSize: 7,
                progressCallback: nil
            )
        }
    }

    // MARK: - Edge Cases

    @Test("Copy file to same location (overwrite)")
    func copyToSameLocation() async throws {
        let originalContent = "Original content"
        let sourceDir = try TestHelpers.createTestDirectory(files: ["file.txt": originalContent])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
        }

        let filePath = sourceDir.appendingPathComponent("file.txt").path(percentEncoded: false)
        let fileSize = Int64(originalContent.utf8.count)

        // This should work - copying a file to itself
        try copyFileWithProgress(
            from: filePath,
            to: filePath,
            fileSize: fileSize,
            progressCallback: nil
        )

        #expect(TestHelpers.fileExists(at: URL(fileURLWithPath: filePath)))
    }

    @Test("Copy file with incorrect fileSize parameter")
    func copyWithIncorrectFileSize() async throws {
        let content = "Actual content"
        let sourceDir = try TestHelpers.createTestDirectory(files: ["source.txt": content])
        let destDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
            try? TestHelpers.cleanupTestDirectory(destDir)
        }

        let sourcePath = sourceDir.appendingPathComponent("source.txt").path(percentEncoded: false)
        let destPath = destDir.appendingPathComponent("dest.txt").path(percentEncoded: false)

        // Provide wrong file size (much larger than actual)
        let incorrectSize: Int64 = 10_000

        let lastProgress = LockIsolated<Int64>(0)

        try copyFileWithProgress(
            from: sourcePath,
            to: destPath,
            fileSize: incorrectSize
        ) { bytesTransferred in
            lastProgress.withValue { $0 = bytesTransferred }
        }

        // File should still be copied correctly
        #expect(TestHelpers.fileExists(at: URL(fileURLWithPath: destPath)))
        #expect(try TestHelpers.readFile(at: URL(fileURLWithPath: destPath)) == content)

        // Progress will reflect actual bytes read, not the incorrect size
        #expect(lastProgress.value == Int64(content.utf8.count))
    }

    @Test("Copy file replaces existing destination file")
    func copyReplacesExisting() async throws {
        let newContent = "New content"
        let oldContent = "Old content that should be replaced"

        let sourceDir = try TestHelpers.createTestDirectory(files: ["source.txt": newContent])
        let destDir = try TestHelpers.createTestDirectory(files: ["dest.txt": oldContent])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
            try? TestHelpers.cleanupTestDirectory(destDir)
        }

        let sourcePath = sourceDir.appendingPathComponent("source.txt").path(percentEncoded: false)
        let destPath = destDir.appendingPathComponent("dest.txt").path(percentEncoded: false)
        let fileSize = Int64(newContent.utf8.count)

        try copyFileWithProgress(
            from: sourcePath,
            to: destPath,
            fileSize: fileSize,
            progressCallback: nil
        )

        // Verify old content was replaced with new content
        #expect(try TestHelpers.readFile(at: URL(fileURLWithPath: destPath)) == newContent)
        #expect(try TestHelpers.readFile(at: URL(fileURLWithPath: destPath)) != oldContent)
    }

    @Test("Copy file with very long content")
    func copyVeryLargeFile() async throws {
        // Create a 10MB file
        let largeSize = 10 * 1024 * 1024
        let content = String(repeating: "D", count: largeSize)

        let sourceDir = try TestHelpers.createTestDirectory(files: [:])
        let destDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(sourceDir)
            try? TestHelpers.cleanupTestDirectory(destDir)
        }

        let sourceURL = sourceDir.appendingPathComponent("10mb.txt")
        try content.write(to: sourceURL, atomically: true, encoding: .utf8)

        let sourcePath = sourceURL.path(percentEncoded: false)
        let destPath = destDir.appendingPathComponent("10mb_copy.txt").path(percentEncoded: false)
        let fileSize = Int64(content.utf8.count)

        let progressUpdates = LockIsolated<[Int64]>([])

        try copyFileWithProgress(
            from: sourcePath,
            to: destPath,
            fileSize: fileSize
        ) { bytesTransferred in
            progressUpdates.withValue { $0.append(bytesTransferred) }
        }

        // Verify file was copied
        #expect(TestHelpers.fileExists(at: URL(fileURLWithPath: destPath)))

        // Verify size matches
        let attrs = try FileManager.default.attributesOfItem(atPath: destPath)
        let copiedSize = (attrs[.size] as? Int64) ?? 0
        #expect(copiedSize == fileSize)

        // Should have many progress updates for a 10MB file
        let updates = progressUpdates.value
        #expect(updates.count >= 10)

        // Verify final progress
        #expect(updates.last == fileSize)
    }

    @Test("Copy preserves file content integrity")
    func copyPreservesContentIntegrity() async throws {
        // Test with various content types to ensure integrity
        let testCases = [
            "Simple ASCII text",
            "Unicode: 你好世界 🌍 café",
            "Special chars: \n\t\r\\\"'",
            String(repeating: "X", count: 100_000),  // Large content
        ]

        for (index, content) in testCases.enumerated() {
            let sourceDir = try TestHelpers.createTestDirectory(files: ["file\(index).txt": content]
            )
            let destDir = try TestHelpers.createTestDirectory(files: [:])

            defer {
                try? TestHelpers.cleanupTestDirectory(sourceDir)
                try? TestHelpers.cleanupTestDirectory(destDir)
            }

            let sourcePath = sourceDir.appendingPathComponent("file\(index).txt").path(
                percentEncoded: false)
            let destPath = destDir.appendingPathComponent("copy\(index).txt").path(
                percentEncoded: false)
            let fileSize = Int64(content.utf8.count)

            try copyFileWithProgress(
                from: sourcePath,
                to: destPath,
                fileSize: fileSize,
                progressCallback: nil
            )

            let copiedContent = try TestHelpers.readFile(at: URL(fileURLWithPath: destPath))
            #expect(copiedContent == content, "Content mismatch for test case \(index)")
        }
    }
}
