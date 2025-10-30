import Foundation


/// Represents a sync operation to be performed
public struct SyncOperation: Sendable {
    public enum OperationType: Sendable {
        case copy
        case delete
        case update
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
///   - dryRun: If true, only plan operations without executing them (default: false)
/// - Returns: A `SyncResult` containing the operations performed and their results
/// - Throws: `DirectorySyncError` if directories are invalid or operations fail
public func directorySync(
    left leftPath: String,
    right rightPath: String,
    mode: SyncMode,
    recursive: Bool = true,
    deletions: Bool = false,
    dryRun: Bool = false
) async throws -> SyncResult {
    let diff: DirectoryDifference
    do {
        // Optimization: when doing one-way sync without deletions,
        // we don't need to know about files only in right
        let includeOnlyInRight = switch mode {
            case .oneWay:
                deletions
            case .twoWay:
                true
        }

        diff = try await directoryDifference(
            left: leftPath,
            right: rightPath,
            recursive: recursive,
            includeOnlyInRight: includeOnlyInRight
        )
    } catch let error as DirectoryDifferenceError {
        throw DirectorySyncError.from(error: error)
    }

    // Plan sync operations based on mode
    let operations = try await planSyncOperations(
        diff: diff,
        leftPath: leftPath,
        rightPath: rightPath,
        mode: mode,
        deletions: deletions
    )

    // Execute operations if not in dry-run mode
    if dryRun {
        return SyncResult(
            operations: operations, succeeded: 0, failed: 0, skipped: operations.count)
    } else {
        return try await executeSyncOperations(operations)
    }
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
        return planOneWaySync(diff: diff, leftPath: leftPath, rightPath: rightPath, deletions: deletions)
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
    let left: String? = if let leftBasePath {
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
    let deleteOps = deletions ? diff.onlyInRight.map {
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

    return copyOps + deleteOps + updateOps
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

    return leftToRightOps + rightToLeftOps + conflictOps
}

/// Resolves a conflict between two modified files
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

/// Executes a list of sync operations
private func executeSyncOperations(_ operations: [SyncOperation]) async throws -> SyncResult {
    var succeeded = 0
    var failed = 0
    let skipped = 0

    for operation in operations {
        do {
            try await executeSyncOperation(operation)
            succeeded += 1
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

/// Executes a single sync operation
private func executeSyncOperation(_ operation: SyncOperation) async throws {
    try await Task.detached {
        let fileManager = FileManager.default

        switch operation.type {
        case .copy, .update:
            guard let left = operation.left else {
                throw DirectorySyncError.operationFailed("No left for copy/update operation")
            }

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
            try fileManager.copyItem(atPath: left, toPath: operation.right)

        case .delete:
            // Delete file
            if fileManager.fileExists(atPath: operation.right) {
                try fileManager.removeItem(atPath: operation.right)
            }
        }
    }.value
}
