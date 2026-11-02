import FP
import Foundation

/// Reads and replaces the Vorbis comments of a FLAC file
enum FLACTags {
    static func read(at path: String) -> Result<VorbisComments, FLACTagsError> {
        contents(of: path)
            .flatMap { FLACMetadata.parse($0, path: path) }
            .flatMap { $0.comments(path: path) }
    }

    /// Replaces all comments with `fields`, keeping the encoder's vendor string
    static func write(_ fields: [(key: String, value: String)], to path: String) -> Result<
        Void, FLACTagsError
    > {
        contents(of: path)
            .bind { FLACMetadata.parse($0, path: path) }
            .bind { _, metadata in
                metadata.replacingComments(with: fields).encodedHeader(path: path)
            }
            .map { data, metadata, header in header + data[metadata.audioOffset...] }
            .flatMap { save($0, to: path) }
    }

    private static func contents(of path: String) -> Result<Data, FLACTagsError> {
        fileContents(at: path, options: .alwaysMapped).mapError(FLACTagsError.fileSystem)
    }

    private static func save(_ data: Data, to path: String) -> Result<Void, FLACTagsError> {
        writeFile(data, to: path, options: .atomic).mapError(FLACTagsError.fileSystem)
    }
}
