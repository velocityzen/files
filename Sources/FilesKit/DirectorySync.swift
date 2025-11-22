import Foundation

let COPY_CHUNK_SIZE = 1024 * 1024
let MIN_SIZE_TO_CHUNK = COPY_CHUNK_SIZE * 10

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

public enum DirectorySyncError: Error, Sendable {
    case invalidDirectory(String)
    case accessDenied(String)
    case operationFailed(String)

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
    matchPrecision: Double = 1.0
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
        matchPrecision: matchPrecision
    )

    if case .failure(let error) = diffResult {
        let error = DirectorySyncError.from(error: error)
        let operation = FileOperation.compareOperation(
            leftPath: leftPath,
            rightPath: rightPath,
            error: "\(error)"
        )

        return .fastFail(
            on: operation,
            with: error,
        )
    }

    let diff = try! diffResult.get()

    // Plan sync operations based on mode
    let planResult = await planFileOperations(
        diff: diff,
        leftPath: leftPath,
        rightPath: rightPath,
        mode: mode,
        deletions: deletions
    )

    if case .failure(let error) = planResult {
        let operation = FileOperation.compareOperation(
            leftPath: leftPath,
            rightPath: rightPath,
            error: "Planning failed: \(error)"
        )

        return .fastFail(
            on: operation,
            with: error,
        )
    }

    var operations = try! planResult.get()

    if rightMode == .leafFoldersOnly {
        operations += diff.onlyInRight
            .map {
                createFileOperation(
                    type: .info,
                    relativePath: $0,
                    leftBasePath: leftPath,
                    rightBasePath: rightPath
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

/// Creates a sync operation by building full paths from base directories and relative path
private func createFileOperation(
    type: FileOperation.OperationType,
    relativePath: String,
    leftBasePath: String?,
    rightBasePath: String
) -> FileOperation {
    let left: String? =
        if let leftBasePath {
            URL(fileURLWithPath: leftBasePath)
                .appendingPathComponent(relativePath)
                .path(percentEncoded: false)
        } else {
            nil
        }

    let right = URL(fileURLWithPath: rightBasePath)
        .appendingPathComponent(relativePath)
        .path(percentEncoded: false)

    return FileOperation(
        type: type,
        relativePath: relativePath,
        left: left,
        right: right
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
    // Copy files only in left to right
    let leftToRightOps = diff.onlyInLeft.map {
        createFileOperation(
            type: .copy,
            relativePath: $0,
            leftBasePath: leftPath,
            rightBasePath: rightPath
        )
    }

    // Copy files only in right to left
    let rightToLeftOps = diff.onlyInRight.map {
        createFileOperation(
            type: .copy,
            relativePath: $0,
            leftBasePath: rightPath,
            rightBasePath: leftPath
        )
    }

    // Handle modified files based on conflict resolution strategy
    var conflictOps: [FileOperation] = []
    for relativePath in diff.modified {
        let leftFile = URL(fileURLWithPath: leftPath)
            .appendingPathComponent(relativePath)
            .path(percentEncoded: false)
        let rightFile = URL(fileURLWithPath: rightPath)
            .appendingPathComponent(relativePath)
            .path(percentEncoded: false)

        let result = await resolveConflict(
            relativePath: relativePath,
            leftFile: leftFile,
            rightFile: rightFile,
            resolution: conflictResolution
        )

        switch result {
            case .success(let operation):
                if let operation = operation {
                    conflictOps.append(operation)
                }
            case .failure(let error):
                return .failure(error)
        }
    }

    return .success(
        (leftToRightOps + rightToLeftOps + conflictOps).sorted {
            $0.relativePath < $1.relativePath
        })
}

/// Resolves a conflict between two modified files based on modification dates
@concurrent
private func resolveConflictByNewest(
    relativePath: String,
    leftFile: String,
    rightFile: String
) async -> Result<FileOperation?, DirectorySyncError> {
    let fileManager = FileManager.default

    do {
        let leftAttrs = try fileManager.attributesOfItem(atPath: leftFile)
        let rightAttrs = try fileManager.attributesOfItem(atPath: rightFile)

        guard let leftDate = leftAttrs[.modificationDate] as? Date,
            let rightDate = rightAttrs[.modificationDate] as? Date
        else {
            // If we can't determine dates, skip
            return .success(nil)
        }

        if leftDate > rightDate {
            // Left is newer, copy to right
            return .success(
                FileOperation(
                    type: .update,
                    relativePath: relativePath,
                    left: leftFile,
                    right: rightFile
                ))
        } else if rightDate > leftDate {
            // Right is newer, copy to left
            return .success(
                FileOperation(
                    type: .update,
                    relativePath: relativePath,
                    left: rightFile,
                    right: leftFile
                ))
        } else {
            // Same modification time, skip
            return .success(nil)
        }
    } catch {
        return .failure(.accessDenied("Failed to read file attributes: \(error)"))
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

/// Tracks progress state for sync operations
private actor ProgressTracker {
    private(set) var totalBytesTransferred: Int64 = 0
    private let startTime = Date()

    func addBytes(_ bytes: Int64) {
        totalBytesTransferred += bytes
    }

    func calculateSpeed() -> Double {
        let elapsed = Date().timeIntervalSince(startTime)
        return elapsed > 0 ? Double(totalBytesTransferred) / elapsed : 0
    }

    func calculateSpeed(adding bytes: Int64) -> Double {
        let elapsed = Date().timeIntervalSince(startTime)
        return elapsed > 0 ? Double(totalBytesTransferred + bytes) / elapsed : 0
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

/// Gets the size of a single operation
private func getOperationSize(_ operation: FileOperation) -> Int64 {
    guard let sourcePath = operation.left else { return 0 }
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: sourcePath) else {
        return 0
    }
    return (attrs[.size] as? Int64) ?? 0
}

/// Calculates total bytes to transfer for all operations
private func calculateTotalBytes(_ operations: [FileOperation]) async -> Int64 {
    await withTaskGroup(of: Int64.self) { group in
        for operation in operations {
            group.addTask {
                guard let sourcePath = operation.left else { return 0 }
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: sourcePath)
                else { return 0 }
                return (attrs[.size] as? Int64) ?? 0
            }
        }

        var total: Int64 = 0
        for await size in group {
            total += size
        }
        return total
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

    do {
        // Get file size
        let attrs = try FileManager.default.attributesOfItem(atPath: left)
        let fileSize = (attrs[.size] as? Int64) ?? 0

        // Create right directory if needed
        let rightURL = URL(fileURLWithPath: operation.right)
        let rightDir = rightURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: rightDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Copy file (will overwrite if exists for update operations)
        if FileManager.default.fileExists(atPath: operation.right) {
            try FileManager.default.removeItem(atPath: operation.right)
        }

        if fileSize < MIN_SIZE_TO_CHUNK {
            // For small files, use simple copy
            try FileManager.default.copyItem(atPath: left, toPath: operation.right)
            continuation.success(operation: operation, bytesTransferred: fileSize)
        } else {
            copyFileWithProgress(
                operation: operation,
                expectedFileSize: fileSize,
                continuation: continuation
            )
        }
    } catch {
        return continuation.failure(operation: operation, error: error)
    }
}

private func deleteOperation(for operation: FileOperation) -> OperationResult {
    do {
        if FileManager.default.fileExists(atPath: operation.right) {
            try FileManager.default.removeItem(atPath: operation.right)
        }

        return .success(OperationSuccess(operation: operation, bytesTransferred: 0))
    } catch {
        return .failure(OperationError(operation: operation, error: error))
    }
}

/// Copies a file with progress reporting via the stream continuation
internal func copyFileWithProgress(
    operation: FileOperation,
    expectedFileSize: Int64,
    continuation: AsyncStream<OperationResult>.Continuation
) {
    let bufferSize = COPY_CHUNK_SIZE

    // we check that file exists vefore calling this function
    guard let inputStream = InputStream(fileAtPath: operation.left!) else {
        return continuation.failure(
            operation: operation,
            error: DirectorySyncError.operationFailed("Failed to open source file")
        )
    }
    guard let outputStream = OutputStream(toFileAtPath: operation.right, append: false) else {
        return continuation.failure(
            operation: operation,
            error: DirectorySyncError.operationFailed("Failed to create destination file")
        )
    }

    inputStream.open()
    outputStream.open()

    defer {
        inputStream.close()
        outputStream.close()
    }

    var buffer = [UInt8](repeating: 0, count: bufferSize)
    var totalBytesRead: Int64 = 0
    var lastReportedBytes: Int64 = 0

    while inputStream.hasBytesAvailable {
        let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)

        if bytesRead < 0 {
            return continuation.failure(
                operation: operation,
                error: DirectorySyncError.operationFailed("Failed to read from source file")
            )
        }

        if bytesRead == 0 {
            break
        }

        let bytesWritten = outputStream.write(buffer, maxLength: bytesRead)
        if bytesWritten != bytesRead {
            return continuation.failure(
                operation: operation,
                error: DirectorySyncError.operationFailed("Failed to write to destination file")
            )
        }

        totalBytesRead += Int64(bytesRead)

        // Yield progress update only at intervals
        if totalBytesRead - lastReportedBytes >= MIN_SIZE_TO_CHUNK {
            continuation.success(operation: operation, bytesTransferred: totalBytesRead)
            lastReportedBytes = totalBytesRead
        }
    }

    // Final progress update with exact total
    if totalBytesRead != lastReportedBytes {
        continuation.success(operation: operation, bytesTransferred: totalBytesRead)
    }

    if totalBytesRead != expectedFileSize {
        return continuation.failure(
            operation: operation,
            error: DirectorySyncError.operationFailed(
                "Transferred \(totalBytesRead) bytes, expected \(expectedFileSize)")
        )
    }
}
