import FilesKit
import Foundation
import ProgramStatus

/// Tells the terminal what files is doing with the Program Status Protocol (OSC 7501), so a
/// terminal that supports it can show progress on the tab and notify when a long sync, copy
/// or cut finishes. Terminals that don't know the protocol ignore the reports.
///
/// Reports go to the controlling terminal, never into redirected output. `FILES_STATUS=off`
/// turns them off, and `FILES_STATUS=<file>` appends them to a file instead. Sending is
/// best-effort: a report that can't be sent is dropped.
enum Status {
    static let environmentKey = "FILES_STATUS"

    private static let reporter = makeReporter(
        ProcessInfo.processInfo.environment[environmentKey])

    static func working(_ message: String, progress: Int? = nil) {
        send(.working(StatusText.singleLine(message), progress: progress))
    }

    /// Finished; sent right before exiting, so the result stays on the terminal
    static func done(_ message: String) {
        send(.done(StatusText.singleLine(message)))
    }

    /// Failed and stopped; sent right before exiting, so the result stays on the terminal
    static func failed(_ message: String) {
        send(.error(StatusText.singleLine(message)))
    }

    /// A `working` sender that skips repeats, for streams that report one file many times
    static func workingOnChange() -> (String) -> Void {
        var last: String?
        return { message in
            guard message != last else {
                return
            }
            last = message
            working(message)
        }
    }

    /// "Compared A and B: 3 differences"
    static func comparison(_ diff: DirectoryDifference, of subject: String) -> String {
        let differences = diff.onlyInLeft.count + diff.onlyInRight.count + diff.modified.count
        let summary = differences == 0 ? "no differences" : count(differences, "difference")
        return "Compared \(subject): \(summary)"
    }

    /// How a path is named in reports: its last component, with "." resolved to a name
    static func name(of path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.lastPathComponent
    }

    /// "1 track", "2 tracks"
    static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }

    /// The reporter for a `FILES_STATUS` value: none for "off", a file for a path, and the
    /// terminal otherwise
    static func makeReporter(_ setting: String?) -> ProgramStatusReporter? {
        switch setting {
            case "off":
                nil
            case let path? where !path.isEmpty:
                appending(to: path).map {
                    ProgramStatusReporter(app: "files", destination: .fileHandle($0))
                }
            default:
                ProgramStatusReporter(app: "files")
        }
    }

    private static func send(_ report: StatusReport) {
        _ = reporter?.send(report)
    }

    /// Opens a file for appending, creating it if needed, so several runs can share one log
    private static func appending(to path: String) -> FileHandle? {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        return descriptor < 0 ? nil : FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}
