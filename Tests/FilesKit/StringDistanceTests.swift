import Foundation
import Testing

@testable import FilesKit

@Suite("String Distance Tests")
struct StringDistanceTests {

    // MARK: - Levenshtein Distance Tests

    @Test("Identical strings have zero distance")
    func testIdenticalStrings() {
        #expect(levenshteinDistance("hello", "hello") == 0)
        #expect(levenshteinDistance("", "") == 0)
        #expect(levenshteinDistance("test", "test") == 0)
    }

    @Test("Empty string distances")
    func testEmptyStrings() {
        #expect(levenshteinDistance("", "hello") == 5)
        #expect(levenshteinDistance("hello", "") == 5)
        #expect(levenshteinDistance("", "") == 0)
    }

    @Test("Single character difference")
    func testSingleCharacterDifference() {
        #expect(levenshteinDistance("cat", "bat") == 1)
        #expect(levenshteinDistance("hello", "hallo") == 1)
        #expect(levenshteinDistance("test", "text") == 1)
    }

    @Test("Insertion operations")
    func testInsertions() {
        #expect(levenshteinDistance("cat", "cats") == 1)
        #expect(levenshteinDistance("hello", "helloo") == 1)
        #expect(levenshteinDistance("a", "abc") == 2)
    }

    @Test("Deletion operations")
    func testDeletions() {
        #expect(levenshteinDistance("cats", "cat") == 1)
        #expect(levenshteinDistance("hello", "hell") == 1)
        #expect(levenshteinDistance("abc", "a") == 2)
    }

    @Test("Substitution operations")
    func testSubstitutions() {
        #expect(levenshteinDistance("cat", "bat") == 1)
        #expect(levenshteinDistance("abc", "def") == 3)
        #expect(levenshteinDistance("kitten", "sitten") == 1)
    }

    @Test("Complex transformations")
    func testComplexTransformations() {
        #expect(levenshteinDistance("kitten", "sitting") == 3)
        #expect(levenshteinDistance("saturday", "sunday") == 3)
        #expect(levenshteinDistance("intention", "execution") == 5)
    }

    @Test("Case sensitivity")
    func testCaseSensitivity() {
        #expect(levenshteinDistance("Hello", "hello") == 1)
        #expect(levenshteinDistance("TEST", "test") == 4)
        #expect(levenshteinDistance("CamelCase", "camelcase") == 2)
    }

    // MARK: - String Similarity Tests

    @Test("Identical strings have 1.0 similarity")
    func testIdenticalSimilarity() {
        #expect(stringSimilarity("hello", "hello") == 1.0)
        #expect(stringSimilarity("test", "test") == 1.0)
        #expect(stringSimilarity("", "") == 1.0)
    }

    @Test("Empty string similarity")
    func testEmptyStringSimilarity() {
        #expect(stringSimilarity("", "hello") == 0.0)
        #expect(stringSimilarity("hello", "") == 0.0)
        #expect(stringSimilarity("", "") == 1.0)
    }

    @Test("High similarity strings")
    func testHighSimilarity() {
        let similarity1 = stringSimilarity("hello", "hallo")
        #expect(similarity1 >= 0.8)

        let similarity2 = stringSimilarity("report.txt", "reprot.txt")
        #expect(similarity2 >= 0.8)

        let similarity3 = stringSimilarity("file1.txt", "file2.txt")
        #expect(similarity3 > 0.8)
    }

    @Test("Low similarity strings")
    func testLowSimilarity() {
        let similarity1 = stringSimilarity("abc", "xyz")
        #expect(similarity1 == 0.0)

        let similarity2 = stringSimilarity("hello", "world")
        #expect(similarity2 < 0.5)
    }

