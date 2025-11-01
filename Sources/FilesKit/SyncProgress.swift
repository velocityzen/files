import Foundation

/// Represents the current state of a sync operation
public struct SyncProgress: Sendable {
    public let currentOperation: SyncOperation?
    public let completedOperations: Int
    public let totalOperations: Int
    public let currentFileBytes: Int64
    public let currentFileTotalBytes: Int64
    public let totalBytesTransferred: Int64
    public let totalBytes: Int64
    public let bytesPerSecond: Double

    /// Progress percentage (0.0 to 1.0)
    public var percentage: Double {
        guard totalOperations > 0 else { return 0.0 }
        return Double(completedOperations) / Double(totalOperations)
    }

    /// Current file progress percentage (0.0 to 1.0)
    public var currentFilePercentage: Double {
        guard currentFileTotalBytes > 0 else { return 0.0 }
        return Double(currentFileBytes) / Double(currentFileTotalBytes)
    }

    /// Estimated time remaining in seconds
    public var estimatedTimeRemaining: TimeInterval? {
        guard bytesPerSecond > 0 else { return nil }
        let bytesRemaining = totalBytes - totalBytesTransferred
        return Double(bytesRemaining) / bytesPerSecond
    }

    public init(
        currentOperation: SyncOperation? = nil,
        completedOperations: Int = 0,
        totalOperations: Int = 0,
        currentFileBytes: Int64 = 0,
        currentFileTotalBytes: Int64 = 0,
        totalBytesTransferred: Int64 = 0,
        totalBytes: Int64 = 0,
        bytesPerSecond: Double = 0
    ) {
        self.currentOperation = currentOperation
        self.completedOperations = completedOperations
        self.totalOperations = totalOperations
        self.currentFileBytes = currentFileBytes
        self.currentFileTotalBytes = currentFileTotalBytes
        self.totalBytesTransferred = totalBytesTransferred
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
    }
}

/// Progress handler callback type
public typealias ProgressHandler = @Sendable (SyncProgress) -> Void
