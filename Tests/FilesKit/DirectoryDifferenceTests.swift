import Foundation
import Testing

@testable import FilesKit

/// Test suite for directory difference functionality
@Suite("DirectoryDifference")
struct DirectoryDifferenceTests {

    // MARK: - Tests for Identical Directories

    @Test("Identical empty directories")
    func identicalEmptyDirectories() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [:])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        )

        #expect(diff.onlyInLeft.isEmpty)
        #expect(diff.onlyInRight.isEmpty)
        #expect(diff.modified.isEmpty)
        #expect(diff.common.isEmpty)
    }

    @Test("Identical directories with same files")
    func identicalDirectoriesWithFiles() async throws {
        let files = [
            "file1.txt": "content1",
            "file2.txt": "content2",
            "file3.txt": "content3",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: files)
        let rightDir = try TestHelpers.createTestDirectory(files: files)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        )

        #expect(diff.onlyInLeft.isEmpty)
        #expect(diff.onlyInRight.isEmpty)
        #expect(diff.modified.isEmpty)
        #expect(diff.common.count == 3)
        #expect(diff.common.contains("file1.txt"))
        #expect(diff.common.contains("file2.txt"))
        #expect(diff.common.contains("file3.txt"))
    }

    // MARK: - Tests for Files Only in One Directory

    @Test("Files only in left directory")
    func filesOnlyInLeft() async throws {
        let leftFiles = [
            "left1.txt": "content",
            "left2.txt": "content",
        ]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        )

        #expect(diff.onlyInLeft.count == 2)
        #expect(diff.onlyInLeft.contains("left1.txt"))
        #expect(diff.onlyInLeft.contains("left2.txt"))
        #expect(diff.onlyInRight.isEmpty)
        #expect(diff.modified.isEmpty)
        #expect(diff.common.isEmpty)
    }

    @Test("Files only in right directory")
    func filesOnlyInRight() async throws {
        let leftFiles: [String: String] = [:]
        let rightFiles = [
            "right1.txt": "content",
            "right2.txt": "content",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        )

        #expect(diff.onlyInLeft.isEmpty)
        #expect(diff.onlyInRight.count == 2)
        #expect(diff.onlyInRight.contains("right1.txt"))
        #expect(diff.onlyInRight.contains("right2.txt"))
        #expect(diff.modified.isEmpty)
        #expect(diff.common.isEmpty)
    }

    @Test("Mixed files in both directories")
    func mixedFiles() async throws {
        let leftFiles = [
            "common.txt": "same content",
            "left_only.txt": "left content",
        ]
        let rightFiles = [
            "common.txt": "same content",
            "right_only.txt": "right content",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        )

        #expect(diff.onlyInLeft.count == 1)
        #expect(diff.onlyInLeft.contains("left_only.txt"))
        #expect(diff.onlyInRight.count == 1)
        #expect(diff.onlyInRight.contains("right_only.txt"))
        #expect(diff.modified.isEmpty)
        #expect(diff.common.count == 1)
        #expect(diff.common.contains("common.txt"))
    }

    // MARK: - Tests for Modified Files

    @Test("Modified files with different content")
    func modifiedFilesDifferentContent() async throws {
        let leftFiles = [
            "modified.txt": "version 1"
        ]
        let rightFiles = [
            "modified.txt": "version 2"
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        )

        #expect(diff.onlyInLeft.isEmpty)
        #expect(diff.onlyInRight.isEmpty)
        #expect(diff.modified.count == 1)
        #expect(diff.modified.contains("modified.txt"))
        #expect(diff.common.isEmpty)
    }

    @Test("Multiple modified files")
    func multipleModifiedFiles() async throws {
        let leftFiles = [
            "file1.txt": "left version 1",
            "file2.txt": "left version 2",
            "same.txt": "identical",
        ]
        let rightFiles = [
            "file1.txt": "right version 1",
            "file2.txt": "right version 2",
            "same.txt": "identical",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        )

        #expect(diff.onlyInLeft.isEmpty)
        #expect(diff.onlyInRight.isEmpty)
        #expect(diff.modified.count == 2)
        #expect(diff.modified.contains("file1.txt"))
        #expect(diff.modified.contains("file2.txt"))
        #expect(diff.common.count == 1)
        #expect(diff.common.contains("same.txt"))
    }

    @Test("Modified files detected by size difference")
    func modifiedFilesDetectedBySize() async throws {
        let leftFiles = [
            "file.txt": "short"
        ]
        let rightFiles = [
            "file.txt": "much longer content here"
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        )

        #expect(diff.modified.count == 1)
        #expect(diff.modified.contains("file.txt"))
    }

    // MARK: - Tests for Recursive vs Non-Recursive

    @Test("Recursive scan finds subdirectory files")
    func recursiveScan() async throws {
        let leftFiles = [
            "root.txt": "content",
            "subdir/nested.txt": "nested content",
        ]
        let rightFiles = [
            "root.txt": "content",
            "subdir/nested.txt": "nested content",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            recursive: true
        )

        #expect(diff.common.count == 2)
        #expect(diff.common.contains("root.txt"))
        #expect(diff.common.contains("subdir/nested.txt"))
    }

    @Test("Non-recursive scan ignores subdirectories")
    func nonRecursiveScan() async throws {
        let leftFiles = [
            "root.txt": "content",
            "subdir/nested.txt": "nested content",
        ]
        let rightFiles = [
            "root.txt": "content",
            "subdir/nested.txt": "nested content",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            recursive: false
        )

        #expect(diff.common.count == 1)
        #expect(diff.common.contains("root.txt"))
        #expect(!diff.common.contains("subdir/nested.txt"))
    }

    @Test("Deep nested directory structure")
    func deepNestedStructure() async throws {
        let leftFiles = [
            "a/b/c/d/deep.txt": "deep content"
        ]
        let rightFiles = [
            "a/b/c/d/deep.txt": "deep content"
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            recursive: true
        )

        #expect(diff.common.count == 1)
        #expect(diff.common.contains("a/b/c/d/deep.txt"))
    }

    // MARK: - Tests for Error Handling

    @Test("Invalid left directory throws error")
    func invalidLeftDirectory() async throws {
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        await #expect(throws: DirectoryDifferenceError.self) {
            _ = try await directoryDifference(
                left: "/nonexistent/path/12345",
                right: rightDir.path(percentEncoded: false)
            )
        }
    }

    @Test("Invalid right directory throws error")
    func invalidRightDirectory() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
        }

        await #expect(throws: DirectoryDifferenceError.self) {
            _ = try await directoryDifference(
                left: leftDir.path(percentEncoded: false),
                right: "/nonexistent/path/12345"
            )
        }
    }

    @Test("Both directories invalid throws error")
    func bothDirectoriesInvalid() async throws {
        await #expect(throws: DirectoryDifferenceError.self) {
            _ = try await directoryDifference(
                left: "/nonexistent/left/12345",
                right: "/nonexistent/right/12345"
            )
        }
    }

    @Test("File path instead of directory throws error")
    func filePathInsteadOfDirectory() async throws {
        let dir = try TestHelpers.createTestDirectory(files: ["file.txt": "content"])
        let filePath = dir.appendingPathComponent("file.txt").path(percentEncoded: false)

        defer {
            try? TestHelpers.cleanupTestDirectory(dir)
        }

        await #expect(throws: DirectoryDifferenceError.self) {
            _ = try await directoryDifference(
                left: filePath,
                right: dir.path(percentEncoded: false)
            )
        }
    }

    // MARK: - Tests for Complex Scenarios

    @Test("Complete diff scenario with all difference types")
    func completeDiffScenario() async throws {
        let leftFiles = [
            "common_unchanged.txt": "same",
            "common_modified.txt": "left version",
            "left_only_1.txt": "left",
            "left_only_2.txt": "left",
            "subdir/nested_common.txt": "same",
        ]
        let rightFiles = [
            "common_unchanged.txt": "same",
            "common_modified.txt": "right version",
            "right_only_1.txt": "right",
            "right_only_2.txt": "right",
            "subdir/nested_common.txt": "same",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        )

        #expect(diff.onlyInLeft.count == 2)
        #expect(diff.onlyInLeft.contains("left_only_1.txt"))
        #expect(diff.onlyInLeft.contains("left_only_2.txt"))

        #expect(diff.onlyInRight.count == 2)
        #expect(diff.onlyInRight.contains("right_only_1.txt"))
        #expect(diff.onlyInRight.contains("right_only_2.txt"))

        #expect(diff.modified.count == 1)
        #expect(diff.modified.contains("common_modified.txt"))

        #expect(diff.common.count == 2)
        #expect(diff.common.contains("common_unchanged.txt"))
        #expect(diff.common.contains("subdir/nested_common.txt"))
    }

    @Test("Empty files are detected as identical")
    func emptyFilesIdentical() async throws {
        let leftFiles = [
            "empty.txt": ""
        ]
        let rightFiles = [
            "empty.txt": ""
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        )

        #expect(diff.common.count == 1)
        #expect(diff.common.contains("empty.txt"))
        #expect(diff.modified.isEmpty)
    }

    @Test("Large number of files")
    func largeNumberOfFiles() async throws {
        var leftFiles: [String: String] = [:]
        var rightFiles: [String: String] = [:]

        // Create 100 identical files
        for i in 0..<100 {
            leftFiles["file\(i).txt"] = "content \(i)"
            rightFiles["file\(i).txt"] = "content \(i)"
        }

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        )

        #expect(diff.common.count == 100)
        #expect(diff.onlyInLeft.isEmpty)
        #expect(diff.onlyInRight.isEmpty)
        #expect(diff.modified.isEmpty)
    }
}