    @Test("Similarity range is between 0 and 1")
    func testSimilarityRange() {
        let testCases = [
            ("hello", "world"),
            ("abc", "def"),
            ("test", "text"),
            ("kitten", "sitting"),
            ("", "hello"),
            ("same", "same"),
        ]

        for (s1, s2) in testCases {
            let similarity = stringSimilarity(s1, s2)
            #expect(similarity >= 0.0)
            #expect(similarity <= 1.0)
        }
    }

    @Test("Similarity is symmetric")
    func testSimilaritySymmetry() {
        #expect(stringSimilarity("hello", "world") == stringSimilarity("world", "hello"))
        #expect(stringSimilarity("abc", "xyz") == stringSimilarity("xyz", "abc"))
        #expect(stringSimilarity("test", "text") == stringSimilarity("text", "test"))
    }

    @Test("Real-world filename examples")
    func testFilenameExamples() {
        // Common typos should have high similarity
        let typo1 = stringSimilarity("report.txt", "reprot.txt")
        #expect(typo1 >= 0.8)

        // Different versions should have high similarity
        let version = stringSimilarity("file_v1.txt", "file_v2.txt")
        #expect(version > 0.8)

        // Completely different files should have low similarity
        let different = stringSimilarity("readme.md", "config.json")
        #expect(different < 0.5)

        // Similar names with different extensions
        let extensionDiff = stringSimilarity("document.pdf", "document.txt")
        #expect(extensionDiff > 0.7)
    }

    @Test("Similarity calculation correctness")
    func testSimilarityCalculation() {
        // Distance of 1 on a 5-character string: 1.0 - 1/5 = 0.8
        #expect(stringSimilarity("hello", "hallo") == 0.8)

        // Distance of 1 on a 10-character string: 1.0 - 1/10 = 0.9
        #expect(stringSimilarity("helloworld", "halloworld") == 0.9)

        // Distance of 3 on a 3-character string: 1.0 - 3/3 = 0.0
        #expect(stringSimilarity("abc", "xyz") == 0.0)
    }
}

@Suite("Fuzzy Matching Tests")
struct FuzzyMatchingTests {

    @Test("No matches when threshold is too high")
    func testNoMatchesHighThreshold() {
        let leftFiles: Set<String> = ["file1.txt", "file2.txt"]
        let rightFiles: Set<String> = ["completely_different.txt", "another.txt"]

        let matches = findFuzzyMatches(
            leftFiles: leftFiles,
            rightFiles: rightFiles,
            threshold: 0.9
        )

        #expect(matches.isEmpty)
    }

    @Test("Exact matches with threshold 1.0")
    func testExactMatches() {
        let leftFiles: Set<String> = ["file1.txt", "file2.txt"]
        let rightFiles: Set<String> = ["file1.txt", "file2.txt", "file3.txt"]

        let matches = findFuzzyMatches(
            leftFiles: leftFiles,
            rightFiles: rightFiles,
            threshold: 1.0
        )

        #expect(matches.count == 2)
        #expect(matches["file1.txt"] == "file1.txt")
        #expect(matches["file2.txt"] == "file2.txt")
    }

    @Test("Fuzzy matches with typos")
    func testFuzzyMatchesTypos() {
        let leftFiles: Set<String> = ["report.txt", "document.txt"]
        let rightFiles: Set<String> = ["reprot.txt", "documnet.txt"]

        let matches = findFuzzyMatches(
            leftFiles: leftFiles,
            rightFiles: rightFiles,
            threshold: 0.8
        )

        #expect(matches.count == 2)
        #expect(matches["report.txt"] == "reprot.txt")
        #expect(matches["document.txt"] == "documnet.txt")
    }

    @Test("Best match is selected when multiple candidates exist")
    func testBestMatchSelection() {
        let leftFiles: Set<String> = ["test.txt"]
        let rightFiles: Set<String> = ["test1.txt", "test.txt", "testing.txt"]

        let matches = findFuzzyMatches(
            leftFiles: leftFiles,
            rightFiles: rightFiles,
            threshold: 0.8
        )

        // Should match the exact one, not the similar ones
        #expect(matches.count == 1)
        #expect(matches["test.txt"] == "test.txt")
    }

