import FP
import Foundation

public enum FLACTagsError: Error, Sendable, Equatable, LocalizedError {
    case fileSystem(FileSystemError)
    case notFLAC(String)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
            case .fileSystem(let error): error.localizedDescription
            case .notFLAC(let path): "Not a FLAC file: \(path)"
            case .malformed(let path): "Malformed FLAC metadata in \(path)"
        }
    }
}

/// The metadata blocks at the start of a FLAC file, and where its audio frames begin
struct FLACMetadata: Equatable {
    struct Block: Equatable {
        var type: UInt8
        var body: Data
    }

    static let marker = Data("fLaC".utf8)
    private static let streamInfoType: UInt8 = 0
    private static let paddingType: UInt8 = 1
    private static let vorbisCommentType: UInt8 = 4
    /// A block's length is stored in 24 bits
    private static let maximumBlockLength = 1 << 24

    let blocks: [Block]
    let audioOffset: Int

    /// A block as it sits in the file
    private struct Located {
        let block: Block
        let isLast: Bool
        let end: Int
    }

    static func parse(_ data: Data, path: String) -> Result<FLACMetadata, FLACTagsError> {
        guard data.prefix(4) == marker else {
            return .failure(.notFLAC(path))
        }
        // Each header says whether another block follows; stop after the last one or the
        // first that can't be read
        let located = sequence(first: block(in: data, at: data.startIndex + 4, path: path)) {
            previous in
            guard case .success(let block) = previous, !block.isLast else {
                return nil
            }
            return Self.block(in: data, at: block.end, path: path)
        }
        return Array(located).traverse { $0 }.flatMap { metadata(from: $0, path: path) }
    }

    private static func block(in data: Data, at offset: Int, path: String) -> Result<
        Located, FLACTagsError
    > {
        guard offset + 4 <= data.endIndex else {
            return .failure(.malformed(path))
        }
        let header = data[offset]
        let length =
            Int(data[offset + 1]) << 16 | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
        let end = offset + 4 + length
        guard end <= data.endIndex else {
            return .failure(.malformed(path))
        }
        let block = Block(type: header & 0x7F, body: Data(data[offset + 4..<end]))
        return .success(Located(block: block, isLast: header & 0x80 != 0, end: end))
    }

    private static func metadata(from located: [Located], path: String) -> Result<
        FLACMetadata, FLACTagsError
    > {
        guard located.first?.block.type == streamInfoType, let last = located.last else {
            return .failure(.malformed(path))
        }
        return .success(FLACMetadata(blocks: located.map(\.block), audioOffset: last.end))
    }

    /// The Vorbis comments, or none if the file has no comment block
    func comments(path: String) -> Result<VorbisComments, FLACTagsError> {
        guard let block = blocks.first(where: { $0.type == Self.vorbisCommentType }) else {
            return .success(VorbisComments(vendor: "", comments: []))
        }
        return .fromOptional(VorbisComments.decode(block.body), error: .malformed(path))
    }

    /// Replaces every comment block with one holding `fields`, keeping the encoder's vendor
    /// string and the block's place, or putting it right after STREAMINFO, which must stay first
    func replacingComments(with fields: [(key: String, value: String)]) -> FLACMetadata {
        let vendor = comments(path: "").map(\.vendor).getOrElse("")
        let block = Block(
            type: Self.vorbisCommentType,
            body: VorbisComments(vendor: vendor, fields: fields).encoded)
        let position = blocks.firstIndex { $0.type == Self.vorbisCommentType } ?? 1
        let others = blocks.filter { $0.type != Self.vorbisCommentType }
        return FLACMetadata(
            blocks: Array(others.prefix(position)) + [block] + others.dropFirst(position),
            audioOffset: audioOffset)
    }

    /// The same blocks with their padding resized so the marker and blocks take exactly
    /// `size` bytes, to be written over metadata of that size in place, or nil if they don't
    /// fit. Padding needs four bytes for its own header, so 1 to 3 spare bytes don't fit
    /// either, and no more than one block holds.
    func fitted(to size: Int) -> FLACMetadata? {
        let spare = size - Self.encodedSize(of: unpadded)
        if spare == 0 {
            return FLACMetadata(blocks: unpadded, audioOffset: audioOffset)
        }
        return (4..<4 + Self.maximumBlockLength).contains(spare) ? padded(by: spare - 4) : nil
    }

    /// The same blocks followed by one padding block of `length` bytes, room for later tag
    /// changes to be written in place
    func padded(by length: Int) -> FLACMetadata {
        let padding = Block(type: Self.paddingType, body: Data(count: length))
        return FLACMetadata(blocks: unpadded + [padding], audioOffset: audioOffset)
    }

    /// Every block but padding
    private var unpadded: [Block] {
        blocks.filter { $0.type != Self.paddingType }
    }

    private static func encodedSize(of blocks: [Block]) -> Int {
        blocks.reduce(marker.count) { size, block in size + 4 + block.body.count }
    }

    /// The marker and blocks, ready to be followed by the audio frames
    func encodedHeader(path: String) -> Result<Data, FLACTagsError> {
        Array(blocks.enumerated())
            .traverse { index, block in
                Self.encode(block, isLast: index == blocks.count - 1, path: path)
            }
            .map { Self.marker + $0.reduce(Data(), +) }
    }

    private static func encode(_ block: Block, isLast: Bool, path: String) -> Result<
        Data, FLACTagsError
    > {
        let length = block.body.count
        guard length < maximumBlockLength else {
            return .failure(.malformed(path))
        }
        let header: [UInt8] = [
            (isLast ? 0x80 : 0) | block.type,
            UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF),
        ]
        return .success(Data(header) + block.body)
    }
}
