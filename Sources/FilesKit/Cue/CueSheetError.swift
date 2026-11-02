import Foundation

public enum CueSheetError: Error, Sendable, Equatable, LocalizedError {
    case unreadable(String)
    case unknownEncoding(String)
    case invalidTime(line: Int, String)
    case invalidTrackNumber(line: Int, String)
    case trackOutsideFile(line: Int)
    case indexOutsideTrack(line: Int)
    case noTracks
    case missingStart(track: Int)
    case tracksOutOfOrder(track: Int)
    case missingAudioFile(String)
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
            case .unreadable(let path):
                "Could not read cue sheet \(path)"
            case .unknownEncoding(let path):
                "Could not detect the text encoding of \(path); pass --encoding"
            case .invalidTime(let line, let text):
                "Line \(line): invalid time '\(text)', expected mm:ss:ff"
            case .invalidTrackNumber(let line, let text):
                "Line \(line): invalid track number '\(text)'"
            case .trackOutsideFile(let line):
                "Line \(line): TRACK before any FILE"
            case .indexOutsideTrack(let line):
                "Line \(line): INDEX before any TRACK"
            case .noTracks:
                "The cue sheet has no tracks"
            case .missingStart(let track):
                "Track \(track) has no INDEX 01"
            case .tracksOutOfOrder(let track):
                "Track \(track) starts before the track it follows"
            case .missingAudioFile(let name):
                "Audio file \(name) not found next to the cue sheet"
            case .unsupportedFormat(let path):
                "Unsupported audio format: \(path) (supported: flac, wav, aiff, ape, wv)"
        }
    }
}
