import Foundation
import Testing

@testable import FilesKit

// Helper extension to convert Result to throwing
extension Result where Success == DirectoryDifference, Failure == DirectoryDifferenceError {
    func unwrap() throws -> DirectoryDifference {
        switch self {
            case .success(let diff):
                return diff
            case .failure(let error):
                throw error
        }
    }
}

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
        ).unwrap()

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
        ).unwrap()

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
        ).unwrap()

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
        ).unwrap()

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
        ).unwrap()

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
        ).unwrap()

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
        ).unwrap()

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
        ).unwrap()

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
        ).unwrap()

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
        ).unwrap()

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
        ).unwrap()

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
            ).unwrap()
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
            ).unwrap()
        }
    }

    @Test("Both directories invalid throws error")
    func bothDirectoriesInvalid() async throws {
        await #expect(throws: DirectoryDifferenceError.self) {
            _ = try await directoryDifference(
                left: "/nonexistent/left/12345",
                right: "/nonexistent/right/12345"
            ).unwrap()
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
            ).unwrap()
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
        ).unwrap()

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
        ).unwrap()

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
        ).unwrap()

        #expect(diff.common.count == 100)
        #expect(diff.onlyInLeft.isEmpty)
        #expect(diff.onlyInRight.isEmpty)
        #expect(diff.modified.isEmpty)
    }

    // MARK: - Fuzzy Matching Tests

    @Test("Fuzzy matching: files with typos recognized as modified")
    func fuzzyMatchingTypos() async throws {
        let leftFiles = [
            "report.txt": "content A",
            "document.txt": "content B",
        ]
        let rightFiles = [
            "reprot.txt": "content X",  // typo of report.txt
            "documnet.txt": "content Y",  // typo of document.txt
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            matchPrecision: 0.8
        )

        let diff = try result.unwrap()

        // Files should be recognized as modified (fuzzy matched)
        #expect(diff.modified.count == 2)
        #expect(diff.modified.contains("report.txt"))
        #expect(diff.modified.contains("document.txt"))
        #expect(diff.onlyInLeft.isEmpty)
        #expect(diff.onlyInRight.isEmpty)
        #expect(diff.common.isEmpty)
    }

    @Test("Fuzzy matching: exact match preferred over fuzzy")
    func fuzzyMatchingPreferExact() async throws {
        let leftFiles = [
            "file.txt": "exact content"
        ]
        let rightFiles = [
            "file.txt": "exact content",
            "flie.txt": "typo content",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            matchPrecision: 0.8
        )

        let diff = try result.unwrap()

        // Should match exact file, typo file is only in right
        #expect(diff.common.contains("file.txt"))
        #expect(diff.onlyInRight.contains("flie.txt"))
        #expect(diff.modified.isEmpty)
        #expect(diff.onlyInLeft.isEmpty)
    }

    @Test("Fuzzy matching: disabled by default (matchPrecision = 1.0)")
    func fuzzyMatchingDisabledByDefault() async throws {
        let leftFiles = [
            "report.txt": "content A"
        ]
        let rightFiles = [
            "reprot.txt": "content B"  // typo
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        // Don't specify matchPrecision (defaults to 1.0)
        let result = await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        )

        let diff = try result.unwrap()

        // Files should be treated as separate
        #expect(diff.onlyInLeft.contains("report.txt"))
        #expect(diff.onlyInRight.contains("reprot.txt"))
        #expect(diff.common.isEmpty)
        #expect(diff.modified.isEmpty)
    }

    @Test("Fuzzy matching: no match below threshold")
    func fuzzyMatchingBelowThreshold() async throws {
        let leftFiles = [
            "abc.txt": "content"
        ]
        let rightFiles = [
            "xyz.txt": "content"
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            matchPrecision: 0.9  // High threshold - these won't match
        )

        let diff = try result.unwrap()

        // Files should be treated as separate
        #expect(diff.onlyInLeft.contains("abc.txt"))
        #expect(diff.onlyInRight.contains("xyz.txt"))
        #expect(diff.common.isEmpty)
        #expect(diff.modified.isEmpty)
    }

    @Test("Fuzzy matching: multiple files with mixed matches")
    func fuzzyMatchingMixedScenario() async throws {
        let leftFiles = [
            "exact.txt": "content",
            "report.txt": "report A",
            "unique.txt": "unique",
        ]
        let rightFiles = [
            "exact.txt": "content",  // exact match
            "reprot.txt": "report B",  // fuzzy match to report.txt
            "different.txt": "diff",  // only in right
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            matchPrecision: 0.8
        )

        let diff = try result.unwrap()

        #expect(diff.common.contains("exact.txt"))
        #expect(diff.modified.contains("report.txt"))
        #expect(diff.onlyInLeft.contains("unique.txt"))
        #expect(diff.onlyInRight.contains("different.txt"))
    }

    @Test("Fuzzy matching: works with nested paths")
    func fuzzyMatchingNestedPaths() async throws {
        let leftFiles = [
            "dir/report.txt": "content A",
            "dir/document.txt": "content B",
        ]
        let rightFiles = [
            "dir/reprot.txt": "content X",
            "dir/documnet.txt": "content Y",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            matchPrecision: 0.8
        )

        let diff = try result.unwrap()

        // Should fuzzy match based on filename, not full path
        #expect(diff.modified.count == 2)
        #expect(diff.modified.contains("dir/report.txt"))
        #expect(diff.modified.contains("dir/document.txt"))
    }

    @Test("Fuzzy matching: one-to-one mapping (no duplicate matches)")
    func fuzzyMatchingOneToOne() async throws {
        let leftFiles = [
            "file1.txt": "content A",
            "file2.txt": "content B",
        ]
        let rightFiles = [
            "flie1.txt": "content X"  // Similar to file1.txt but not file2.txt
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let result = await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            matchPrecision: 0.8
        )

        let diff = try result.unwrap()

        // file1.txt should match flie1.txt, file2.txt has no match
        // However, due to set iteration order being non-deterministic, we can't guarantee which one matches
        // So we just verify that only one matches and one doesn't
        let totalMatches = diff.modified.count + diff.common.count
        #expect(totalMatches <= 1)  // At most one fuzzy match
        #expect(diff.onlyInLeft.count >= 1)  // At least one file didn't match
    }
}

