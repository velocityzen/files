import Foundation

/// A file system operation that failed: what was attempted, on which path, and why
public struct FileSystemError: Error, Sendable, Equatable, LocalizedError,
    CustomStringConvertible
{
    public enum Operation: Sendable, Equatable {
        case readAttributes
        case setAttributes
        case read
        case write
        case list
        case createDirectory
        case copy
        case move
        case remove
    }

    public enum Reason: Sendable, Equatable {
        case notFound
        case permissionDenied
        case alreadyExists
        case notADirectory
        case isADirectory
        case outOfSpace
        case readOnlyVolume
        case other(String)
    }

    public let operation: Operation
    public let path: String
    /// Where the item was going, for copies and moves
    public let destination: String?
    public let reason: Reason

    public init(operation: Operation, path: String, destination: String? = nil, reason: Reason) {
        self.operation = operation
        self.path = path
        self.destination = destination
        self.reason = reason
    }

    public var description: String {
        let target = destination.map { "\(path) to \($0)" } ?? path
        return "Could not \(operation.verb) \(target): \(reason.description)"
    }

    public var errorDescription: String? {
        description
    }
}

extension FileSystemError.Operation {
    fileprivate var verb: String {
        switch self {
            case .readAttributes: "read attributes of"
            case .setAttributes: "set attributes of"
            case .read: "read"
            case .write: "write"
            case .list: "list"
            case .createDirectory: "create directory"
            case .copy: "copy"
            case .move: "move"
            case .remove: "remove"
        }
    }
}

extension FileSystemError.Reason: CustomStringConvertible {
    /// Classifies a Foundation error by its Cocoa code or underlying POSIX code
    init(_ error: any Error) {
        self = Self.classify(error as NSError) ?? .other(error.localizedDescription)
    }

    private static func classify(_ error: NSError) -> Self? {
        if error.domain == NSPOSIXErrorDomain,
            let code = POSIXErrorCode(rawValue: Int32(error.code))
        {
            switch code {
                case .ENOENT: return .notFound
                case .EACCES, .EPERM: return .permissionDenied
                case .EEXIST: return .alreadyExists
                case .ENOTDIR: return .notADirectory
                case .EISDIR: return .isADirectory
                case .ENOSPC, .EDQUOT: return .outOfSpace
                case .EROFS: return .readOnlyVolume
                default: break
            }
        }

        if error.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: error.code) {
                case .fileNoSuchFile, .fileReadNoSuchFile: return .notFound
                case .fileReadNoPermission, .fileWriteNoPermission: return .permissionDenied
                case .fileWriteFileExists: return .alreadyExists
                case .fileWriteOutOfSpace: return .outOfSpace
                case .fileWriteVolumeReadOnly: return .readOnlyVolume
                default: break
            }
        }

        // Generic Cocoa errors often carry the POSIX error that caused them
        return (error.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap(classify)
    }

    public var description: String {
        switch self {
            case .notFound: "no such file or directory"
            case .permissionDenied: "permission denied"
            case .alreadyExists: "an item with that name already exists"
            case .notADirectory: "part of the path is not a directory"
            case .isADirectory: "it is a directory"
            case .outOfSpace: "not enough space"
            case .readOnlyVolume: "the volume is read-only"
            case .other(let message): message
        }
    }
}
