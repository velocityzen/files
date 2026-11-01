import Foundation
import Testing

@testable import FilesKit

@Suite("Fuzzy pair selection and sync")
struct FuzzyPairTests {
    // MARK: - Pair selection

    @Test("The most similar pair wins, whatever the iteration order")
    func bestPairWins() {
        // file_abcd.txt is closer to file_abc.txt than file_ab.txt is
        for _ in 0..<20 {
            let matches = findFuzzyMatches(
                leftFiles: ["file_ab.txt", "file_abcd.txt"],
                rightFiles: ["file_abc.txt"],
                threshold: 0.8
            )
            #expect(matches == ["file_abcd.txt": "file_abc.txt"])
        }
    }

    @Test("Ties prefer the same directory, then the first path")
    func tiesAreDeterministic() {
        let sameDirectory = findFuzzyMatches(
            leftFiles: ["a/report.txt"],
            rightFiles: ["b/report1.txt", "a/report1.txt"],
            threshold: 0.8
        )
        #expect(sameDirectory == ["a/report.txt": "a/report1.txt"])

        let pathOrder = findFuzzyMatches(
            leftFiles: ["doc_b.txt", "doc_a.txt"],
            rightFiles: ["doc_c.txt"],
            threshold: 0.8
        )
        #expect(pathOrder == ["doc_a.txt": "doc_c.txt"])
    }

    // MARK: - Scan settings

    @Test("One-way fuzzy copy does not match ignored destination files")
    func fuzzyRespectsIgnore() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: ["report1.txt": "same"])
        let rightDir = try TestHelpers.createTestDirectory(files: ["report2.txt": "same"])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let results = await TestHelpers.collect(
            await directorySync(
                left: leftDir.path(percentEncoded: false),
                right: rightDir.path(percentEncoded: false),
                mode: .oneWay,
                ignore: Ignore(patterns: ["report2.txt"]),
                matchPrecision: 0.8
            ))

        #expect(results.operations.map(\.relativePath) == ["report1.txt"])
        #expect(results.operations.first?.type == .copy)
        #expect(TestHelpers.fileExists(at: rightDir.appendingPathComponent("report1.txt")))
    }

    @Test("Non-recursive fuzzy copy does not match files in subdirectories")
    func fuzzyRespectsRecursive() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: ["report1.txt": "same"])
        let rightDir = try TestHelpers.createTestDirectory(files: ["sub/report2.txt": "same"])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let results = await TestHelpers.collect(
            await directorySync(
                left: leftDir.path(percentEncoded: false),
                right: rightDir.path(percentEncoded: false),
                mode: .oneWay,
                recursive: false,
                ignore: Ignore(patterns: []),
                matchPrecision: 0.8
            ))

        #expect(results.operations.map(\.relativePath) == ["report1.txt"])
        #expect(results.operations.first?.type == .copy)
    }

    // MARK: - Recorded pairs

    @Test("The difference records which right file each left file matched")
    func differenceRecordsMatches() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [
            "report.txt": "new",
            "same.txt": "same",
        ])
        let rightDir = try TestHelpers.createTestDirectory(files: [
            "reprot.txt": "old",
            "same.txt": "same",
        ])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let diff = try await directoryDifference(
            left: leftDir.path(percentEncoded: false),
            right: rightDir.path(percentEncoded: false),
            ignore: Ignore(patterns: []),
            matchPrecision: 0.8
        ).unwrap()

        #expect(diff.modified == ["report.txt"])
        #expect(diff.matches == ["report.txt": "reprot.txt"])
        #expect(diff.rightPath(for: "report.txt") == "reprot.txt")
        #expect(diff.rightPath(for: "same.txt") == "same.txt")
    }

    @Test("Snapshots keep matches, and older snapshots without them still load")
    func snapshotMatchesCoding() throws {
        let diff = DirectoryDifference(
            onlyInLeft: [], onlyInRight: [], common: [], modified: ["report.txt"],
            matches: ["report.txt": "reprot.txt"]
        )
        let decoded = try JSONDecoder().decode(
            DirectoryDifference.self, from: try JSONEncoder().encode(diff))
        #expect(decoded.matches == diff.matches)

        let older = Data(
            #"{"onlyInLeft":[],"onlyInRight":["a.txt"],"common":[],"modified":[]}"#.utf8)
        let decodedOlder = try JSONDecoder().decode(DirectoryDifference.self, from: older)
        #expect(decodedOlder.onlyInRight == ["a.txt"])
        #expect(decodedOlder.matches.isEmpty)
    }

    // MARK: - Two-way sync

    @Test("Two-way newest resolves a fuzzy pair between the two actual files")
    func twoWayNewestUsesMatchedPair() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: [:])
        let rightDir = try TestHelpers.createTestDirectory(files: [:])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        try TestHelpers.createFile(
            at: leftDir.appendingPathComponent("notes1.txt"), content: "older left",
            modificationDate: Date(timeIntervalSince1970: 1_000_000))
        try TestHelpers.createFile(
            at: rightDir.appendingPathComponent("notes2.txt"), content: "newer right",
            modificationDate: Date(timeIntervalSince1970: 2_000_000))

        let results = await TestHelpers.collect(
            await directorySync(
                left: leftDir.path(percentEncoded: false),
                right: rightDir.path(percentEncoded: false),
                mode: .twoWay(conflictResolution: .keepNewest),
                ignore: Ignore(patterns: []),
                matchPrecision: 0.8
            ))

        #expect(results.failed == 0)
        #expect(results.operations.count == 1)
        #expect(
            try TestHelpers.readFile(at: leftDir.appendingPathComponent("notes1.txt"))
                == "newer right")
        // Each side keeps its own name
        #expect(!TestHelpers.fileExists(at: leftDir.appendingPathComponent("notes2.txt")))
        #expect(!TestHelpers.fileExists(at: rightDir.appendingPathComponent("notes1.txt")))
    }

    @Test("Two-way keep-left overwrites the matched right file in place")
    func twoWayKeepLeftUsesMatchedPair() async throws {
        let leftDir = try TestHelpers.createTestDirectory(files: ["notes1.txt": "left wins"])
        let rightDir = try TestHelpers.createTestDirectory(files: ["notes2.txt": "right loses"])

        defer {
            try? TestHelpers.cleanupTestDirectory(leftDir)
            try? TestHelpers.cleanupTestDirectory(rightDir)
        }

        let results = await TestHelpers.collect(
            await directorySync(
                left: leftDir.path(percentEncoded: false),
                right: rightDir.path(percentEncoded: false),
                mode: .twoWay(conflictResolution: .keepLeft),
                ignore: Ignore(patterns: []),
                matchPrecision: 0.8
            ))

        #expect(results.failed == 0)
        #expect(
            try TestHelpers.readFile(at: rightDir.appendingPathComponent("notes2.txt"))
                == "left wins")
        #expect(!TestHelpers.fileExists(at: rightDir.appendingPathComponent("notes1.txt")))
    }
}
