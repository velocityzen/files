import Foundation
import Testing

@testable import FilesKit

@Suite("Ignore Tests")
struct IgnoreTests {
    @Test("Empty patterns don't ignore anything")
    func testEmptyPatterns() {
        let patterns = Ignore()

        #expect(!patterns.shouldIgnore("file.txt"))
        #expect(!patterns.shouldIgnore("dir/file.txt"))
        #expect(!patterns.shouldIgnore(".hidden"))
    }

    @Test("Simple filename pattern")
    func testSimpleFilename() {
        let patterns = Ignore(patterns: ["*.log"])

        #expect(patterns.shouldIgnore("error.log"))
        #expect(patterns.shouldIgnore("debug.log"))
        #expect(!patterns.shouldIgnore("error.txt"))
        #expect(patterns.shouldIgnore("dir/error.log"))
    }

    @Test("Directory-specific pattern")
    func testDirectoryPattern() {
        let patterns = Ignore(patterns: ["node_modules/"])

        #expect(patterns.shouldIgnore("node_modules", isDirectory: true))
        #expect(!patterns.shouldIgnore("node_modules", isDirectory: false))
        #expect(!patterns.shouldIgnore("node_modules.txt"))
    }

    @Test("Wildcard patterns")
    func testWildcardPatterns() {
        let patterns = Ignore(patterns: ["*.tmp", "temp*"])

        #expect(patterns.shouldIgnore("file.tmp"))
        #expect(patterns.shouldIgnore("tempfile"))
        #expect(patterns.shouldIgnore("temporary"))
        #expect(!patterns.shouldIgnore("file.txt"))
    }

    @Test("Nested directory patterns")
    func testNestedPatterns() {
        let patterns = Ignore(patterns: ["build/**/*.o"])

        #expect(patterns.shouldIgnore("build/main.o"))
        #expect(patterns.shouldIgnore("build/src/main.o"))
        #expect(patterns.shouldIgnore("build/src/lib/helper.o"))
        #expect(!patterns.shouldIgnore("src/main.o"))
    }

    @Test("Root-relative patterns")
    func testRootRelativePatterns() {
        let patterns = Ignore(patterns: ["/config.txt"])

        #expect(patterns.shouldIgnore("config.txt"))
        #expect(!patterns.shouldIgnore("dir/config.txt"))
    }

    @Test("Negation patterns")
    func testNegationPatterns() {
        let patterns = Ignore(patterns: [
            "*.log",
            "!important.log",
        ])

        #expect(patterns.shouldIgnore("error.log"))
        #expect(patterns.shouldIgnore("debug.log"))
        #expect(!patterns.shouldIgnore("important.log"))
    }

    @Test("Comment and empty lines are ignored")
    func testCommentsAndEmptyLines() {
        let patterns = Ignore(patterns: [
            "# This is a comment",
            "",
            "*.log",
            "  ",
            "# Another comment",
        ])

        #expect(patterns.shouldIgnore("error.log"))
        #expect(!patterns.shouldIgnore("# This is a comment"))
    }

    @Test("Hidden files pattern")
    func testHiddenFiles() {
        let patterns = Ignore(patterns: [".*"])

        #expect(patterns.shouldIgnore(".hidden"))
        #expect(patterns.shouldIgnore(".git"))
        #expect(patterns.shouldIgnore("dir/.hidden"))
        #expect(!patterns.shouldIgnore("visible.txt"))
    }

    @Test("Multiple patterns with priority")
    func testMultiplePatternsWithPriority() {
        let patterns = Ignore(patterns: [
            "*.txt",
            "!important.txt",
            "*.txt",  // This should re-ignore important.txt
        ])

        #expect(patterns.shouldIgnore("file.txt"))
        #expect(patterns.shouldIgnore("important.txt"))  // Last matching pattern wins
    }

    @Test("Complex real-world patterns")
    func testRealWorldPatterns() {
        let patterns = Ignore(patterns: [
            "node_modules/",
            ".git/",
            "*.log",
            "*.tmp",
            "build/",
            ".DS_Store",
            "thumbs.db",
        ])

        #expect(patterns.shouldIgnore("node_modules", isDirectory: true))
        #expect(patterns.shouldIgnore(".git", isDirectory: true))
        #expect(patterns.shouldIgnore("error.log"))
        #expect(patterns.shouldIgnore("temp.tmp"))
        #expect(patterns.shouldIgnore("build", isDirectory: true))
        #expect(patterns.shouldIgnore(".DS_Store"))
        #expect(patterns.shouldIgnore("thumbs.db"))
        #expect(!patterns.shouldIgnore("src/main.swift"))
    }

    @Test("Specific file extension in directory")
    func testSpecificExtensionInDirectory() {
        let patterns = Ignore(patterns: ["*.class"])

        #expect(patterns.shouldIgnore("Main.class"))
        #expect(patterns.shouldIgnore("com/example/Main.class"))
        #expect(!patterns.shouldIgnore("Main.java"))
    }

    @Test("Question mark wildcard")
    func testQuestionMarkWildcard() {
        let patterns = Ignore(patterns: ["file?.txt"])

        #expect(patterns.shouldIgnore("file1.txt"))
        #expect(patterns.shouldIgnore("filea.txt"))
        #expect(!patterns.shouldIgnore("file.txt"))
        #expect(!patterns.shouldIgnore("file12.txt"))
    }
}
