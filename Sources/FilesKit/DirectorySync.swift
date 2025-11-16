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
    }

    public let type: OperationType
    public let relativePath: String
    public let left: String?  // nil for delete operations
    public let right: String
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

/// Result of a sync operation
public struct SyncResult: Sendable {
    public let operations: [SyncOperation]
    public let succeeded: Int
    public let failed: Int
    public let skipped: Int

    public var totalOperations: Int {
        succeeded + failed + skipped
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
///   - progress: Optional progress callback to receive real-time updates (default: nil)
/// - Returns: A `SyncResult` containing the operations performed and their results
/// - Throws: `DirectorySyncError` if directories are invalid or operations fail
public func directorySync(
    left leftPath: String,
    right rightPath: String,
    mode: SyncMode,
    recursive: Bool = true,
    deletions: Bool = false,
    showMoreRight: Bool = false,
    dryRun: Bool = false,
    ignore: Ignore? = nil,
    progress: ProgressHandler? = nil
) async throws -> SyncResult {
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
    } catch let error as DirectoryDifferenceError {
        throw DirectorySyncError.from(error: error)
    }

    // Plan sync operations based on mode
    var operations = try await planSyncOperations(
        diff: diff,
        leftPath: leftPath,
        rightPath: rightPath,
        mode: mode,
        deletions: deletions
    )

    if rightMode == .leafFoldersOnly {
        operations += diff.onlyInRight
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
        return SyncResult(
            operations: operations,
            succeeded: 0,
            failed: 0,
            skipped: operations.count
        )
    }

    return try await executeSyncOperations(operations, progress: progress)
}

/// Plans sync operations based on the directory difference and sync mode
private func planSyncOperations(
    diff: DirectoryDifference,
    leftPath: String,
    rightPath: String,
    mode: SyncMode,
    deletions: Bool
) async throws -> [SyncOperation] {
    switch mode {
        case .oneWay:
            return planOneWaySync(
                diff: diff, leftPath: leftPath, rightPath: rightPath, deletions: deletions)
        case .twoWay(let conflictResolution):
            return try await planTwoWaySync(
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
) async throws -> [SyncOperation] {
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
    let conflictOps = try await diff.modified.asyncCompactMap {
        let leftFile = URL(fileURLWithPath: leftPath)
            .appendingPathComponent($0)
            .path(percentEncoded: false)
        let rightFile = URL(fileURLWithPath: rightPath)
            .appendingPathComponent($0)
            .path(percentEncoded: false)

        return try await resolveConflict(
            relativePath: $0,
            leftFile: leftFile,
            rightFile: rightFile,
            resolution: conflictResolution
        )
    }

    return (leftToRightOps + rightToLeftOps + conflictOps).sorted {
        $0.relativePath < $1.relativePath
    }
}

/// Resolves a conflict between two modified files
@concurrent
private func resolveConflict(
    relativePath: String,
    leftFile: String,
    rightFile: String,
    resolution: ConflictResolution
) async throws -> SyncOperation? {
    switch resolution {
        case .skip:
            return nil

        case .keepLeft:
            return SyncOperation(
                type: .update,
                relativePath: relativePath,
                left: leftFile,
                right: rightFile
            )

        case .keepRight:
            return SyncOperation(
                type: .update,
                relativePath: relativePath,
                left: rightFile,
                right: leftFile
            )

        case .keepNewest:
            let fileManager = FileManager.default
            let leftAttrs = try fileManager.attributesOfItem(atPath: leftFile)
            let rightAttrs = try fileManager.attributesOfItem(atPath: rightFile)

            guard let leftDate = leftAttrs[.modificationDate] as? Date,
                let rightDate = rightAttrs[.modificationDate] as? Date
            else {
                // If we can't determine dates, skip
                return nil
            }

            if leftDate > rightDate {
                // Left is newer, copy to right
                return SyncOperation(
                    type: .update,
                    relativePath: relativePath,
                    left: leftFile,
                    right: rightFile
                )
            } else if rightDate > leftDate {
                // Right is newer, copy to left
                return SyncOperation(
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

/// Executes a list of sync operations
private func executeSyncOperations(
    _ operations: [SyncOperation],
    progress: ProgressHandler? = nil
) async throws -> SyncResult {
    var succeeded = 0
    var failed = 0
    let skipped = 0
    let operationsToRun = operations.filter { $0.type != .info }

    // Calculate total bytes if progress tracking is enabled
    let totalBytes = await calculateTotalBytes(operationsToRun)
    let tracker = ProgressTracker()

    for (index, operation) in operationsToRun.enumerated() {
        do {
            // Get file size before executing operation
            let fileSize = getOperationSize(operation)

            let actualSize = try await executeSyncOperation(operation) { currentBytes in
                Task {
                    // Report progress during file transfer
                    let bytesPerSecond = await tracker.calculateSpeed(adding: currentBytes)
                    let totalTransferred = await tracker.totalBytesTransferred

                    progress?(
                        SyncProgress(
                            currentOperation: operation,
                            completedOperations: index,
                            totalOperations: operationsToRun.count,
                            currentFileBytes: currentBytes,
                            currentFileTotalBytes: fileSize,
                            totalBytesTransferred: totalTransferred + currentBytes,
                            totalBytes: totalBytes,
                            bytesPerSecond: bytesPerSecond
                        ))
                }
            }

            await tracker.addBytes(actualSize)
            succeeded += 1

            // Report completion of this operation
            let bytesPerSecond = await tracker.calculateSpeed()
            let totalTransferred = await tracker.totalBytesTransferred

            progress?(
                SyncProgress(
                    currentOperation: nil,
                    completedOperations: index + 1,
                    totalOperations: operationsToRun.count,
                    currentFileBytes: 0,
                    currentFileTotalBytes: 0,
                    totalBytesTransferred: totalTransferred,
                    totalBytes: totalBytes,
                    bytesPerSecond: bytesPerSecond
                ))
        } catch {
            failed += 1
        }
    }

    return SyncResult(
        operations: operations,
        succeeded: succeeded,
        failed: failed,
        skipped: skipped
    )
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

            case .info:
                throw DirectorySyncError.operationFailed("Unsupported operation")
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
