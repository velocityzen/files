import FP
import FilesKit

/// Status reports for a sync or copy: the route while it runs, each file as it is worked on,
/// and how it ended
struct TransferStatus {
    enum Action {
        case sync
        case copy

        var verb: String {
            switch self {
                case .sync: "sync"
                case .copy: "copy"
            }
        }

        var running: String {
            switch self {
                case .sync: "Syncing"
                case .copy: "Copying"
            }
        }

        var finished: String {
            switch self {
                case .sync: "Synced"
                case .copy: "Copied"
            }
        }
    }

    let action: Action
    /// "Photos → Backup"
    let route: String

    init(_ action: Action, from source: String, to destination: String) {
        self.action = action
        self.route = "\(Status.name(of: source)) → \(Status.name(of: destination))"
    }

    /// Sent before comparing the directories, which can take a while on its own
    func started() {
        Status.working("\(action.running) \(route)")
    }

    /// Reports the file each result is about, once per file. A dry run only plans, so it
    /// reports nothing per file.
    func fileReporter(dryRun: Bool) -> (OperationResult) -> Void {
        guard !dryRun else {
            return { _ in }
        }
        let working = Status.workingOnChange()
        return { result in
            Self.message(for: result.match(\.operation, \.operation)).map(working)
        }
    }

    func finished(_ results: [OperationResult], dryRun: Bool) {
        let failures = results.failedOperations
        let operations = Status.count(results.count, "operation")
        if let failure = failures.first(where: { $0.operation.type == .compare }) {
            // The directories couldn't be compared, so nothing was attempted
            Status.failed(failure.error.localizedDescription)
        } else if !failures.isEmpty {
            Status.failed(
                "\(failures.count) of \(operations) failed \(action.running.lowercased()) \(route)")
        } else if results.isEmpty {
            Status.done("Nothing to \(action.verb): \(route)")
        } else if dryRun {
            Status.done("Dry run: \(operations) to \(action.verb) \(route)")
        } else {
            Status.done("\(action.finished) \(route): \(operations)")
        }
    }

    private static func message(for operation: FileOperation) -> String? {
        switch operation.type {
            case .copy: "Copying \(operation.relativePath)"
            case .update: "Updating \(operation.relativePath)"
            case .delete: "Deleting \(operation.relativePath)"
            case .info, .compare: nil
        }
    }
}
