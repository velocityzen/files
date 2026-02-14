import Foundation
import Testing

@testable import FilesKit

@Suite("Config")
struct ConfigTests {
    @Test("Empty config has all nil values")
    func emptyConfig() {
        let config = Config()
        #expect(config.matchPrecision == nil)
        #expect(config.sizeTolerance == nil)
        #expect(config.recursive == nil)
        #expect(config.deletions == nil)
        #expect(config.showMoreRight == nil)
        #expect(config.dryRun == nil)
        #expect(config.verbose == nil)
        #expect(config.format == nil)
        #expect(config.twoWay == nil)
        #expect(config.conflictResolution == nil)
        #expect(config.noIgnore == nil)
    }

    @Test("Load config from left directory")
    func loadFromLeftDirectory() async throws {
        let leftFiles = [
            ".files": "matchPrecision = 0.8\nsizeTolerance = 0.2\n",
            "file.txt": "content",
        ]
        let rightFiles = ["file.txt": "content"]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let config = await Config.load(
            leftPath: leftDir.path(percentEncoded: false),
            rightPath: rightDir.path(percentEncoded: false)
        )

        #expect(config.matchPrecision == 0.8)
        #expect(config.sizeTolerance == 0.2)
    }

    @Test("Load config from right directory")
    func loadFromRightDirectory() async throws {
        let leftFiles = ["file.txt": "content"]
        let rightFiles = [
            ".files": "recursive = false\ndeletions = true\n",
            "file.txt": "content",
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let config = await Config.load(
            leftPath: leftDir.path(percentEncoded: false),
            rightPath: rightDir.path(percentEncoded: false)
        )

        #expect(config.recursive == false)
        #expect(config.deletions == true)
    }

    @Test("Right directory config overrides left")
    func rightOverridesLeft() async throws {
        let leftFiles = [
            ".files": "matchPrecision = 0.8\nsizeTolerance = 0.1\n"
        ]
        let rightFiles = [
            ".files": "matchPrecision = 0.9\n"
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let config = await Config.load(
            leftPath: leftDir.path(percentEncoded: false),
            rightPath: rightDir.path(percentEncoded: false)
        )

        #expect(config.matchPrecision == 0.9)
        #expect(config.sizeTolerance == 0.1)
    }

    @Test("All config options are parsed")
    func allOptionsAreParsed() async throws {
        let configContent = """
            matchPrecision = 0.7
            sizeTolerance = 0.3
            recursive = false
            deletions = true
            showMoreRight = true
            dryRun = true
            verbose = true
            format = json
            twoWay = true
            conflictResolution = left
            noIgnore = true
            """

        let leftFiles = [".files": configContent]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let config = await Config.load(
            leftPath: leftDir.path(percentEncoded: false),
            rightPath: rightDir.path(percentEncoded: false)
        )

        #expect(config.matchPrecision == 0.7)
        #expect(config.sizeTolerance == 0.3)
        #expect(config.recursive == false)
        #expect(config.deletions == true)
        #expect(config.showMoreRight == true)
        #expect(config.dryRun == true)
        #expect(config.verbose == true)
        #expect(config.format == "json")
        #expect(config.twoWay == true)
        #expect(config.conflictResolution == "left")
        #expect(config.noIgnore == true)
    }

    @Test("Comments and empty lines are ignored")
    func commentsAndEmptyLines() async throws {
        let configContent = """
            # This is a comment
            matchPrecision = 0.8

            # Another comment
            sizeTolerance = 0.2
            """

        let leftFiles = [".files": configContent]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let config = await Config.load(
            leftPath: leftDir.path(percentEncoded: false),
            rightPath: rightDir.path(percentEncoded: false)
        )

        #expect(config.matchPrecision == 0.8)
        #expect(config.sizeTolerance == 0.2)
    }

    @Test("Invalid values are ignored")
    func invalidValuesIgnored() async throws {
        let configContent = """
            matchPrecision = notanumber
            recursive = maybe
            unknownKey = value
            sizeTolerance = 0.5
            """

        let leftFiles = [".files": configContent]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let config = await Config.load(
            leftPath: leftDir.path(percentEncoded: false),
            rightPath: rightDir.path(percentEncoded: false)
        )

        #expect(config.matchPrecision == nil)
        #expect(config.recursive == nil)
        #expect(config.sizeTolerance == 0.5)
    }

    @Test("No .files files returns empty config")
    func noConfigFiles() async throws {
        let leftFiles = ["file.txt": "content"]
        let rightFiles = ["file.txt": "content"]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let config = await Config.load(
            leftPath: leftDir.path(percentEncoded: false),
            rightPath: rightDir.path(percentEncoded: false)
        )

        #expect(config.matchPrecision == nil)
        #expect(config.sizeTolerance == nil)
        #expect(config.recursive == nil)
    }

    @Test("Merge preserves non-nil values from base")
    func mergePreservesBase() {
        var base = Config()
        base.matchPrecision = 0.8
        base.recursive = true

        let overlay = Config()

        let merged = base.merged(with: overlay)
        #expect(merged.matchPrecision == 0.8)
        #expect(merged.recursive == true)
    }

    @Test("Merge overrides with non-nil values")
    func mergeOverrides() {
        var base = Config()
        base.matchPrecision = 0.8
        base.recursive = true

        var overlay = Config()
        overlay.matchPrecision = 0.9

        let merged = base.merged(with: overlay)
        #expect(merged.matchPrecision == 0.9)
        #expect(merged.recursive == true)
    }

    @Test("Bool values accept various formats")
    func boolFormats() async throws {
        let configContent = """
            recursive = yes
            deletions = no
            showMoreRight = 1
            dryRun = 0
            verbose = true
            noIgnore = false
            """

        let leftFiles = [".files": configContent]
        let rightFiles: [String: String] = [:]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let config = await Config.load(
            leftPath: leftDir.path(percentEncoded: false),
            rightPath: rightDir.path(percentEncoded: false)
        )

        #expect(config.recursive == true)
        #expect(config.deletions == false)
        #expect(config.showMoreRight == true)
        #expect(config.dryRun == false)
        #expect(config.verbose == true)
        #expect(config.noIgnore == false)
    }

    @Test(".files is not copied during sync")
    func filesConfigNotCopied() async throws {
        let leftFiles = [
            ".files": "matchPrecision = 0.8\n",
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

        let ignore = Ignore(patterns: [])

        let stream = await directorySync(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            mode: .oneWay,
            ignore: ignore
        )
        var results: [OperationResult] = []
        for await opResult in stream {
            results.append(opResult)
        }

        #expect(results.succeeded == 2)
        #expect(results.operations.count == 2)

        let filesConfigPath = rightDir.appendingPathComponent(".files")
        #expect(!TestHelpers.fileExists(at: filesConfigPath))

        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("data.txt")))
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("config.json")))
    }

    @Test("Config values applied in directory comparison")
    func configAppliedInComparison() async throws {
        let leftFiles = [
            ".files": "matchPrecision = 0.8\nsizeTolerance = 0.3\n",
            "report.txt": String(repeating: "a", count: 100),
        ]
        let rightFiles = [
            "reprot.txt": String(repeating: "b", count: 120)
        ]

        let leftDir = try TestHelpers.createTestDirectory(files: leftFiles)
        let rightDir = try TestHelpers.createTestDirectory(files: rightFiles)

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        // Without config (exact matching) — files are unrelated
        let diffExact = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false)
        ).unwrap()

        #expect(diffExact.onlyInLeft.contains("report.txt"))
        #expect(diffExact.onlyInRight.contains("reprot.txt"))

        // With config values — fuzzy match + size tolerance → common
        let diffFuzzy = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            matchPrecision: 0.8,
            sizeTolerance: 0.3
        ).unwrap()

        #expect(diffFuzzy.common.contains("report.txt"))
        #expect(diffFuzzy.onlyInLeft.isEmpty)
    }
}
