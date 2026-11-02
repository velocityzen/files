import FP
import Foundation

/// Files this large are copied a chunk at a time, reporting progress as they go
let minSizeToChunk = copyChunkSize * 10

public struct FileOperation: Sendable, Equatable, Hashable {
    public enum OperationType: Sendable, CustomStringConvertible {
        case copy
        case delete
        case update
        case info
        case compare  // Special type for comparison/validation errors

        public var description: String {
            switch self {
                case .copy: "+"
                case .delete: "-"
                case .update: "^"
                case .info: "i"
                case .compare: "❌"
            }
        }
    }

    public let type: OperationType
    public let relativePath: String
    public let left: String?  // nil for delete operations
    public let right: String

    /// Creates a special comparison operation for representing directory comparison errors
    public static func compareOperation(leftPath: String, rightPath: String, error: String)
        -> FileOperation
    {
        FileOperation(
            type: .compare,
            relativePath: error,
            left: leftPath,
            right: rightPath
        )
    }
}

/// Conflict resolution strategy for two-way sync
public enum ConflictResolution: Sendable {
    case keepNewest
    case keepLeft
    case keepRight
    case skip
}

public enum SyncMode: Sendable {
    case oneWay
    case twoWay(conflictResolution: ConflictResolution)
}

public struct OperationSuccess: Sendable {
    public let operation: FileOperation
    public let bytesTransferred: Int64
}

public struct OperationError: Error, Sendable {
    public let operation: FileOperation
    public let error: Error

    public var localizedDescription: String {
        "\(error.localizedDescription)"
    }
}

/// The result type for a single operation
public typealias OperationResult = Result<OperationSuccess, OperationError>

public enum DirectorySyncError: Error, Sendable, LocalizedError {
    case invalidDirectory(String)
    case accessDenied(String)
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
            case .invalidDirectory(let path): "Invalid directory: \(path)"
            case .accessDenied(let message): "Access denied: \(message)"
            case .operationFailed(let message): "Operation failed: \(message)"
        }
    }

    /// Converts a DirectoryDifferenceError to a DirectorySyncError
    static func from(error: DirectoryDifferenceError) -> DirectorySyncError {
        switch error {
            case .invalidDirectory(let path):
                return .invalidDirectory(path)
            case .accessDenied(let message):
                return .accessDenied(message)
        }
    }
}

