import Foundation

public enum CueCutError: Error, Sendable, Equatable, LocalizedError {
    case outputExists(String)
    case outputIsSource(String)
    case startPastEnd(track: Int)
    case unsupportedAudio(String)
    case audio(path: String, reason: String)
    case fileSystem(FileSystemError)
    case tags(FLACTagsError)
    case ffmpegNotFound(String)
    case ffmpegFailed(String, String)

    public var errorDescription: String? {
        switch self {
            case .outputExists(let path):
                "\((path as NSString).lastPathComponent) already exists; pass --overwrite to replace it"
            case .outputIsSource(let path):
                "\(path) is a source of this cue sheet and won't be overwritten"
            case .startPastEnd(let track):
                "Track \(track) starts past the end of its audio file"
            case .unsupportedAudio(let path):
                "Can't cut \(path) losslessly: unsupported encoding or bit depth"
            case .audio(let path, let reason):
                "Could not process the audio in \(path): \(reason)"
            case .fileSystem(let error):
                error.localizedDescription
            case .tags(let error):
                error.localizedDescription
            case .ffmpegNotFound(let path):
                "\(path) needs ffmpeg to decode; install it with `brew install ffmpeg`"
            case .ffmpegFailed(let path, let message):
                "ffmpeg could not decode \(path): \(message)"
        }
    }
}

/// A track that was cut and written
public struct CueTrackOutput: Sendable, Equatable {
    public let track: CueTrack
    /// Where the track was written
    public let path: String
    /// Length in sample frames
    public let frames: Int64
}

/// A track that could not be cut
public struct CueTrackError: Error, Sendable, Equatable, LocalizedError {
    public let track: CueTrack
    public let error: CueCutError

    public var errorDescription: String? {
        error.localizedDescription
    }
}

/// The outcome of cutting one track
public typealias CueTrackResult = Result<CueTrackOutput, CueTrackError>