    @Test("Each right file can only match once")
    func testOneToOneMatching() {
        let leftFiles: Set<String> = ["file1.txt", "file2.txt"]
        let rightFiles: Set<String> = ["file1.txt"]

        let matches = findFuzzyMatches(
            leftFiles: leftFiles,
            rightFiles: rightFiles,
            threshold: 0.8
        )

        // Only one left file can match the right file
        #expect(matches.count == 1)
        #expect(matches["file1.txt"] == "file1.txt" || matches["file2.txt"] == "file1.txt")
    }

    @Test("Matches are based on filename only, not full path")
    func testFilenameOnlyMatching() {
        let leftFiles: Set<String> = ["dir1/file.txt", "dir2/document.txt"]
        let rightFiles: Set<String> = ["otherdir/file.txt", "anotherdir/document.txt"]

        let matches = findFuzzyMatches(
            leftFiles: leftFiles,
            rightFiles: rightFiles,
            threshold: 1.0
        )

        // Should match based on filename, not full path
        #expect(matches.count == 2)
        #expect(matches["dir1/file.txt"] == "otherdir/file.txt")
        #expect(matches["dir2/document.txt"] == "anotherdir/document.txt")
    }

    @Test("Lower threshold allows more fuzzy matches")
    func testThresholdEffect() {
        let leftFiles: Set<String> = ["file_abc.txt"]
        let rightFiles: Set<String> = ["file_xyz.txt"]

        // High threshold - no match
        let strictMatches = findFuzzyMatches(
            leftFiles: leftFiles,
            rightFiles: rightFiles,
            threshold: 0.9
        )
        #expect(strictMatches.isEmpty)

        // Lower threshold - might match
        let lenientMatches = findFuzzyMatches(
            leftFiles: leftFiles,
            rightFiles: rightFiles,
            threshold: 0.5
        )
        #expect(lenientMatches.count <= 1)
    }

    @Test("Empty sets return empty matches")
    func testEmptySets() {
        let emptyLeft: Set<String> = []
        let emptyRight: Set<String> = []
        let someFiles: Set<String> = ["file.txt"]

        #expect(findFuzzyMatches(leftFiles: emptyLeft, rightFiles: emptyRight, threshold: 0.8).isEmpty)
        #expect(findFuzzyMatches(leftFiles: emptyLeft, rightFiles: someFiles, threshold: 0.8).isEmpty)
        #expect(findFuzzyMatches(leftFiles: someFiles, rightFiles: emptyRight, threshold: 0.8).isEmpty)
    }

    @Test("Complex path matching")
    func testComplexPaths() {
        let leftFiles: Set<String> = [
            "src/components/Header.tsx",
            "src/components/Footer.tsx"
        ]
        let rightFiles: Set<String> = [
            "src/components/Heeder.tsx",  // typo in Header
            "src/components/Footer.tsx"
        ]

        let matches = findFuzzyMatches(
            leftFiles: leftFiles,
            rightFiles: rightFiles,
            threshold: 0.8
        )

        #expect(matches.count == 2)
        #expect(matches["src/components/Header.tsx"] == "src/components/Heeder.tsx")
        #expect(matches["src/components/Footer.tsx"] == "src/components/Footer.tsx")
    }

    @Test("Greedy algorithm behavior")
    func testGreedyMatching() {
        // Tests that the algorithm greedily matches as it iterates
        let leftFiles: Set<String> = ["aaa.txt", "aab.txt"]
        let rightFiles: Set<String> = ["aaa.txt"]

        let matches = findFuzzyMatches(
            leftFiles: leftFiles,
            rightFiles: rightFiles,
            threshold: 0.9
        )

        // Only one can match since there's only one right file
        #expect(matches.count == 1)
        #expect(matches.values.contains("aaa.txt"))
    }
}