/// Synchronizes two directories
/// - Parameters:
///   - leftPath: Path to the left directory
///   - rightPath: Path to the right directory
///   - mode: Sync mode (one-way or two-way with conflict resolution)
///   - recursive: Whether to sync subdirectories recursively (default: true)
///   - deletions: Whether to delete files in destination that don't exist in source (default: false)
///   - showMoreRight: If true, scan leaf directories on the right side for additional diff information (one-way sync without deletions only, default: false)
///   - dryRun: If true, only plan operations without executing them (default: false)
///   - ignore: Optional ignore patterns to skip certain files (default: nil, will auto-load from .filesignore files)
///   - sizeTolerance: Maximum allowed file size difference ratio for fuzzy-matched files (0.0 to 1.0, default: 0.0)
///   - concurrentReads: How many pairs of files are read and compared at once, at least 1 (default: `defaultConcurrentReads`)
/// - Returns: An AsyncStream that yields OperationResult for each completed operation
/// - Note: If directory validation fails, the stream will yield a single initialization error and finish
public func directorySync(
    left leftPath: String,
    right rightPath: String,
    mode: SyncMode,
    recursive: Bool = true,
    deletions: Bool = false,
    showMoreRight: Bool = false,
    dryRun: Bool = false,
    ignore: Ignore? = nil,
    matchPrecision: Double = 1.0,
    sizeTolerance: Double = 0.0,
    concurrentReads: Int = defaultConcurrentReads
) async -> AsyncStream<OperationResult> {
    let rightMode: IncludeOnlyInRight =
        switch mode {
            case .oneWay:
                deletions ? .all : showMoreRight ? .leafFoldersOnly : .none
            case .twoWay:
                .all
        }

    let diffResult = await directoryDifference(
        left: leftPath,
        right: rightPath,
        recursive: recursive,
        includeOnlyInRight: rightMode,
        ignore: ignore,
        matchPrecision: matchPrecision,
        sizeTolerance: sizeTolerance,
        concurrentReads: concurrentReads
    )

    let diff: DirectoryDifference
    switch diffResult {
        case .success(let result):
            diff = result
        case .failure(let diffError):
            let error = DirectorySyncError.from(error: diffError)
            let operation = FileOperation.compareOperation(
                leftPath: leftPath,
                rightPath: rightPath,
                error: "\(error)"
            )

            return .fastFail(
                on: operation,
                with: error
            )
    }

    // Operations hold absolute paths; resolve the bases once and join each relative path
    let leftBase = absolutePath(leftPath)
    let rightBase = absolutePath(rightPath)

    // Plan sync operations based on mode
    let planResult = await planFileOperations(
        diff: diff,
        leftPath: leftBase,
        rightPath: rightBase,
        mode: mode,
        deletions: deletions
    )

    var operations: [FileOperation]
    switch planResult {
        case .success(let planned):
            operations = planned
        case .failure(let planError):
            let operation = FileOperation.compareOperation(
                leftPath: leftPath,
                rightPath: rightPath,
                error: "Planning failed: \(planError)"
            )

            return .fastFail(
                on: operation,
                with: planError
            )
    }

    if rightMode == .leafFoldersOnly {
        operations += diff.onlyInRight
            .map {
                createFileOperation(
                    type: .info,
                    relativePath: $0,
                    leftBasePath: leftBase,
                    rightBasePath: rightBase
                )
            }
            .sorted { $0.relativePath < $1.relativePath }
    }

    if dryRun {
        return .flush(operations: operations)
    }

    return executeFileOperationsStream(operations)
}

/// Plans sync operations based on the directory difference and sync mode
private func planFileOperations(
    diff: DirectoryDifference,
    leftPath: String,
    rightPath: String,
    mode: SyncMode,
    deletions: Bool
) async -> Result<[FileOperation], DirectorySyncError> {
    switch mode {
        case .oneWay:
            return .success(
                planOneWaySync(
                    diff: diff, leftPath: leftPath, rightPath: rightPath, deletions: deletions))
        case .twoWay(let conflictResolution):
            return await planTwoWaySync(
                diff: diff,
                leftPath: leftPath,
                rightPath: rightPath,
                conflictResolution: conflictResolution
            )
    }
}

/// Creates a sync operation by joining the relative path onto absolute base directories
private func createFileOperation(
    type: FileOperation.OperationType,
    relativePath: String,
    leftBasePath: String?,
    rightBasePath: String
) -> FileOperation {
    FileOperation(
        type: type,
        relativePath: relativePath,
        left: leftBasePath.map { joinPath($0, relativePath) },
        right: joinPath(rightBasePath, relativePath)
    )
}

/// Plans one-way sync operations (left -> right)
private func planOneWaySync(
    diff: DirectoryDifference,
    leftPath: String,
    rightPath: String,
    deletions: Bool
) -> [FileOperation] {
    // Copy files only in left
    let copyOps = diff.onlyInLeft.map {
        createFileOperation(
            type: .copy,
            relativePath: $0,
            leftBasePath: leftPath,
            rightBasePath: rightPath
        )
    }

    // Delete files only in right (only if deletions flag is true)
    let deleteOps =
        deletions
        ? diff.onlyInRight.map {
            createFileOperation(
                type: .delete,
                relativePath: $0,
                leftBasePath: nil,
                rightBasePath: rightPath
            )
        } : []

    // Update modified files
    let updateOps = diff.modified.map {
        createFileOperation(
            type: .update,
            relativePath: $0,
            leftBasePath: leftPath,
            rightBasePath: rightPath
        )
    }

    return (copyOps + deleteOps + updateOps).sorted { $0.relativePath < $1.relativePath }
}