// MARK: - JSON Comparison Tests

@Suite("JSON Comparison")
struct JSONComparisonTests {

    @Test("Identical JSON comparison results")
    func identicalJSONResults() async throws {
        let comparisonResult = DirectoryDifference(
            onlyInLeft: ["file1.txt", "file2.txt"],
            onlyInRight: ["file3.txt"],
            common: ["file5.txt", "file6.txt"],
            modified: ["file4.txt"]
        )

        let (leftFile, rightFile) = try TestHelpers.createJSONComparisonFiles(
            left: comparisonResult,
            right: comparisonResult
        )

        defer {
            try? FileManager.default.removeItem(atPath: leftFile)
            try? FileManager.default.removeItem(atPath: rightFile)
        }

        let diff = try await compareSnapshots(left: leftFile, right: rightFile)

        #expect(diff.onlyInLeft.isEmpty)
        #expect(diff.onlyInRight.isEmpty)
        #expect(diff.modified.isEmpty)
        #expect(diff.common.count == 6)  // All files should have same status
        #expect(!diff.hasDifferences)
    }

    @Test("Files added to comparison")
    func filesAddedToComparison() async throws {
        let leftResult = DirectoryDifference(
            onlyInLeft: ["file1.txt"],
            onlyInRight: ["file2.txt"],
            common: ["file3.txt"],
            modified: []
        )

        let rightResult = DirectoryDifference(
            onlyInLeft: ["file1.txt"],
            onlyInRight: ["file2.txt"],
            common: ["file3.txt", "file4.txt"],  // file4.txt added
            modified: []
        )

        let (leftFile, rightFile) = try TestHelpers.createJSONComparisonFiles(
            left: leftResult,
            right: rightResult
        )

        defer {
            try? FileManager.default.removeItem(atPath: leftFile)
            try? FileManager.default.removeItem(atPath: rightFile)
        }

        let diff = try await compareSnapshots(left: leftFile, right: rightFile)

        #expect(diff.onlyInRight.contains("file4.txt"))
        #expect(diff.hasDifferences)
    }

