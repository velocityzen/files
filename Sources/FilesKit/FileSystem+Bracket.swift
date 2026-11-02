import FP
import FPBracket
import Foundation

/// A new directory in the system temporary directory, removed with its contents when the
/// scope ends
func temporaryDirectory(prefix: String) -> Bracket<String, FileSystemError> {
    let path = URL.temporaryDirectory.appending(path: "\(prefix)-\(UUID().uuidString)")
        .path(percentEncoded: false)
    return Bracket(
        acquire: { createDirectory(at: path).as(path) },
        dispose: discardingFailure(removeItemIfPresent)
    )
}

/// A hidden path next to `destination` to build a file at before moving it into place. It
/// keeps the destination's extension, and whatever is left there is removed when the scope
/// ends, so a failed write never leaves a partial file behind.
func temporaryFile(nextTo destination: String) -> Bracket<String, FileSystemError> {
    let url = URL(fileURLWithPath: destination)
    let path = url.deletingLastPathComponent()
        .appending(path: ".\(UUID().uuidString).\(url.pathExtension)")
        .path(percentEncoded: false)
    return Bracket(
        acquire: { .success(path) },
        dispose: discardingFailure(removeItemIfPresent)
    )
}

/// Cleanup is best effort: a failed removal must not replace the outcome of the scope
private func discardingFailure(
    _ cleanup: @escaping (String) -> Result<Void, FileSystemError>
) -> (String) -> Result<Void, FileSystemError> {
    { path in cleanup(path).orElse { _ in .success(()) } }
}
