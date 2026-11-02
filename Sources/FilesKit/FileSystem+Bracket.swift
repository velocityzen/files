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

/// What every temporary file's name has, so one left by an interrupted run can be told apart
let temporaryFileMarker = ".files-tmp"

/// A hidden path next to `destination` to build a file at before moving it into place.
/// Whatever is left there is removed when the scope ends, so a failed write never leaves a
/// partial file behind.
///
/// The name is a UUID and `temporaryFileMarker`, then the destination's extension, which
/// AVAudioFile picks the format from. It leaves out the destination's own name, which can
/// already be as long as a name can be; the extension is dropped too when it doesn't fit.
func temporaryFile(nextTo destination: String) -> Bracket<String, FileSystemError> {
    let url = URL(fileURLWithPath: destination)
    let name = ".\(UUID().uuidString)\(temporaryFileMarker)"
    let fileExtension = url.pathExtension
    let fits = name.utf8.count + 1 + fileExtension.utf8.count <= Int(NAME_MAX)
    let path = url.deletingLastPathComponent()
        .appending(path: fileExtension.isEmpty || !fits ? name : "\(name).\(fileExtension)")
        .path(percentEncoded: false)
    return Bracket(
        acquire: { .success(path) },
        dispose: { path in
            // Usually the file was moved into place and is gone. One unlink tells, where
            // FileManager would also build an error to say so, five times the cost.
            _ = unlink(path)
            return .success(())
        }
    )
}

/// A file opened for reading, closed when the scope ends
func openForReading(_ path: String) -> Bracket<OpenFile, FileSystemError> {
    Bracket(
        acquire: { openFileDescriptor(forReadingAt: path) },
        dispose: closeFileDescriptor
    )
}

/// A new file opened for writing, closed when the scope ends. Anything already at the path,
/// a symbolic link included, fails it, so the bytes never go to some other file.
func createForWriting(_ path: String) -> Bracket<OutputFile, FileSystemError> {
    Bracket(
        acquire: { createFileDescriptor(forWritingAt: path) },
        dispose: closeFileDescriptor
    )
}

/// An existing file opened to write over its bytes in place, closed when the scope ends
func openForUpdating(_ path: String) -> Bracket<OutputFile, FileSystemError> {
    Bracket(
        acquire: { openFileDescriptor(forUpdatingAt: path) },
        dispose: closeFileDescriptor
    )
}

/// Cleanup is best effort: a failed removal must not replace the outcome of the scope
private func discardingFailure(
    _ cleanup: @escaping (String) -> Result<Void, FileSystemError>
) -> (String) -> Result<Void, FileSystemError> {
    { path in cleanup(path).orElse { _ in .success(()) } }
}