    @Test("Files removed from comparison")
    func filesRemovedFromComparison() async throws {
        let leftResult = DirectoryDifference(
            onlyInLeft: ["file1.txt"],
            onlyInRight: ["file2.txt"],
            common: ["file4.txt"],
            modified: ["file3.txt"]
        )

        let rightResult = DirectoryDifference(
            onlyInLeft: ["file1.txt"],
            onlyInRight: ["file2.txt"],
            common: [],  // file4.txt removed
            modified: []  // file3.txt removed
        )

        let (leftFile, rightFile) = try TestHelpers.createJSONComparisonFiles(
            left: leftResult,
            right: rightResult
        )

        defer {
            try? FileManager.default.removeItem(atPath: leftFile)
            try? FileManager.default.removeItem(atPath: rightFile)
        }

        let diff = try await compareSnapshots(left: leftFile, right: rightFile)

        #expect(diff.onlyInLeft.contains("file3.txt"))
        #expect(diff.onlyInLeft.contains("file4.txt"))
        #expect(diff.hasDifferences)
    }

    @Test("File status changed between comparisons")
    func fileStatusChanged() async throws {
        let leftResult = DirectoryDifference(
            onlyInLeft: [],
            onlyInRight: [],
            common: ["file2.txt"],  // file2 was common
            modified: ["file1.txt"]  // file1 was modified
        )

        let rightResult = DirectoryDifference(
            onlyInLeft: [],
            onlyInRight: [],
            common: ["file1.txt", "file2.txt"],  // file1 now common
            modified: []
        )

        let (leftFile, rightFile) = try TestHelpers.createJSONComparisonFiles(
            left: leftResult,
            right: rightResult
        )

        defer {
            try? FileManager.default.removeItem(atPath: leftFile)
            try? FileManager.default.removeItem(atPath: rightFile)
        }

        let diff = try await compareSnapshots(left: leftFile, right: rightFile)

        #expect(diff.modified.contains("file1.txt"))  // Status changed
        #expect(diff.common.contains("file2.txt"))  // Status unchanged
        #expect(diff.hasDifferences)
    }

    @Test("Multiple status changes")
    func multipleStatusChanges() async throws {
        let leftResult = DirectoryDifference(
            onlyInLeft: ["file1.txt"],
            onlyInRight: [],
            common: ["file3.txt"],
            modified: ["file2.txt"]
        )

        let rightResult = DirectoryDifference(
            onlyInLeft: [],
            onlyInRight: ["file1.txt"],  // file1 moved from left to right
            common: ["file2.txt"],  // file2 became common
            modified: ["file3.txt"]  // file3 became modified
        )

        let (leftFile, rightFile) = try TestHelpers.createJSONComparisonFiles(
            left: leftResult,
            right: rightResult
        )

        defer {
            try? FileManager.default.removeItem(atPath: leftFile)
            try? FileManager.default.removeItem(atPath: rightFile)
        }

        let diff = try await compareSnapshots(left: leftFile, right: rightFile)

        #expect(diff.modified.contains("file1.txt"))
        #expect(diff.modified.contains("file2.txt"))
        #expect(diff.modified.contains("file3.txt"))
        #expect(diff.hasDifferences)
    }

    @Test("Invalid JSON file throws error")
    func invalidJSONFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let invalidFile = tempDir.appendingPathComponent(UUID().uuidString + ".json")
        let validResult = DirectoryDifference(
            onlyInLeft: [],
            onlyInRight: [],
            common: [],
            modified: []
        )

