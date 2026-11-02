import Foundation
import Testing

@testable import FilesKit

@Suite("File system operations")
struct FileSystemTests {
    @Test("Missing items fail with the operation, the path and notFound")
    func missing() throws {
        let directory = try TestHelpers.createTestDirectory(files: [:])
        defer { try? TestHelpers.cleanupTestDirectory(directory) }
        let missing = path(directory, "missing.txt")

        #expect(
            fileAttributes(at: missing).error
                == FileSystemError(operation: .readAttributes, path: missing, reason: .notFound))
        #expect(
            fileContents(at: missing).error
                == FileSystemError(operation: .read, path: missing, reason: .notFound))
        #expect(
            removeItem(at: missing).error
                == FileSystemError(operation: .remove, path: missing, reason: .notFound))
        #expect(removeItemIfPresent(at: missing).error == nil)
    }

    @Test("Copying onto an existing file fails with alreadyExists and a readable message")
    func copyOntoExisting() throws {
        let directory = try TestHelpers.createTestDirectory(files: ["a.txt": "a", "b.txt": "b"])
        defer { try? TestHelpers.cleanupTestDirectory(directory) }
        let a = path(directory, "a.txt")
        let b = path(directory, "b.txt")

        let error = try #require(copyItem(at: a, to: b).error)
        #expect(
            error
                == FileSystemError(
                    operation: .copy, path: a, destination: b, reason: .alreadyExists))
        let message = "Could not copy \(a) to \(b): an item with that name already exists"
        #expect(error.localizedDescription == message)
        // The CLI prints errors by interpolating them
        #expect("\(error as any Error)" == message)
        #expect(try TestHelpers.readFile(at: directory.appendingPathComponent("b.txt")) == "b")
    }

    @Test("Creating a directory makes parents, accepts an existing one, and fails under a file")
    func createDirectories() throws {
        let directory = try TestHelpers.createTestDirectory(files: ["file": ""])
        defer { try? TestHelpers.cleanupTestDirectory(directory) }

        let nested = path(directory, "a/b/c")
        #expect(createDirectory(at: nested).error == nil)
        #expect(directoryExists(at: nested))
        #expect(createDirectory(at: nested).error == nil)

        let underFile = path(directory, "file/child")
        let error = try #require(createDirectory(at: underFile).error)
        #expect(error.operation == .createDirectory)
        #expect(error.path == underFile)
        #expect(error.reason == .notADirectory)
    }

    @Test("Reading a file without permission fails with permissionDenied")
    func permissionDenied() throws {
        let directory = try TestHelpers.createTestDirectory(files: ["secret.txt": "x"])
        let secret = path(directory, "secret.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: secret)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: secret)
            try? TestHelpers.cleanupTestDirectory(directory)
        }
        // Root can read anything
        guard !FileManager.default.isReadableFile(atPath: secret) else {
            return
        }

        #expect(fileContents(at: secret).error?.reason == .permissionDenied)
    }

    @Test("Moving replaces an existing file with the moved file's own metadata")
    func moveReplacing() throws {
        let directory = try TestHelpers.createTestDirectory(files: [
            "new.txt": "new", "old.txt": "old",
        ])
        defer { try? TestHelpers.cleanupTestDirectory(directory) }
        let new = path(directory, "new.txt")
        let old = path(directory, "old.txt")
        let date = Date(timeIntervalSince1970: 1_000_000_000)
        #expect(
            setFileAttributes(
                FileAttributes(size: 0, modificationDate: date, posixPermissions: 0o600), at: new
            )
            .error == nil)

        #expect(moveReplacingItem(at: new, to: old).error == nil)
        #expect(!fileExists(at: new))
        #expect(try TestHelpers.readFile(at: directory.appendingPathComponent("old.txt")) == "new")
        let attributes = try fileAttributes(at: old).get()
        #expect(attributes.size == 3)
        #expect(attributes.modificationDate == date)
        #expect(attributes.posixPermissions == 0o600)

        // Without a file in the way it is a plain move
        let moved = path(directory, "moved.txt")
        #expect(moveReplacingItem(at: old, to: moved).error == nil)
        #expect(regularFileExists(at: moved))
        #expect(!regularFileExists(at: directory.path(percentEncoded: false)))
    }

    @Test("Reasons come from Cocoa codes, underlying POSIX errors, or the message")
    func reasons() {
        #expect(FileSystemError.Reason(CocoaError(.fileWriteOutOfSpace)) == .outOfSpace)
        #expect(FileSystemError.Reason(POSIXError(.EROFS)) == .readOnlyVolume)
        #expect(FileSystemError.Reason(POSIXError(.EISDIR)) == .isADirectory)

        let wrapped = NSError(
            domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
            userInfo: [NSUnderlyingErrorKey: POSIXError(.EACCES) as NSError])
        #expect(FileSystemError.Reason(wrapped) == .permissionDenied)

        let unknown = POSIXError(.EIO)
        #expect(FileSystemError.Reason(unknown) == .other(unknown.localizedDescription))
    }

    private func path(_ directory: URL, _ name: String) -> String {
        directory.appendingPathComponent(name).path(percentEncoded: false)
    }
}

extension Result {
    /// The failure, if there is one
    fileprivate var error: Failure? {
        guard case .failure(let error) = self else {
            return nil
        }
        return error
    }
}
