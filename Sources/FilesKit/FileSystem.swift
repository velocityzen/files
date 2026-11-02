import FPBracket
import Foundation

/// The attributes of a file this module reads and restores
struct FileAttributes: Sendable, Equatable {
    var size: Int64
    var modificationDate: Date?
    var posixPermissions: Int?

    init(size: Int64, modificationDate: Date? = nil, posixPermissions: Int? = nil) {
        self.size = size
        self.modificationDate = modificationDate
        self.posixPermissions = posixPermissions
    }

    fileprivate init(_ info: stat) {
        #if canImport(Darwin)
        let modified = info.st_mtimespec
        #else
        let modified = info.st_mtim
        #endif
        self.size = Int64(info.st_size)
        self.modificationDate = Date(
            timeIntervalSince1970: TimeInterval(modified.tv_sec) + TimeInterval(modified.tv_nsec)
                / 1_000_000_000)
        self.posixPermissions = Int(info.st_mode & 0o7777)
    }
}

/// The failure a POSIX call reported in `errno`
private func posixFailure(_ operation: FileSystemError.Operation, path: String) -> FileSystemError {
    FileSystemError(
        operation: operation, path: path,
        reason: FileSystemError.Reason(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)))
}

/// Runs a FileManager call and turns what it throws into a `FileSystemError`
private func perform<Success>(
    _ operation: FileSystemError.Operation,
    path: String,
    destination: String? = nil,
    _ body: (FileManager) throws -> Success
) -> Result<Success, FileSystemError> {
    Result { try body(FileManager.default) }
        .mapError {
            FileSystemError(
                operation: operation, path: path, destination: destination,
                reason: FileSystemError.Reason($0))
        }
}

// MARK: - Checks

/// Whether anything exists at the path, following symlinks
func fileExists(at path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

/// Whether a directory exists at the path, following symlinks
func directoryExists(at path: String) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        && isDirectory.boolValue
}

/// Whether something other than a directory exists at the path, following symlinks
func regularFileExists(at path: String) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        && !isDirectory.boolValue
}

func isExecutableFile(at path: String) -> Bool {
    FileManager.default.isExecutableFile(atPath: path)
}

// MARK: - Paths

/// The absolute form of a path, resolved against the working directory the way
/// `URL(fileURLWithPath:)` resolves it
func absolutePath(_ path: String) -> String {
    URL(fileURLWithPath: path).path(percentEncoded: false)
}

/// The path with every symbolic link, `.` and `..` resolved, or nil if it doesn't exist
func canonicalPath(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else {
        return nil
    }
    defer { free(resolved) }
    return String(cString: resolved)
}

/// A relative path inside a directory. It is the path `URL.appendingPathComponent` builds,
/// joined as text, since that call also checks the disk for whether the result is a
/// directory, once for every path built.
func joinPath(_ directory: String, _ relativePath: String) -> String {
    directory.hasSuffix("/") ? directory + relativePath : directory + "/" + relativePath
}

// MARK: - Reading

/// The attributes of the item itself, a symbolic link included, as
/// `FileManager.attributesOfItem` returns them. That call also reads every extended
/// attribute, the data protection class and the owner's names, which made it most of the
/// cost of comparing two small files.
func fileAttributes(at path: String) -> Result<FileAttributes, FileSystemError> {
    var info = stat()
    guard lstat(path, &info) == 0 else {
        return .failure(posixFailure(.readAttributes, path: path))
    }
    return .success(FileAttributes(info))
}

func fileContents(at path: String, options: Data.ReadingOptions = []) -> Result<
    Data, FileSystemError
> {
    // Data(contentsOf:) says why a read failed; FileManager.contents(atPath:) only returns nil
    perform(.read, path: path) { _ in
        try Data(contentsOf: URL(filePath: path, directoryHint: .notDirectory), options: options)
    }
}

/// Bytes read from each file at a time when comparing contents
private let comparisonChunkSize = 256 * 1024

/// Whether two files hold the same bytes, following symbolic links. They are read a chunk at
/// a time, so memory stays flat however large the files are, and the first difference ends
/// the reading.
func fileContentsEqual(_ left: String, _ right: String) -> Result<Bool, FileSystemError> {
    let files = openForReading(left).flatMap { leftFile in
        openForReading(right).map { rightFile in (leftFile, rightFile) }
    }
    return files { leftFile, rightFile in contentsEqual(leftFile, rightFile) }
}

