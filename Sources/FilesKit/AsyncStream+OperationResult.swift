/// Extension to simplify error handling in AsyncStream
extension AsyncStream where Element == OperationResult {
    /// Creates a stream that yields a single failure result and finishes
    static func fastFail(leftPath: String, rightPath: String, error: Error, message: String)
        -> AsyncStream<OperationResult>
    {
        return AsyncStream<OperationResult> { continuation in
            let compareOp = FileOperation.compareOperation(
                leftPath: leftPath, rightPath: rightPath, error: message)
            continuation.failure(operation: compareOp, error: error)
            continuation.finish()
        }
    }

    static func flush(operations: [FileOperation]) -> AsyncStream<OperationResult> {
        return AsyncStream<OperationResult> { continuation in
            for operation in operations {
                continuation.success(operation: operation, bytesTransferred: 0)  // No bytes transferred in dry-run
            }
            continuation.finish()
        }
    }
}

/// Extension to add convenience methods for Result-based continuations
extension AsyncStream.Continuation where Element == OperationResult {
    /// Yields a success result with the given operation and bytes transferred
    func success(operation: FileOperation, bytesTransferred: Int64) {
        yield(.success(OperationSuccess(operation: operation, bytesTransferred: bytesTransferred)))
    }

    /// Yields a failure result with the given operation and error
    func failure(operation: FileOperation, error: Error) {
        yield(.failure(OperationError(operation: operation, error: error)))
    }
}
