import Foundation
@testable import FilesKit

/// Shared test helpers for FilesKit tests
enum TestHelpers {

    /// Creates a temporary directory with the specified files
    /// - Parameter files: Dictionary of relative paths to file contents
    /// - Returns: URL of the created temporary directory
    static func createTestDirectory(files: [String: String]) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for (path, content) in files {
            let fileURL = tempDir.appendingPathComponent(path)
            let dirURL = fileURL.deletingLastPathComponent()

            // Create subdirectories if needed
            try FileManager.default.createDirectory(
                at: dirURL, withIntermediateDirectories: true)

            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return tempDir
    }

    /// Cleans up a test directory
    /// - Parameter url: URL of the directory to remove
    static func cleanupTestDirectory(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// Creates a test file with a specific modification date
    /// - Parameters:
    ///   - url: URL where to create the file
    ///   - content: Content of the file
    ///   - modificationDate: Modification date to set
    static func createFile(at url: URL, content: String, modificationDate: Date) throws {
        let dirURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dirURL, withIntermediateDirectories: true)

        try content.write(to: url, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    /// Reads the content of a file
    /// - Parameter url: URL of the file to read
    /// - Returns: Content of the file as a string
    static func readFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Checks if a file exists at the given path
    /// - Parameter url: URL of the file to check
    /// - Returns: True if the file exists
    static func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Gets the modification date of a file
    /// - Parameter url: URL of the file
    /// - Returns: Modification date of the file
    static func getModificationDate(of url: URL) throws -> Date {
        let attrs = try FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false))
        return attrs[.modificationDate] as! Date
    }

    /// Creates a JSON file from a DirectoryDifference
    /// - Parameter diff: The DirectoryDifference to serialize
    /// - Returns: Path to the created JSON file
    static func createJSONFile(diff: DirectoryDifference) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let jsonFile = tempDir.appendingPathComponent(UUID().uuidString + ".json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(diff)

        try jsonData.write(to: jsonFile)

        return jsonFile.path(percentEncoded: false)
    }

    /// Creates two JSON comparison files for testing
    /// - Parameters:
    ///   - left: Left DirectoryDifference
    ///   - right: Right DirectoryDifference
    /// - Returns: Tuple of (leftFilePath, rightFilePath)
    static func createJSONComparisonFiles(
        left: DirectoryDifference,
        right: DirectoryDifference
    ) throws -> (String, String) {
        let leftFile = try createJSONFile(diff: left)
        let rightFile = try createJSONFile(diff: right)
        return (leftFile, rightFile)
    }
}