private func contentsEqual(_ left: OpenFile, _ right: OpenFile) -> Result<Bool, FileSystemError> {
    // A small file gets a buffer one byte larger than itself, so one chunk reaches its end
    let chunkSize = left.size().map { min(comparisonChunkSize, $0 + 1) } ?? comparisonChunkSize
    return withUnsafeTemporaryAllocation(byteCount: 2 * chunkSize, alignment: 16) { buffer in
        let leftBuffer = UnsafeMutableRawBufferPointer(rebasing: buffer[..<chunkSize])
        let rightBuffer = UnsafeMutableRawBufferPointer(rebasing: buffer[chunkSize...])
        while true {
            let counts = left.readChunk(into: leftBuffer).flatMap { leftCount in
                right.readChunk(into: rightBuffer).map { rightCount in (leftCount, rightCount) }
            }
            guard case .success(let (leftCount, rightCount)) = counts else {
                return counts.map { _ in false }
            }
            guard leftCount == rightCount,
                memcmp(leftBuffer.baseAddress, rightBuffer.baseAddress, leftCount) == 0
            else {
                return .success(false)
            }
            // A chunk that isn't full is the end of both files
            if leftCount < chunkSize {
                return .success(true)
            }
        }
    }
}

/// A file opened for reading, see `openForReading(_:)`
struct OpenFile {
    let descriptor: Int32
    let path: String

    /// The size of the open file, or nil if it can't be read
    func size() -> Int? {
        var info = stat()
        return fstat(descriptor, &info) == 0 ? Int(info.st_size) : nil
    }

    /// Reads from the current offset until the buffer is full or the file ends
    /// - Returns: The number of bytes read, less than the buffer holds only at the end
    func readChunk(into buffer: UnsafeMutableRawBufferPointer) -> Result<Int, FileSystemError> {
        guard let start = buffer.baseAddress else {
            return .success(0)
        }
        var filled = 0
        while filled < buffer.count {
            let count = read(descriptor, start + filled, buffer.count - filled)
            if count > 0 {
                filled += count
            } else if count == 0 {
                break
            } else if errno != EINTR {
                return .failure(posixFailure(.read, path: path))
            }
        }
        return .success(filled)
    }

    /// Moves the offset the next read starts at
    func seek(to offset: Int) -> Result<Void, FileSystemError> {
        lseek(descriptor, off_t(offset), SEEK_SET) >= 0
            ? .success(()) : .failure(posixFailure(.read, path: path))
    }
}

/// Opens a file read-only, following symbolic links
func openFileDescriptor(forReadingAt path: String) -> Result<OpenFile, FileSystemError> {
    let descriptor = open(path, O_RDONLY | O_CLOEXEC)
    return descriptor >= 0
        ? .success(OpenFile(descriptor: descriptor, path: path))
        : .failure(posixFailure(.read, path: path))
}

/// Closes a file opened for reading. Closing a file that was only read can't lose data, so
/// a failure is not reported.
func closeFileDescriptor(_ file: OpenFile) -> Result<Void, FileSystemError> {
    _ = close(file.descriptor)
    return .success(())
}

func directoryEnumerator(
    at url: URL,
    includingPropertiesForKeys keys: [URLResourceKey],
    options: FileManager.DirectoryEnumerationOptions = []
) -> Result<FileManager.DirectoryEnumerator, FileSystemError> {
    guard
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: options)
    else {
        return .failure(
            FileSystemError(
                operation: .list, path: url.path(percentEncoded: false),
                reason: .other("it can't be enumerated")))
    }
    return .success(enumerator)
}

// MARK: - Writing

/// Sets the permissions and modification date that are present in `attributes`
func setFileAttributes(_ attributes: FileAttributes, at path: String) -> Result<
    Void, FileSystemError
> {
    var values: [FileAttributeKey: Any] = [:]
    values[.posixPermissions] = attributes.posixPermissions
    values[.modificationDate] = attributes.modificationDate
    return perform(.setAttributes, path: path) { try $0.setAttributes(values, ofItemAtPath: path) }
}

/// A file opened for writing, see `createForWriting(_:)` and `openForUpdating(_:)`
struct OutputFile {
    let descriptor: Int32
    let path: String

    /// Writes all of the bytes at the current offset
    func writeChunk(_ bytes: UnsafeRawBufferPointer) -> Result<Void, FileSystemError> {
        guard let start = bytes.baseAddress else {
            return .success(())
        }
        var written = 0
        while written < bytes.count {
            let count = write(descriptor, start + written, bytes.count - written)
            if count > 0 {
                written += count
            } else if count == 0 || errno != EINTR {
                return .failure(posixFailure(.write, path: path))
            }
        }
        return .success(())
    }

    func writeChunk(_ data: Data) -> Result<Void, FileSystemError> {
        data.withUnsafeBytes { writeChunk($0) }
    }
}

