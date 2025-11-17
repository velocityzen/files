import FilesKit
import Foundation

/// Creates a progress printer that replaces the line if it's for the same file
func getPrintProgress(_ isMute: Bool = false) -> (OperationResult) -> Void {
    if isMute {
        return { _ in }
    }

    var previousOperation: FileOperation?
    return { result in
        let operation =
            switch result {
                case .success(let success): success.operation
                case .failure(let failure): failure.operation
            }

        if previousOperation == operation {
            // Same file, replace the line
            print("\r\u{001B}[K", terminator: "")
        }

        OutputFormatter.printOperation(operation)

        // Print error if the operation failed
        if case .failure(let failure) = result {
            print("  Error: \(failure.error.localizedDescription)")
        }

        previousOperation = operation
    }
}