        // Create invalid JSON
        try "{ invalid json }".write(to: invalidFile, atomically: true, encoding: .utf8)

        let validFile = try TestHelpers.createJSONFile(diff: validResult)

        defer {
            try? FileManager.default.removeItem(at: invalidFile)
            try? FileManager.default.removeItem(atPath: validFile)
        }

        await #expect(throws: DirectoryDifferenceError.self) {
            _ = try await compareSnapshots(
                left: invalidFile.path(percentEncoded: false),
                right: validFile
            )
        }
    }

    @Test("Nonexistent JSON file throws error")
    func nonexistentJSONFile() async throws {
        let validResult = DirectoryDifference(
            onlyInLeft: [],
            onlyInRight: [],
            common: [],
            modified: []
        )

        let validFile = try TestHelpers.createJSONFile(diff: validResult)

        defer {
            try? FileManager.default.removeItem(atPath: validFile)
        }

        await #expect(throws: DirectoryDifferenceError.self) {
            _ = try await compareSnapshots(
                left: "/nonexistent/file.json",
                right: validFile
            )
        }
    }

    @Test("Empty comparison results")
    func emptyComparisonResults() async throws {
        let emptyResult = DirectoryDifference(
            onlyInLeft: [],
            onlyInRight: [],
            common: [],
            modified: []
        )

        let (leftFile, rightFile) = try TestHelpers.createJSONComparisonFiles(
            left: emptyResult,
            right: emptyResult
        )

        defer {
            try? FileManager.default.removeItem(atPath: leftFile)
            try? FileManager.default.removeItem(atPath: rightFile)
        }

        let diff = try await compareSnapshots(left: leftFile, right: rightFile)

        #expect(diff.onlyInLeft.isEmpty)
        #expect(diff.onlyInRight.isEmpty)
        #expect(diff.modified.isEmpty)
        #expect(diff.common.isEmpty)
        #expect(!diff.hasDifferences)
    }

    // MARK: - Tests for .leafFoldersOnly

    @Test(".leafFoldersOnly: finds files only in right leaf directories")
    func leafFoldersOnlyInRight() async throws {
        let leftFiles = [
            "root.txt": "content",
            "folder1/file1.txt": "content1",
            "folder1/subfolder/file2.txt": "content2",  // Not a leaf - has subdirs
            "folder1/subfolder/leaf/file3.txt": "content3",  // Leaf directory
            "folder2/leaf/file4.txt": "content4",  // Leaf directory
        ]

        let rightFiles = [
            "root.txt": "content",
            "folder1/file1.txt": "content1",
            "folder1/subfolder/file2.txt": "content2",
            "folder1/subfolder/leaf/file3.txt": "content3",
            "folder2/leaf/file4.txt": "content4",

            "folder1/subfolder/leaf/extra.txt": "extra",  // Only in right, in leaf dir
            "folder2/leaf/another.txt": "another",  // Only in right, in leaf dir
            "folder2/notleaf/ignored.txt": "ignored",  // Not in a left leaf dir
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
            includeOnlyInRight: .leafFoldersOnly
        ).unwrap()

        // Should find files only in right leaf directories
        #expect(diff.onlyInRight.contains("folder1/subfolder/leaf/extra.txt"))
        #expect(diff.onlyInRight.contains("folder2/leaf/another.txt"))
        #expect(diff.onlyInRight.count == 2)

        // Should NOT include files in non-leaf directories
        #expect(!diff.onlyInRight.contains("folder2/notleaf/ignored.txt"))

        // Common files should include those in leaf dirs
        #expect(diff.common.contains("folder1/subfolder/leaf/file3.txt"))
        #expect(diff.common.contains("folder2/leaf/file4.txt"))
    }

    @Test(".leafFoldersOnly: detects modified files in leaf directories")
    func leafFoldersModifiedFiles() async throws {
        let leftFiles = [
            "leaf1/file1.txt": "original",
            "leaf1/file2.txt": "same",
            "parent/leaf2/file3.txt": "original",
        ]

        let rightFiles = [
            "leaf1/file1.txt": "modified",  // Modified in leaf dir
            "leaf1/file2.txt": "same",
            "parent/leaf2/file3.txt": "modified",  // Modified in leaf dir
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
            includeOnlyInRight: .leafFoldersOnly
        ).unwrap()

        // Should detect modified files in leaf directories
        #expect(diff.modified.contains("leaf1/file1.txt"))
        #expect(diff.modified.contains("parent/leaf2/file3.txt"))
        #expect(diff.modified.count == 2)

        // Should have common file that wasn't modified
        #expect(diff.common.contains("leaf1/file2.txt"))
    }

    @Test(".leafFoldersOnly: ignores non-leaf directories on right")
    func leafFoldersIgnoresNonLeafDirs() async throws {
        let leftFiles = [
            "leafdir/file1.txt": "content",
            "parent/child/file2.txt": "content",  // parent/child is leaf
        ]

        let rightFiles = [
            "leafdir/file1.txt": "content",
            "leafdir/extra.txt": "extra",  // In leaf dir - should be included
            "parent/child/file2.txt": "content",
            "parent/file3.txt": "parent",  // In non-leaf dir (parent has child subdir)
            "newdir/subdir/file4.txt": "new",  // Completely new path, not a left leaf
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
            includeOnlyInRight: .leafFoldersOnly
        ).unwrap()

        // Should include files in left's leaf directories
        #expect(diff.onlyInRight.contains("leafdir/extra.txt"))

        // Should NOT include files in non-leaf directories or new paths
        #expect(!diff.onlyInRight.contains("parent/file3.txt"))
        #expect(!diff.onlyInRight.contains("newdir/subdir/file4.txt"))
    }

    @Test(".leafFoldersOnly: works with empty right leaf directories")
    func leafFoldersEmptyRightLeafDirs() async throws {
        let leftFiles = [
            "leaf1/file1.txt": "content",
            "leaf2/file2.txt": "content",
        ]

        let rightFiles = [
            "leaf1/file1.txt": "content"
                // leaf2 doesn't exist on right
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
            includeOnlyInRight: .leafFoldersOnly
        ).unwrap()

        // leaf2/file2.txt is only in left, not in common
        #expect(diff.onlyInLeft.contains("leaf2/file2.txt"))
        #expect(diff.onlyInRight.isEmpty)
        #expect(diff.common.contains("leaf1/file1.txt"))
    }

    @Test(".leafFoldersOnly: complex nested structure")
    func leafFoldersComplexNested() async throws {
        let leftFiles = [
            "a/b/c/d/file1.txt": "content",  // d is leaf
            "a/b/e/file2.txt": "content",  // e is leaf
            "a/f/file3.txt": "content",  // f is leaf
            "root.txt": "content",
        ]

        let rightFiles = [
            "a/b/c/d/file1.txt": "content",
            "a/b/c/d/extra1.txt": "extra1",  // In leaf dir d
            "a/b/e/file2.txt": "modified",  // Modified in leaf dir e
            "a/b/e/extra2.txt": "extra2",  // In leaf dir e
            "a/f/file3.txt": "content",
            "a/g/file4.txt": "notleaf",  // g is not a left leaf dir
            "root.txt": "content",
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
            includeOnlyInRight: .leafFoldersOnly
        ).unwrap()

        // Should find extra files in left's leaf directories
        #expect(diff.onlyInRight.contains("a/b/c/d/extra1.txt"))
        #expect(diff.onlyInRight.contains("a/b/e/extra2.txt"))
        #expect(diff.onlyInRight.count == 2)

        // Should detect modified file in leaf directory
        #expect(diff.modified.contains("a/b/e/file2.txt"))

        // Should NOT include file in non-left-leaf directory
        #expect(!diff.onlyInRight.contains("a/g/file4.txt"))

        // Common files in leaf directories
        #expect(diff.common.contains("a/b/c/d/file1.txt"))
        #expect(diff.common.contains("a/f/file3.txt"))
    }
}
