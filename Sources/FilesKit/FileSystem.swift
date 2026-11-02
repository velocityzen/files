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

    fileprivate init(_ attributes: [FileAttributeKey: Any]) {
        self.size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        self.modificationDate = attributes[.modificationDate] as? Date
        self.posixPermissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
    }
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

// MARK: - Reading

func fileAttributes(at path: String) -> Result<FileAttributes, FileSystemError> {
    perform(.readAttributes, path: path) { try $0.attributesOfItem(atPath: path) }
        .map(FileAttributes.init)
}

func fileContents(at path: String, options: Data.ReadingOptions = []) -> Result<
    Data, FileSystemError
> {
    // Data(contentsOf:) says why a read failed; FileManager.contents(atPath:) only returns nil
    perform(.read, path: path) { _ in
        try Data(contentsOf: URL(fileURLWithPath: path), options: options)
    }
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
