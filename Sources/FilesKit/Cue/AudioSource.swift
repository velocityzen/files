import FP
import Foundation

/// An audio file that tracks are cut from, found next to the cue sheet
struct AudioSource: Sendable, Equatable {
    /// Audio extensions that can be cut, in the order a missing source is looked for
    static let extensions = ["flac", "wav", "aiff", "aif", "ape", "wv"]

    let path: String
    /// FLAC, WAV and AIFF keep their format; APE and WavPack become FLAC
    let outputExtension: String

    /// Finds the audio file a FILE line names
    /// - Parameter isOnlyFile: Whether the sheet has a single FILE, which may then also be
    ///   named like the cue sheet itself
    static func resolve(_ name: String, cuePath: String, isOnlyFile: Bool) -> Result<
        AudioSource, CueSheetError
    > {
        let found = candidates(for: name, cuePath: cuePath, isOnlyFile: isOnlyFile)
            .first(where: regularFileExists(at:))
        return Result.fromOptional(found, error: CueSheetError.missingAudioFile(name))
            .flatMap(make)
    }

    static func make(path: String) -> Result<AudioSource, CueSheetError> {
        Result.fromOptional(outputExtension(forSource: path), error: .unsupportedFormat(path))
            .map { AudioSource(path: path, outputExtension: $0) }
    }

    private static func outputExtension(forSource path: String) -> String? {
        let pathExtension = (path as NSString).pathExtension.lowercased()
        return switch pathExtension {
            case "flac", "wav", "aiff", "aif": pathExtension
            case "ape", "wv": "flac"
            default: nil
        }
    }

    /// Where the audio may be, best match first. Rips are often re-encoded after the cue
    /// sheet was written, so the same name with another audio extension also counts. Cue
    /// sheets written on Windows can hold backslashes and absolute paths.
    private static func candidates(for name: String, cuePath: String, isOnlyFile: Bool)
        -> [String]
    {
        let directory = (cuePath as NSString).deletingLastPathComponent
        let name = name.replacing("\\", with: "/")
        let named =
            (name.hasPrefix("/") ? [] : [name]) + [(name as NSString).lastPathComponent]
        let cueNamed =
            isOnlyFile
            ? [((cuePath as NSString).lastPathComponent as NSString).deletingPathExtension] : []

        let exact = named.map { (directory as NSString).appendingPathComponent($0) }
        let stems = (named + cueNamed).map {
            ((directory as NSString).appendingPathComponent($0) as NSString)
                .deletingPathExtension
        }
        return exact + stems.flatMap { stem in extensions.map { "\(stem).\($0)" } }
    }
}
