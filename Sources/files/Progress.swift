import FilesKit
import Foundation

/// Creates a progress printer that replaces the line if it's for the same file
func getPrintProgress(_ isMute: Bool = false) -> (OperationResult) -> Void {
    if isMute {
        return { _ in }
    }

    var previousOperation: FileOperation?
    return { result in
        switch result {
            case .success(let success):
                if previousOperation == success.operation {
                    // Same file, replace the line
                    print("\r\u{001B}[K", terminator: "")
                } else {
                    print()
                }

                print(
                    " \(success.operation.type) \(success.operation.relativePath)", terminator: "")

                // Show progress for operations with bytes transferred
                if success.bytesTransferred > 0 {
                    let bytesStr = formatBytes(success.bytesTransferred)
                    print(" (\(bytesStr))", terminator: "")
                }

                previousOperation = success.operation

            case .failure(let failure):
                if previousOperation == failure.operation {
                    // Same file, replace the line
                    print("\r\u{001B}[K", terminator: "")
                } else {
                    print()
                }

                print(
                    " \(failure.operation.type) \(failure.operation.relativePath)", terminator: "")
                print(" ❌ \(failure.error.localizedDescription)")

                previousOperation = failure.operation
        }

        //  `fflush` call is thread-safe in practice
        nonisolated(unsafe) let stdoutPtr = stdout
        fflush(stdoutPtr)
    }
}

/// Formats bytes into a human-readable string
private func formatBytes(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var size = Double(bytes)
    var unitIndex = 0

    while size >= 1024 && unitIndex < units.count - 1 {
        size /= 1024
        unitIndex += 1
    }

    if unitIndex == 0 {
        return "\(Int(size)) \(units[unitIndex])"
    } else {
        return String(format: "%.2f %@", size, units[unitIndex])
    }
}
