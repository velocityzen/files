import FP
import Foundation

/// The Vorbis comment block of a FLAC file: the encoder's vendor string and "KEY=value" fields
struct VorbisComments: Sendable, Equatable {
    var vendor: String
    var comments: [String]

    init(vendor: String, comments: [String]) {
        self.vendor = vendor
        self.comments = comments
    }

    init(vendor: String, fields: [(key: String, value: String)]) {
        self.init(vendor: vendor, comments: fields.map { "\($0.key)=\($0.value)" })
    }

    /// Little-endian lengths: the vendor, the comment count, then each comment
    var encoded: Data {
        Self.lengthPrefixed(vendor) + Self.littleEndian(comments.count)
            + comments.map(Self.lengthPrefixed).reduce(Data(), +)
    }

    /// Decodes a block body; nil if the lengths run past the end
    static func decode(_ body: Data) -> VorbisComments? {
        guard let vendor = string(in: body, at: body.startIndex),
            let count = length(in: body, at: vendor.end)
        else {
            return nil
        }
        // Read strings back to back until the count is reached or one runs past the end
        let comments = Array(
            sequence(state: count.end) { offset in
                string(in: body, at: offset).map { comment in
                    offset = comment.end
                    return comment.value
                }
            }
            .prefix(count.value))
        guard comments.count == count.value else {
            return nil
        }
        return VorbisComments(vendor: vendor.value, comments: comments)
    }

    private static func lengthPrefixed(_ string: String) -> Data {
        let bytes = Data(string.utf8)
        return littleEndian(bytes.count) + bytes
    }

    private static func littleEndian(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) }
    }

    private static func length(in data: Data, at offset: Int) -> (value: Int, end: Int)? {
        guard offset + 4 <= data.endIndex else {
            return nil
        }
        let value = data[offset..<offset + 4].enumerated().reduce(0) { result, byte in
            result | Int(byte.element) << (8 * byte.offset)
        }
        return (value, offset + 4)
    }

    private static func string(in data: Data, at offset: Int) -> (value: String, end: Int)? {
        guard let length = length(in: data, at: offset), length.end + length.value <= data.endIndex
        else {
            return nil
        }
        let bytes = data[length.end..<length.end + length.value]
        return (String(decoding: bytes, as: UTF8.self), length.end + length.value)
    }
}
