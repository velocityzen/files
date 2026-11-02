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
        guard let date = attrs[.modificationDate] as? Date else {
            throw CocoaError(.fileReadUnknown)
        }
        return date
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

    /// Collects every result from a sync stream
    static func collect(_ stream: AsyncStream<OperationResult>) async -> [OperationResult] {
        var results: [OperationResult] = []
        for await result in stream {
            results.append(result)
        }
        return results
    }

    /// Files in a directory whose name marks them as an unfinished copy
    static func leftoverTempFiles(in url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
            .filter { $0.contains(temporaryFileMarker) }
    }

    /// The built `files` executable, which sits next to the test bundle
    static var filesExecutable: URL {
        // macOS loads tests from a .xctest bundle; Linux runs them as an executable
        let bundleURL = Bundle(for: BundleToken.self).bundleURL
        let productsURL =
            bundleURL.pathExtension == "xctest" ? bundleURL.deletingLastPathComponent() : bundleURL
        return productsURL.appendingPathComponent("files")
    }

    private final class BundleToken {}

    /// Runs the `files` executable in `directory` and captures its output. Status reports go
    /// to a temporary file instead of the terminal running the tests, and come back decoded;
    /// `environment` adds to or overrides the inherited variables, `FILES_STATUS` included.
    static func runFiles(
        _ arguments: [String], in directory: URL, environment: [String: String] = [:]
    ) throws -> (status: Int32, stdout: Data, stderr: String, reports: [SentStatus]) {
        let statusLog = FileManager.default.temporaryDirectory
            .appendingPathComponent("files-status-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: statusLog) }

        let process = Process()
        process.executableURL = filesExecutable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment
            .merging(["FILES_STATUS": statusLog.path(percentEncoded: false)]) { $1 }
            .merging(environment) { $1 }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let reports = (try? String(contentsOf: statusLog, encoding: .utf8)).map(SentStatus.decode)
        return (
            process.terminationStatus, output, String(decoding: errors, as: UTF8.self),
            reports ?? []
        )
    }
}

/// A Program Status Protocol report the `files` executable sent, decoded
struct SentStatus: Equatable, CustomStringConvertible {
    var state: String
    var message: String?
    var progress: Int?
    var app: String?

    init(_ state: String, _ message: String? = nil, progress: Int? = nil, app: String? = "files") {
        self.state = state
        self.message = message
        self.progress = progress
        self.app = app
    }

    var description: String {
        "\(state)\(progress.map { " \($0)%" } ?? ""): \(message ?? "")"
    }

    /// Every `ESC ] 7501 ; key=value:… ESC \` sequence in the text; `msg` is base64
    static func decode(_ text: String) -> [SentStatus] {
        text.components(separatedBy: "\u{1B}]7501;").dropFirst().map { sequence in
            let fields = Dictionary(
                sequence.replacing("\u{1B}\\", with: "").split(separator: ":").map { pair in
                    let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    return (parts[0], parts.count > 1 ? parts[1] : "")
                },
                uniquingKeysWith: { $1 })
            return SentStatus(
                fields["state"] ?? "",
                fields["msg"].flatMap { Data(base64Encoded: $0) }.map {
                    String(decoding: $0, as: UTF8.self)
                },
                progress: fields["progress"].flatMap { Int($0) },
                app: fields["app"])
        }
    }
}
