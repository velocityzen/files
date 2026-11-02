import FP
import FPBracket
import Foundation

/// Reads and replaces the Vorbis comments of a FLAC file
enum FLACTags {
    /// Padding left after metadata that had to be rewritten, so later tag changes, by this
    /// or any other tagger, fit in place
    static let rewritePadding = 8 * 1024

    static func read(at path: String) -> Result<VorbisComments, FLACTagsError> {
        contents(of: path)
            .flatMap { FLACMetadata.parse($0, path: path) }
            .flatMap { $0.comments(path: path) }
    }

    /// Replaces all comments with `fields`, keeping the encoder's vendor string
    ///
    /// New metadata that fits where the old was, its padding included, is written over it in
    /// place, so the audio is left alone. Otherwise the file is rewritten next to itself, with
    /// `rewritePadding` after the metadata, and moved into place.
    static func write(_ fields: [(key: String, value: String)], to path: String) -> Result<
        Void, FLACTagsError
    > {
        contents(of: path)
            .flatMap { FLACMetadata.parse($0, path: path) }
            .map { $0.replacingComments(with: fields) }
            .flatMap { metadata in
                guard let fitted = metadata.fitted(to: metadata.audioOffset) else {
                    return rewrite(path, with: metadata.padded(by: rewritePadding))
                }
                return fitted.encodedHeader(path: path).flatMap { writeInPlace($0, to: path) }
            }
    }

    /// The file mapped, not read: parsing only touches the metadata at its start
    private static func contents(of path: String) -> Result<Data, FLACTagsError> {
        fileContents(at: path, options: .alwaysMapped).mapError(FLACTagsError.fileSystem)
    }

    private static func writeInPlace(_ header: Data, to path: String) -> Result<
        Void, FLACTagsError
    > {
        let withFile = openForUpdating(path)
        return withFile { $0.writeChunk(header) }.mapError(FLACTagsError.fileSystem)
    }

    /// Writes the new metadata to a file next to the old one, copies the audio frames after
    /// it, and moves it into place
    private static func rewrite(_ path: String, with metadata: FLACMetadata) -> Result<
        Void, FLACTagsError
    > {
        let withTemporaryFile = temporaryFile(nextTo: path)
        return metadata.encodedHeader(path: path).flatMap { header in
            withTemporaryFile { temporary in
                let files = openForReading(path).flatMap { input in
                    createForWriting(temporary).map { output in (input, output) }
                }
                return files { input, output in
                    input.seek(to: metadata.audioOffset)
                        .flatMap { _ in output.writeChunk(header) }
                        .flatMap { _ in copyContents(from: input, to: output) }
                }
                .flatMap { _ in moveReplacingItem(at: temporary, to: path) }
            }
            .mapError(FLACTagsError.fileSystem)
        }
    }
}
