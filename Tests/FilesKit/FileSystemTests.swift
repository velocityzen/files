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

    @Test("Contents are compared across chunks, to the last byte, and empty files are equal")
    func contentsEqual() throws {
        let directory = try TestHelpers.createTestDirectory(files: [:])
        defer { try? TestHelpers.cleanupTestDirectory(directory) }
        // Larger than the 256 KB read at a time, and not a multiple of it
        let bytes = Data((0..<600_001).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        func write(_ name: String, _ data: Data) throws -> String {
            let file = path(directory, name)
            try data.write(to: URL(filePath: file))
            return file
        }
        var lastChanged = bytes
        lastChanged[bytes.count - 1] ^= 1
        var firstChanged = bytes
        firstChanged[0] ^= 1

        let original = try write("original", bytes)
        let copy = try write("copy", bytes)
        let last = try write("last", lastChanged)
        let first = try write("first", firstChanged)
        let shorter = try write("shorter", bytes.dropLast())
        let empty = try write("empty", Data())
        let alsoEmpty = try write("also-empty", Data())

        #expect(try fileContentsEqual(original, copy).get())
        #expect(try !fileContentsEqual(original, last).get())
        #expect(try !fileContentsEqual(original, first).get())
        #expect(try !fileContentsEqual(original, shorter).get())
        #expect(try fileContentsEqual(empty, alsoEmpty).get())

        let missing = path(directory, "missing")
        #expect(
            fileContentsEqual(original, missing).error
                == FileSystemError(operation: .read, path: missing, reason: .notFound))
    }

    @Test("Copying contents reads and writes a chunk at a time, to the last byte")
    func chunkedCopy() throws {
        let directory = try TestHelpers.createTestDirectory(files: [:])
        defer { try? TestHelpers.cleanupTestDirectory(directory) }
        let bytes = Data((0..<(copyChunkSize * 5 / 2)).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        let source = path(directory, "source")
        try bytes.write(to: URL(filePath: source))

        var chunks: [Int64] = []
        let copy = path(directory, "copy")
        #expect(
            try copyFileContents(from: source, to: copy) { chunks.append($0) }.get()
                == Int64(bytes.count))
        #expect(try Data(contentsOf: URL(filePath: copy)) == bytes)
        let megabyte = Int64(copyChunkSize)
        #expect(chunks == [megabyte, 2 * megabyte, Int64(bytes.count)])

        let empty = path(directory, "empty")
        try Data().write(to: URL(filePath: empty))
        chunks = []
        #expect(
            try copyFileContents(from: empty, to: path(directory, "empty copy")) {
                chunks.append($0)
            }.get() == 0)
        #expect(chunks.isEmpty)

        let missing = path(directory, "missing")
        #expect(
            copyFileContents(from: missing, to: path(directory, "never")).error
                == FileSystemError(operation: .read, path: missing, reason: .notFound))
        #expect(!fileExists(at: path(directory, "never")))
    }

    @Test("A new file never replaces what is at its path, a symbolic link included")
    func createOverExisting() throws {
        let directory = try TestHelpers.createTestDirectory(files: [
            "source": "new", "existing": "keep", "target": "keep too",
        ])
        defer { try? TestHelpers.cleanupTestDirectory(directory) }
        let link = path(directory, "link")
        try FileManager.default.createSymbolicLink(
            atPath: link, withDestinationPath: path(directory, "target"))

        for destination in [path(directory, "existing"), link] {
            #expect(
                copyFileContents(from: path(directory, "source"), to: destination).error
                    == FileSystemError(operation: .write, path: destination, reason: .alreadyExists)
            )
        }
        #expect(
            try TestHelpers.readFile(at: directory.appendingPathComponent("existing")) == "keep")
        #expect(
            try TestHelpers.readFile(at: directory.appendingPathComponent("target")) == "keep too")
    }

    @Test("Updating a file writes over its start and keeps the rest")
    func updateInPlace() throws {
        let directory = try TestHelpers.createTestDirectory(files: ["file": "abcdef"])
        defer { try? TestHelpers.cleanupTestDirectory(directory) }

        let withFile = openForUpdating(path(directory, "file"))
        #expect(withFile { $0.writeChunk(Data("XY".utf8)) }.error == nil)
        #expect(try TestHelpers.readFile(at: directory.appendingPathComponent("file")) == "XYcdef")
    }

    @Test("Temporary files are hidden and marked next to the destination, with its extension")
    func temporaryFileNames() throws {
        let directory = "/some/folder"
        func name(nextTo destination: String) throws -> String {
            let withTemporaryFile = temporaryFile(nextTo: "\(directory)/\(destination)")
            let path = try withTemporaryFile { .success($0) }.get()
            #expect((path as NSString).deletingLastPathComponent == directory)
            return (path as NSString).lastPathComponent
        }

        let track = try name(nextTo: "01 - Track.flac")
        #expect(track.hasPrefix("."))
        #expect(track.hasSuffix("\(temporaryFileMarker).flac"))
        #expect(try name(nextTo: "README").hasSuffix(temporaryFileMarker))
        #expect(try name(nextTo: "a") != (try name(nextTo: "a")))

        // A destination name as long as a name can be
        let long = try name(nextTo: String(repeating: "n", count: 251) + ".bin")
        #expect(long.hasSuffix("\(temporaryFileMarker).bin"))
        // An extension too long to keep
        let longExtension = try name(nextTo: "a." + String(repeating: "x", count: 250))
        #expect(longExtension.hasSuffix(temporaryFileMarker))
        #expect(longExtension.utf8.count <= Int(NAME_MAX))
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
