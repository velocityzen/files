

/// Extension to support async compact map operations
extension Sequence {
    func asyncCompactMap<T>(_ transform: (Element) async throws -> T?) async rethrows -> [T] {
        var result: [T] = []
        for element in self {
            if let transformed = try await transform(element) {
                result.append(transformed)
            }
        }
        return result
    }
}