/// Plans two-way sync operations with conflict resolution
private func planTwoWaySync(
    diff: DirectoryDifference,
    leftPath: String,
    rightPath: String,
    conflictResolution: ConflictResolution
) async -> Result<[FileOperation], DirectorySyncError> {
    let leftToRightOps = diff.onlyInLeft.map {
        createFileOperation(
            type: .copy,
            relativePath: $0,
            leftBasePath: leftPath,
            rightBasePath: rightPath
        )
    }

    let rightToLeftOps = diff.onlyInRight.map {
        createFileOperation(
            type: .copy,
            relativePath: $0,
            leftBasePath: rightPath,
            rightBasePath: leftPath
        )
    }

    let conflictResult = await resolveModifiedFiles(
        diff: diff,
        leftPath: leftPath,
        rightPath: rightPath,
        conflictResolution: conflictResolution
    )

    switch conflictResult {
        case .success(let conflictOps):
            return .success(
                (leftToRightOps + rightToLeftOps + conflictOps).sorted {
                    $0.relativePath < $1.relativePath
                })
        case .failure(let error):
            return .failure(error)
    }
}

/// Resolves conflicts for all modified files during two-way sync
/// A fuzzy-matched pair is resolved between its two actual files, and the losing file
/// is overwritten in place, so each side keeps its own name
private func resolveModifiedFiles(
    diff: DirectoryDifference,
    leftPath: String,
    rightPath: String,
    conflictResolution: ConflictResolution
) async -> Result<[FileOperation], DirectorySyncError> {
    var operations: [FileOperation] = []

    for relativePath in diff.modified {
        let leftFile = joinPath(leftPath, relativePath)
        let rightFile = joinPath(rightPath, diff.rightPath(for: relativePath))

        let result = await resolveConflict(
            relativePath: relativePath,
            leftFile: leftFile,
            rightFile: rightFile,
            resolution: conflictResolution
        )

        switch result {
            case .success(let operation):
                if let operation = operation {
                    operations.append(operation)
                }
            case .failure(let error):
                return .failure(error)
        }
    }

    return .success(operations)
}

/// Resolves a conflict between two modified files based on modification dates
@concurrent
private func resolveConflictByNewest(
    relativePath: String,
    leftFile: String,
    rightFile: String
) async -> Result<FileOperation?, DirectorySyncError> {
    fileAttributes(at: leftFile)
        .flatMap { left in fileAttributes(at: rightFile).map { right in (left, right) } }
        .mapError { .accessDenied("Failed to read file attributes: \($0.localizedDescription)") }
        .map { left, right in
            guard let leftDate = left.modificationDate, let rightDate = right.modificationDate
            else {
                // If we can't determine dates, skip
                return nil
            }

            if leftDate > rightDate {
                // Left is newer, copy to right
                return FileOperation(
                    type: .update,
                    relativePath: relativePath,
                    left: leftFile,
                    right: rightFile
                )
            } else if rightDate > leftDate {
                // Right is newer, copy to left
                return FileOperation(
                    type: .update,
                    relativePath: relativePath,
                    left: rightFile,
                    right: leftFile
                )
            } else {
                // Same modification time, skip
                return nil
            }
        }
}

/// Resolves a conflict between two modified files
@concurrent
private func resolveConflict(
    relativePath: String,
    leftFile: String,
    rightFile: String,
    resolution: ConflictResolution
) async -> Result<FileOperation?, DirectorySyncError> {
    switch resolution {
        case .skip:
            return .success(nil)

        case .keepLeft:
            return .success(
                FileOperation(
                    type: .update,
                    relativePath: relativePath,
                    left: leftFile,
                    right: rightFile
                ))

        case .keepRight:
            return .success(
                FileOperation(
                    type: .update,
                    relativePath: relativePath,
                    left: rightFile,
                    right: leftFile
                ))

        case .keepNewest:
            return await resolveConflictByNewest(
                relativePath: relativePath,
                leftFile: leftFile,
                rightFile: rightFile
            )
    }
}