/// Creates a file and opens it for writing; anything already at the path, a symbolic link
/// included, fails it
func createFileDescriptor(forWritingAt path: String) -> Result<OutputFile, FileSystemError> {
    let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o666)
    return descriptor >= 0
        ? .success(OutputFile(descriptor: descriptor, path: path))
        : .failure(posixFailure(.write, path: path))
}

/// Opens an existing file for writing at its start, without truncating it
func openFileDescriptor(forUpdatingAt path: String) -> Result<OutputFile, FileSystemError> {
    let descriptor = open(path, O_WRONLY | O_CLOEXEC)
    return descriptor >= 0
        ? .success(OutputFile(descriptor: descriptor, path: path))
        : .failure(posixFailure(.write, path: path))
}

/// Closes a written file. Some volumes, network ones especially, only report a failed write
/// when the file is closed, so that failure is the write's.
func closeFileDescriptor(_ file: OutputFile) -> Result<Void, FileSystemError> {
    close(file.descriptor) == 0 ? .success(()) : .failure(posixFailure(.write, path: file.path))
}

/// Bytes read and written at a time when copying contents
let copyChunkSize = 1024 * 1024

/// Copies what is left to read in `input` to `output`, a chunk at a time, so memory stays
/// flat however large the file is
/// - Parameter onChunk: Called with the bytes copied so far after each chunk
/// - Returns: The number of bytes copied
func copyContents(
    from input: OpenFile,
    to output: OutputFile,
    onChunk: (Int64) -> Void = { _ in }
) -> Result<Int64, FileSystemError> {
    withUnsafeTemporaryAllocation(byteCount: copyChunkSize, alignment: 16) { buffer in
        var copied: Int64 = 0
        while true {
            let chunk = input.readChunk(into: buffer).flatMap { count in
                output.writeChunk(UnsafeRawBufferPointer(rebasing: buffer[..<count])).map { count }
            }
            guard case .success(let count) = chunk else {
                return chunk.map { _ in copied }
            }
            copied += Int64(count)
            if count > 0 {
                onChunk(copied)
            }
            // A chunk that isn't full is the end of the file
            if count < buffer.count {
                return .success(copied)
            }
        }
    }
}

/// Copies a file's bytes into a new file, see `copyContents(from:to:onChunk:)`. Only the
/// bytes are copied: the new file has fresh metadata.
func copyFileContents(
    from source: String,
    to destination: String,
    onChunk: (Int64) -> Void = { _ in }
) -> Result<Int64, FileSystemError> {
    let files = openForReading(source).flatMap { input in
        createForWriting(destination).map { output in (input, output) }
    }
    return files { input, output in copyContents(from: input, to: output, onChunk: onChunk) }
}

func writeFile(_ data: Data, to path: String, options: Data.WritingOptions = []) -> Result<
    Void, FileSystemError
> {
    perform(.write, path: path) { _ in
        try data.write(to: URL(fileURLWithPath: path), options: options)
    }
}

/// Creates a directory and any missing parents; an existing directory is fine
func createDirectory(at path: String) -> Result<Void, FileSystemError> {
    perform(.createDirectory, path: path) {
        try $0.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
}

func copyItem(at source: String, to destination: String) -> Result<Void, FileSystemError> {
    perform(.copy, path: source, destination: destination) {
        try $0.copyItem(atPath: source, toPath: destination)
    }
}

func moveItem(at source: String, to destination: String) -> Result<Void, FileSystemError> {
    perform(.move, path: source, destination: destination) {
        try $0.moveItem(atPath: source, toPath: destination)
    }
}

/// Moves a file into place, atomically replacing an existing file at the destination. The
/// moved file keeps its own metadata instead of merging in the old file's.
func moveReplacingItem(at source: String, to destination: String) -> Result<
    Void, FileSystemError
> {
    guard fileExists(at: destination) else {
        return moveItem(at: source, to: destination)
    }
    return perform(.move, path: source, destination: destination) {
        _ = try $0.replaceItemAt(
            URL(fileURLWithPath: destination),
            withItemAt: URL(fileURLWithPath: source),
            backupItemName: nil,
            options: [.usingNewMetadataOnly]
        )
    }
}

func removeItem(at path: String) -> Result<Void, FileSystemError> {
    perform(.remove, path: path) { try $0.removeItem(atPath: path) }
}

/// Removes an item; one that is already gone counts as removed
func removeItemIfPresent(at path: String) -> Result<Void, FileSystemError> {
    removeItem(at: path).flatMapError { error in
        error.reason == .notFound ? .success(()) : .failure(error)
    }
}
