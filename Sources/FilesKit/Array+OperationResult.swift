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

    public var failedOperations: [(operation: FileOperation, error: Error)] {
        compactMap {
            if case .failure(let opError) = $0 {
                return (opError.operation, opError.error)
            }
            return nil
        }
    }

    public var operations: [FileOperation] {
        map { result in
            switch result {
                case .success(let success): return success.operation
                case .failure(let failure): return failure.operation
            }
        }
    }
}
