import FilesKit
import Foundation

/// Formats and displays progress information for sync operations
actor ProgressFormatter {
    private var lastUpdateTime: Date = Date()
    private let updateInterval: TimeInterval = 0.1  // Update every 100ms
    private var lastCompletedCount = 0
    private var lastOperation: SyncOperation? = nil

    func display(_ progress: SyncProgress) {
        // Check if a file just completed
        if progress.completedOperations > lastCompletedCount {
            // Clear the progress line first
            print("\r\u{001B}[K", terminator: "")

            // Print the completed file(s)
            if let operation = lastOperation {
                OutputFormatter.printOperation(operation)
            }
            lastCompletedCount = progress.completedOperations
        }

        // Store current operation for next completion
        if let operation = progress.currentOperation {
            lastOperation = operation
        }

        // Throttle progress line updates to avoid flickering
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= updateInterval else {
            return
        }
        lastUpdateTime = now

        // Move cursor to beginning of line and clear it
        print("\r\u{001B}[K", terminator: "")

        // Overall progress line
        let overallPercentage = Int(progress.percentage * 100)
        let transferred = formatBytes(progress.totalBytesTransferred)
        let total = formatBytes(progress.totalBytes)
        let speed = formatBytes(Int64(progress.bytesPerSecond)) + "/s"

        var eta = ""
        if let remaining = progress.estimatedTimeRemaining {
            eta = " ETA: \(formatDuration(remaining))"
        }

        print(
            "[\(overallPercentage)%] \(progress.completedOperations)/\(progress.totalOperations) files - \(transferred)/\(total) - \(speed)\(eta)",
            terminator: "")

        try? FileHandle.standardOutput.synchronize()
    }

    func complete() {
        print()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}
