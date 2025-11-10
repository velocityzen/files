import Foundation
import Testing

@testable import FilesKit

/// Test suite for directory synchronization functionality
@Suite("DirectorySync")
struct DirectorySyncTests {

    // MARK: - One-Way Sync Tests

    @Test("One-way sync: copy files from left to right")
    func oneWaySyncCopyFiles() async throws {
        let leftFiles = [
            "file1.txt": "content1",
            "file2.txt": "content2",
        ]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        // Create isolated ignore patterns (don't load from home directory)
        let ignore = Ignore(patterns: ["*.log", "*.tmp"])

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay,
            ignore: ignore
        )

        #expect(result.succeeded == 2)
        #expect(result.failed == 0)
        #expect(result.operations.count == 2)
        #expect(result.operations.allSatisfy { $0.type == .copy })

        // Verify files were copied
        let file1 = rightDir.appendingPathComponent("file1.txt")
        let file2 = rightDir.appendingPathComponent("file2.txt")
        #expect(TestHelpers.fileExists(at: file1))
        #expect(TestHelpers.fileExists(at: file2))
        #expect(try TestHelpers.readFile(at: file1) == "content1")
        #expect(try TestHelpers.readFile(at: file2) == "content2")
    }

    @Test("One-way sync: no deletions by default")
    func oneWaySyncNoDeletesByDefault() async throws {
        let leftFiles: [String: String] = [:]
        let rightFiles = [
            "old1.txt": "old content",
            "old2.txt": "old content",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay
        )

        // Should have no operations since deletions are disabled by default
        #expect(result.succeeded == 0)
        #expect(result.failed == 0)
        #expect(result.operations.count == 0)

        // Verify files were NOT deleted
        let file1 = rightDir.appendingPathComponent("old1.txt")
        let file2 = rightDir.appendingPathComponent("old2.txt")
        #expect(TestHelpers.fileExists(at: file1))
        #expect(TestHelpers.fileExists(at: file2))
    }

    @Test("One-way sync: delete files when deletions enabled")
    func oneWaySyncDeleteFilesWhenEnabled() async throws {
        let leftFiles: [String: String] = [:]
        let rightFiles = [
            "old1.txt": "old content",
            "old2.txt": "old content",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay,
            deletions: true
        )

        #expect(result.succeeded == 2)
        #expect(result.failed == 0)
        #expect(result.operations.count == 2)
        #expect(result.operations.allSatisfy { $0.type == .delete })

        // Verify files were deleted
        let file1 = rightDir.appendingPathComponent("old1.txt")
        let file2 = rightDir.appendingPathComponent("old2.txt")
        #expect(!TestHelpers.fileExists(at: file1))
        #expect(!TestHelpers.fileExists(at: file2))
    }

    @Test("One-way sync: update modified files")
    func oneWaySyncUpdateFiles() async throws {
        let leftFiles = [
            "file.txt": "new content"
        ]
        let rightFiles = [
            "file.txt": "old content"
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay
        )

        #expect(result.succeeded == 1)
        #expect(result.failed == 0)
        #expect(result.operations.count == 1)
        #expect(result.operations.first?.type == .update)

        // Verify file was updated
        let file = rightDir.appendingPathComponent("file.txt")
        #expect(try TestHelpers.readFile(at: file) == "new content")
    }

    @Test("One-way sync: complete scenario with all operation types")
    func oneWaySyncCompleteScenario() async throws {
        let leftFiles = [
            "common.txt": "same",
            "modified.txt": "left version",
            "left_only.txt": "left",
            "subdir/nested.txt": "nested",
        ]
        let rightFiles = [
            "common.txt": "same",
            "modified.txt": "right version",
            "right_only.txt": "right",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay,
            deletions: true
        )

        #expect(result.succeeded == 4)  // 2 copies + 1 update + 1 delete
        #expect(result.failed == 0)

        let copyOps = result.operations.filter { $0.type == .copy }
        let updateOps = result.operations.filter { $0.type == .update }
        let deleteOps = result.operations.filter { $0.type == .delete }

        #expect(copyOps.count == 2)
        #expect(updateOps.count == 1)
        #expect(deleteOps.count == 1)

        // Verify final state
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("common.txt")))
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("left_only.txt")))
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("subdir/nested.txt")))
        #expect(
            try TestHelpers.readFile(at: rightDir.appendingPathComponent("modified.txt"))
                == "left version")
        #expect(!TestHelpers.fileExists(at: rightDir.appendingPathComponent("right_only.txt")))
    }

    // MARK: - Two-Way Sync Tests

    @Test("Two-way sync: copy files from both directories")
    func twoWaySyncCopyBothDirections() async throws {
        let leftFiles = [
            "left_only.txt": "left content"
        ]
        let rightFiles = [
            "right_only.txt": "right content"
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .twoWay(conflictResolution: .keepNewest)
        )

        #expect(result.succeeded == 2)
        #expect(result.failed == 0)
        #expect(result.operations.count == 2)
        #expect(result.operations.allSatisfy { $0.type == .copy })

        // Verify files were copied in both directions
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("left_only.txt")))
        #expect(TestHelpers.fileExists(at: leftDir.appendingPathComponent("right_only.txt")))
        #expect(
            try TestHelpers.readFile(at: rightDir.appendingPathComponent("left_only.txt"))
                == "left content")
        #expect(
            try TestHelpers.readFile(at: leftDir.appendingPathComponent("right_only.txt"))
                == "right content")
    }

    @Test("Two-way sync: no deletions in two-way mode")
    func twoWaySyncNoDeleteions() async throws {
        let leftFiles = [
            "left.txt": "left"
        ]
        let rightFiles = [
            "right.txt": "right"
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .twoWay(conflictResolution: .keepNewest)
        )

        // Should have no delete operations in two-way sync
        let deleteOps = result.operations.filter { $0.type == .delete }
        #expect(deleteOps.isEmpty)

        // Both files should exist in both directories
        #expect(TestHelpers.fileExists(at: leftDir.appendingPathComponent("left.txt")))
        #expect(TestHelpers.fileExists(at: leftDir.appendingPathComponent("right.txt")))
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("left.txt")))
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("right.txt")))
    }

    // MARK: - Conflict Resolution Tests

    @Test("Conflict resolution: keep newest")
    func conflictResolutionKeepNewest() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [:])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let now = Date()
        let older = now.addingTimeInterval(-3600)  // 1 hour ago
        let newer = now

        // Create left file (older)
        try TestHelpers.createFile(
            at: leftDir.appendingPathComponent("file.txt"),
            content: "left content",
            modificationDate: older
        )

        // Create right file (newer)
        try TestHelpers.createFile(
            at: rightDir.appendingPathComponent("file.txt"),
            content: "right content",
            modificationDate: newer
        )

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .twoWay(conflictResolution: .keepNewest)
        )

        #expect(result.succeeded == 1)

        // Both should have the newer content (from right)
        #expect(
            try TestHelpers.readFile(at: leftDir.appendingPathComponent("file.txt"))
                == "right content")
        #expect(
            try TestHelpers.readFile(at: rightDir.appendingPathComponent("file.txt"))
                == "right content")
    }

    @Test("Conflict resolution: keep left")
    func conflictResolutionKeepSource() async throws {
        let leftFiles = [
            "conflict.txt": "left version"
        ]
        let rightFiles = [
            "conflict.txt": "right version"
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .twoWay(conflictResolution: .keepLeft)
        )

        #expect(result.succeeded == 1)

        // Both should have left content
        #expect(
            try TestHelpers.readFile(at: leftDir.appendingPathComponent("conflict.txt"))
                == "left version")
        #expect(
            try TestHelpers.readFile(at: rightDir.appendingPathComponent("conflict.txt"))
                == "left version")
    }

    @Test("Conflict resolution: keep right")
    func conflictResolutionKeepDestination() async throws {
        let leftFiles = [
            "conflict.txt": "left version"
        ]
        let rightFiles = [
            "conflict.txt": "right version"
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .twoWay(conflictResolution: .keepRight)
        )

        #expect(result.succeeded == 1)

        // Both should have right content
        #expect(
            try TestHelpers.readFile(at: leftDir.appendingPathComponent("conflict.txt"))
                == "right version")
        #expect(
            try TestHelpers.readFile(at: rightDir.appendingPathComponent("conflict.txt"))
                == "right version")
    }

    @Test("Conflict resolution: skip")
    func conflictResolutionSkip() async throws {
        let leftFiles = [
            "conflict.txt": "left version"
        ]
        let rightFiles = [
            "conflict.txt": "right version"
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .twoWay(conflictResolution: .skip)
        )

        // Should have no operations for the conflicting file
        #expect(result.operations.isEmpty)

        // Both should keep their original content
        #expect(
            try TestHelpers.readFile(at: leftDir.appendingPathComponent("conflict.txt"))
                == "left version")
        #expect(
            try TestHelpers.readFile(at: rightDir.appendingPathComponent("conflict.txt"))
                == "right version")
    }

    @Test("Conflict resolution: multiple conflicts with skip")
    func conflictResolutionMultipleSkip() async throws {
        let leftFiles = [
            "conflict1.txt": "left1",
            "conflict2.txt": "left2",
            "unique.txt": "unique",
        ]
        let rightFiles = [
            "conflict1.txt": "right1",
            "conflict2.txt": "right2",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .twoWay(conflictResolution: .skip)
        )

        // Should only copy the unique file
        #expect(result.operations.count == 1)
        #expect(result.operations.first?.relativePath == "unique.txt")
        #expect(result.operations.first?.type == .copy)
    }

    // MARK: - Dry-Run Tests

    @Test("Dry-run mode: no actual changes made")
    func dryRunNoChanges() async throws {
        let leftFiles = [
            "file1.txt": "content1",
            "file2.txt": "content2",
        ]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay,
            dryRun: true
        )

        // Operations should be planned
        #expect(result.operations.count == 2)
        #expect(result.skipped == 2)
        #expect(result.succeeded == 0)
        #expect(result.failed == 0)

        // But no actual changes made
        #expect(!TestHelpers.fileExists(at: rightDir.appendingPathComponent("file1.txt")))
        #expect(!TestHelpers.fileExists(at: rightDir.appendingPathComponent("file2.txt")))
    }

    @Test("Dry-run mode: operations correctly planned")
    func dryRunOperationsPlanned() async throws {
        let leftFiles = [
            "copy.txt": "copy me",
            "update.txt": "new version",
        ]
        let rightFiles = [
            "update.txt": "old version",
            "delete.txt": "delete me",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay,
            deletions: true,
            dryRun: true
        )

        #expect(result.operations.count == 3)

        let copyOps = result.operations.filter { $0.type == .copy }
        let updateOps = result.operations.filter { $0.type == .update }
        let deleteOps = result.operations.filter { $0.type == .delete }

        #expect(copyOps.count == 1)
        #expect(updateOps.count == 1)
        #expect(deleteOps.count == 1)
    }

    // MARK: - Recursive Tests

    @Test("Recursive sync: syncs nested directories")
    func recursiveSyncNested() async throws {
        let leftFiles = [
            "root.txt": "root",
            "sub1/file1.txt": "sub1",
            "sub1/sub2/deep.txt": "deep",
        ]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay,
            recursive: true
        )

        #expect(result.succeeded == 3)
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("root.txt")))
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("sub1/file1.txt")))
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("sub1/sub2/deep.txt")))
    }

    @Test("Non-recursive sync: only syncs root level")
    func nonRecursiveSyncRootOnly() async throws {
        let leftFiles = [
            "root.txt": "root",
            "subdir/nested.txt": "nested",
        ]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay,
            recursive: false
        )

        #expect(result.succeeded == 1)
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("root.txt")))
        #expect(!TestHelpers.fileExists(at: rightDir.appendingPathComponent("subdir/nested.txt")))
    }

    // MARK: - Error Handling Tests

    @Test("Invalid left directory throws error")
    func invalidSourceDirectory() async throws {
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        await #expect(throws: DirectorySyncError.self) {
            _ = try await directorySync(
                left: "/nonexistent/left/12345",
                right: rightDir.path(percentEncoded: false),
                mode: .oneWay
            )
        }
    }

    @Test("Invalid right directory throws error")
    func invalidDestinationDirectory() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
        }

        await #expect(throws: DirectorySyncError.self) {
            _ = try await directorySync(
                left: leftDir.path(percentEncoded: false),
                right: "/nonexistent/right/12345",
                mode: .oneWay
            )
        }
    }

    // MARK: - Edge Cases

    @Test("Sync identical directories: no operations needed")
    func syncIdenticalDirectories() async throws {
        let files = [
            "file1.txt": "content1",
            "file2.txt": "content2",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: files)
        let rightDir = try TestHelpers.createTestDirectory(files: files)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay
        )

        #expect(result.operations.isEmpty)
        #expect(result.succeeded == 0)
    }

    @Test("Sync empty directories")
    func syncEmptyDirectories() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [:])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay
        )

        #expect(result.operations.isEmpty)
        #expect(result.succeeded == 0)
    }

    @Test("Sync creates intermediate directories")
    func syncCreatesIntermediateDirectories() async throws {
        let leftFiles = [
            "a/b/c/deep.txt": "deep content"
        ]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay
        )

        #expect(result.succeeded == 1)
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("a/b/c/deep.txt")))
        #expect(
            try TestHelpers.readFile(at: rightDir.appendingPathComponent("a/b/c/deep.txt"))
                == "deep content")
    }

    @Test("Sync handles empty files")
    func syncHandlesEmptyFiles() async throws {
        let leftFiles = [
            "empty.txt": ""
        ]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay
        )

        #expect(result.succeeded == 1)
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("empty.txt")))
        #expect(try TestHelpers.readFile(at: rightDir.appendingPathComponent("empty.txt")) == "")
    }

    @Test(".filesignore is not copied during sync")
    func filesignoreNotCopied() async throws {
        let leftFiles = [
            ".filesignore": "*.log\n*.tmp",
            "data.txt": "important data",
            "config.json": "{}",
        ]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        // Create isolated ignore patterns (don't load from home directory)
        let ignore = Ignore(patterns: ["*.log", "*.tmp"])

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay,
            ignore: ignore
        )

        // Should copy 2 files (data.txt and config.json), but NOT .filesignore
        #expect(result.succeeded == 2)
        #expect(result.operations.count == 2)

        // Verify .filesignore was NOT copied
        let filesignorePath = rightDir.appendingPathComponent(".filesignore")
        #expect(!TestHelpers.fileExists(at: filesignorePath))

        // Verify other files were copied
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("data.txt")))
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("config.json")))
    }

    @Test(".filesignore can be explicitly included with negation pattern")
    func filesignoreCanBeIncludedExplicitly() async throws {
        let leftFiles = [
            ".filesignore": "*.log\n!.filesignore",
            "data.txt": "important data",
        ]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = try await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay
        )

        // With !.filesignore in the patterns, it should be included
        // Should copy both files
        #expect(result.succeeded == 2)
        #expect(result.operations.count == 2)

        // Verify .filesignore WAS copied this time
        let filesignorePath = rightDir.appendingPathComponent(".filesignore")
        #expect(TestHelpers.fileExists(at: filesignorePath))
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("data.txt")))
    }
}