/// Executes sync operations and returns a stream of operation results
private func executeFileOperationsStream(
    _ operations: [FileOperation]
) -> AsyncStream<OperationResult> {
    AsyncStream<OperationResult> { continuation in
        Task {
            await executeFileOperations(operations, with: continuation)
        }
    }
}

private func executeFileOperations(
    _ operations: [FileOperation],
    with continuation: AsyncStream<OperationResult>.Continuation
) async {
    defer {
        continuation.finish()
    }

    for operation in operations {
        await executeFileOperation(operation, with: continuation)
    }
}

private func executeFileOperation(
    _ operation: FileOperation,
    with continuation: AsyncStream<OperationResult>.Continuation
) async {
    await Task.detached {
        switch operation.type {
            case .copy, .update:
                await copyOperation(for: operation, with: continuation)

            case .delete:
                let result = deleteOperation(for: operation)
                continuation.yield(result)

            case .info, .compare:
                // just forward operations
                continuation.success(operation: operation, bytesTransferred: 0)
        }
    }.value
}

private func copyOperation(
    for operation: FileOperation,
    with continuation: AsyncStream<OperationResult>.Continuation
) async {
    guard let left = operation.left else {
        return continuation.failure(
            operation: operation,
            error: DirectorySyncError.operationFailed("No left for copy/update operation")
        )
    }

    fileAttributes(at: left)
        .flatMap { attributes in
            copyIntoPlace(left, to: operation.right, attributes) { bytesCopied in
                continuation.success(operation: operation, bytesTransferred: bytesCopied)
            }
            .map { attributes.size }
        }
        .match(
            { continuation.success(operation: operation, bytesTransferred: $0) },
            { continuation.failure(operation: operation, error: $0) }
        )
}

/// Copies next to the destination first and moves the copy into place, so a failed or
/// interrupted copy never touches an existing file
private func copyIntoPlace(
    _ source: String,
    to destination: String,
    _ attributes: FileAttributes,
    onProgress: (Int64) -> Void
) -> Result<Void, FileSystemError> {
    let directory = URL(fileURLWithPath: destination).deletingLastPathComponent()
        .path(percentEncoded: false)
    let withTemporaryFile = temporaryFile(nextTo: destination)
    return createDirectory(at: directory).flatMap { _ in
        withTemporaryFile { temporary in
            copyFile(source, to: temporary, attributes, onProgress: onProgress)
                .flatMap { _ in moveReplacingItem(at: temporary, to: destination) }
        }
    }
}

private func copyFile(
    _ source: String,
    to destination: String,
    _ attributes: FileAttributes,
    onProgress: (Int64) -> Void
) -> Result<Void, FileSystemError> {
    if attributes.size < minSizeToChunk {
        return copyItem(at: source, to: destination)
    }
    // A streamed copy has fresh metadata, so keep what copyItem would keep
    return copyFileWithProgress(
        from: source, to: destination, expectedFileSize: attributes.size, onProgress: onProgress
    )
    .flatMap { _ in setFileAttributes(attributes, at: destination) }
}

private func deleteOperation(for operation: FileOperation) -> OperationResult {
    removeItemIfPresent(at: operation.right)
        .map { OperationSuccess(operation: operation, bytesTransferred: 0) }
        .mapError { OperationError(operation: operation, error: $0) }
}

/// Copies a file in chunks, calling `onProgress` with the bytes copied so far at intervals
func copyFileWithProgress(
    from source: String,
    to destination: String,
    expectedFileSize: Int64,
    onProgress: (Int64) -> Void
) -> Result<Void, FileSystemError> {
    var lastReported: Int64 = 0
    return copyFileContents(from: source, to: destination) { copied in
        // Report progress only at intervals; the caller reports the final total
        if copied - lastReported >= minSizeToChunk {
            onProgress(copied)
            lastReported = copied
        }
    }
    .flatMap { copied in
        // The destination is a temporary file, so only the source is named
        copied == expectedFileSize
            ? .success(())
            : .failure(
                FileSystemError(
                    operation: .copy, path: source,
                    reason: .other("it changed size while being copied")))
    }
}
