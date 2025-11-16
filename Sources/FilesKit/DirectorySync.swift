import Foundation

let COPY_CHUNK_SIZE = 1024 * 1024
let MIN_SIZE_TO_CHUNK = COPY_CHUNK_SIZE * 10

/// Represents a sync operation to be performed
public struct SyncOperation: Sendable {
    public enum OperationType: Sendable {
        case copy
        case delete
        case update
        case info
        case initialization  // Special type for initialization errors
    }

    public let type: OperationType
    public let relativePath: String
    public let left: String?  // nil for delete operations
    public let right: String

    /// Creates a special initialization operation for representing setup errors
    public static func initializationOperation(error: String) -> SyncOperation {
        SyncOperation(
            type: .initialization,
            relativePath: error,
            left: nil,
            right: ""
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

/// Sync mode
public enum SyncMode: Sendable {
    case oneWay
    case twoWay(conflictResolution: ConflictResolution)
}

/// Success case for an operation - contains the operation and what was accomplished
public struct OperationSuccess: Sendable {
    public let operation: SyncOperation
    public let bytesTransferred: Int64
}

/// Failure case for an operation - contains the operation and what went wrong
public struct OperationError: Error, Sendable {
    public let operation: SyncOperation
    public let error: Error

    public var localizedDescription: String {
        "\(error.localizedDescription)"
    }
}

/// The result type for a single operation
public typealias OperationResult = Result<OperationSuccess, OperationError>

/// Helper extensions for working with operation results
extension Array where Element == OperationResult {
    public var succeeded: Int {
        filter {
            if case .success = $0 { return true }; return false
        }.count
    }

    public var failed: Int {
        filter {
            if case .failure = $0 { return true }; return false
        }.count
    }

    public var failedOperations: [(operation: SyncOperation, error: Error)] {
        compactMap {
            if case .failure(let opError) = $0 {
                return (opError.operation, opError.error)
            }
            return nil
        }
    }

    public var operations: [SyncOperation] {
        map { result in
            switch result {
                case .success(let success): return success.operation
                case .failure(let failure): return failure.operation
            }
        }
    }
}

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
    ignore: Ignore? = nil
) async -> AsyncStream<OperationResult> {
    let rightMode: IncludeOnlyInRight =
        switch mode {
            case .oneWay:
                deletions ? .all : showMoreRight ? .leafFoldersOnly : .none
            case .twoWay:
                .all
        }

    let diff: DirectoryDifference
    do {
        diff = try await directoryDifference(
            left: leftPath,
            right: rightPath,
            recursive: recursive,
            includeOnlyInRight: rightMode,
            ignore: ignore
        )
    } catch {
        // Return a stream with a single initialization error
        let syncError: DirectorySyncError
        if let diffError = error as? DirectoryDifferenceError {
            syncError = DirectorySyncError.from(error: diffError)
        } else {
            syncError = error as? DirectorySyncError ?? .operationFailed("\(error)")
        }

        return AsyncStream<OperationResult> { continuation in
            let initOp = SyncOperation.initializationOperation(error: "\(syncError)")
            continuation.yield(
                .failure(
                    OperationError(
                        operation: initOp,
                        error: syncError
                    )))
            continuation.finish()
        }
    }

    // Plan sync operations based on mode
    let planResult = await planSyncOperations(
        diff: diff,
        leftPath: leftPath,
        rightPath: rightPath,
        mode: mode,
        deletions: deletions
    )

    let operations: [SyncOperation]
    switch planResult {
        case .success(let ops):
            operations = ops
        case .failure(let error):
            // Return a stream with a single initialization error
            return AsyncStream<OperationResult> { continuation in
                let initOp = SyncOperation.initializationOperation(
                    error: "Planning failed: \(error)")
                continuation.yield(
                    .failure(
                        OperationError(
                            operation: initOp,
                            error: error
                        )))
                continuation.finish()
            }
    }

    var allOperations = operations
    if rightMode == .leafFoldersOnly {
        allOperations += diff.onlyInRight
            .map {
                createSyncOperation(
                    type: .info,
                    relativePath: $0,
                    leftBasePath: leftPath,
                    rightBasePath: rightPath
                )
            }
            .sorted { $0.relativePath < $1.relativePath }
    }

    // Execute operations if not in dry-run mode
    if dryRun {
        // For dry-run, return a stream that yields success results for all planned operations
        // without actually executing them
        return AsyncStream<OperationResult> { continuation in
            let operationsToRun = allOperations.filter { $0.type != .info }
            for operation in operationsToRun {
                continuation.yield(
                    .success(
                        OperationSuccess(
                            operation: operation,
                            bytesTransferred: 0  // No bytes transferred in dry-run
                        )))
            }
            continuation.finish()
        }
    }

    // Create the stream and execute operations
    return executeSyncOperationsStream(allOperations)
}

/// Plans sync operations based on the directory difference and sync mode
private func planSyncOperations(
    diff: DirectoryDifference,
    leftPath: String,
    rightPath: String,
    mode: SyncMode,
    deletions: Bool
) async -> Result<[SyncOperation], DirectorySyncError> {
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
private func createSyncOperation(
    type: SyncOperation.OperationType,
    relativePath: String,
    leftBasePath: String?,
    rightBasePath: String
) -> SyncOperation {
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

    return SyncOperation(
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
) -> [SyncOperation] {
    // Copy files only in left
    let copyOps = diff.onlyInLeft.map {
        createSyncOperation(
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
            createSyncOperation(
                type: .delete,
                relativePath: $0,
                leftBasePath: nil,
                rightBasePath: rightPath
            )
        } : []

    // Update modified files
    let updateOps = diff.modified.map {
        createSyncOperation(
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
) async -> Result<[SyncOperation], DirectorySyncError> {
    // Copy files only in left to right
    let leftToRightOps = diff.onlyInLeft.map {
        createSyncOperation(
            type: .copy,
            relativePath: $0,
            leftBasePath: leftPath,
            rightBasePath: rightPath
        )
    }

    // Copy files only in right to left
    let rightToLeftOps = diff.onlyInRight.map {
        createSyncOperation(
            type: .copy,
            relativePath: $0,
            leftBasePath: rightPath,
            rightBasePath: leftPath
        )
    }

    // Handle modified files based on conflict resolution strategy
    var conflictOps: [SyncOperation] = []
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
) async -> Result<SyncOperation?, DirectorySyncError> {
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
                SyncOperation(
                    type: .update,
                    relativePath: relativePath,
                    left: leftFile,
                    right: rightFile
                ))
        } else if rightDate > leftDate {
            // Right is newer, copy to left
            return .success(
                SyncOperation(
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
) async -> Result<SyncOperation?, DirectorySyncError> {
    switch resolution {
        case .skip:
            return .success(nil)

        case .keepLeft:
            return .success(
                SyncOperation(
                    type: .update,
                    relativePath: relativePath,
                    left: leftFile,
                    right: rightFile
                ))

        case .keepRight:
            return .success(
                SyncOperation(
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
private func executeSyncOperationsStream(
    _ operations: [SyncOperation]
) -> AsyncStream<OperationResult> {
    return AsyncStream<OperationResult> { continuation in
        Task {
            await executeSyncOperations(operations, continuation: continuation)
        }
    }
}

/// Executes a list of sync operations and yields results to the stream
private func executeSyncOperations(
    _ operations: [SyncOperation],
    continuation: AsyncStream<OperationResult>.Continuation
) async {
    let operationsToRun = operations.filter { $0.type != .info }

    defer {
        // Always finish the continuation when done
        continuation.finish()
    }

    for operation in operationsToRun {
        do {
            // Execute the operation without progress callbacks
            let bytesTransferred = try await executeSyncOperation(operation, progressCallback: nil)

            // Yield success result to stream
            continuation.yield(
                .success(
                    OperationSuccess(
                        operation: operation,
                        bytesTransferred: bytesTransferred
                    )))
        } catch {
            // Yield failure result to stream
            continuation.yield(
                .failure(
                    OperationError(
                        operation: operation,
                        error: error
                    )))
        }
    }
}

/// Gets the size of a single operation
private func getOperationSize(_ operation: SyncOperation) -> Int64 {
    guard let sourcePath = operation.left else { return 0 }
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: sourcePath) else {
        return 0
    }
    return (attrs[.size] as? Int64) ?? 0
}

/// Calculates total bytes to transfer for all operations
private func calculateTotalBytes(_ operations: [SyncOperation]) async -> Int64 {
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

/// Executes a single sync operation
/// - Parameters:
///   - operation: The operation to execute
///   - progressCallback: Optional callback to report progress during file transfer
/// - Returns: Size of the file in bytes (0 for deletions)
@concurrent
private func executeSyncOperation(
    _ operation: SyncOperation,
    progressCallback: (@Sendable (Int64) -> Void)? = nil
) async throws -> Int64 {
    try await Task.detached {
        let fileManager = FileManager.default

        switch operation.type {
            case .copy, .update:
                guard let left = operation.left else {
                    throw DirectorySyncError.operationFailed("No left for copy/update operation")
                }

                // Get file size
                let attrs = try fileManager.attributesOfItem(atPath: left)
                let fileSize = (attrs[.size] as? Int64) ?? 0

                // Create right directory if needed
                let rightURL = URL(fileURLWithPath: operation.right)
                let rightDir = rightURL.deletingLastPathComponent()
                try fileManager.createDirectory(
                    at: rightDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                // Copy file (will overwrite if exists for update operations)
                if fileManager.fileExists(atPath: operation.right) {
                    try fileManager.removeItem(atPath: operation.right)
                }

                // For small files or when no progress callback, use simple copy
                if fileSize < MIN_SIZE_TO_CHUNK || progressCallback == nil {
                    try fileManager.copyItem(atPath: left, toPath: operation.right)
                } else {
                    // For larger files with progress tracking, use chunked copy
                    try copyFileWithProgress(
                        from: left,
                        to: operation.right,
                        fileSize: fileSize,
                        progressCallback: progressCallback
                    )
                }

                return fileSize

            case .delete:
                // Delete file
                if fileManager.fileExists(atPath: operation.right) {
                    try fileManager.removeItem(atPath: operation.right)
                }
                return 0

            case .info, .initialization:
                // These operation types should not be executed
                throw DirectorySyncError.operationFailed("Unsupported operation type")
        }
    }.value
}

/// Copies a file with progress reporting
internal func copyFileWithProgress(
    from source: String,
    to destination: String,
    fileSize: Int64,
    progressCallback: (@Sendable (Int64) -> Void)?
) throws {
    let bufferSize = COPY_CHUNK_SIZE

    guard let inputStream = InputStream(fileAtPath: source) else {
        throw DirectorySyncError.operationFailed("Failed to open source file")
    }
    guard let outputStream = OutputStream(toFileAtPath: destination, append: false) else {
        throw DirectorySyncError.operationFailed("Failed to create destination file")
    }

    inputStream.open()
    outputStream.open()

    defer {
        inputStream.close()
        outputStream.close()
    }

    var buffer = [UInt8](repeating: 0, count: bufferSize)
    var totalBytesRead: Int64 = 0

    while inputStream.hasBytesAvailable {
        let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)

        if bytesRead < 0 {
            throw DirectorySyncError.operationFailed("Failed to read from source file")
        }

        if bytesRead == 0 {
            break
        }

        let bytesWritten = outputStream.write(buffer, maxLength: bytesRead)
        if bytesWritten != bytesRead {
            throw DirectorySyncError.operationFailed("Failed to write to destination file")
        }

        totalBytesRead += Int64(bytesRead)
        progressCallback?(totalBytesRead)
    }
}
