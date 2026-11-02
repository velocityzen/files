import Foundation
import Testing

@testable import FilesKit

@Suite("FLAC metadata")
struct FLACMetadataTests {
    private static let streamInfo = (type: UInt8(0), body: Data(repeating: 7, count: 34))
    private static let padding = (type: UInt8(1), body: Data(count: 16))
    private static let audio = Data("AUDIO FRAMES".utf8)

    @Test("Vorbis comments survive encoding and reject truncated bodies")
    func vorbisComments() {
        let comments = VorbisComments(
            vendor: "encoder", fields: [(key: "TITLE", value: "Новое"), (key: "DATE", value: "")])
        #expect(VorbisComments.decode(comments.encoded) == comments)
        #expect(VorbisComments.decode(comments.encoded.dropLast()) == nil)
        #expect(VorbisComments.decode(Data()) == nil)
    }

    @Test("Finds the blocks and where the audio starts")
    func parsing() throws {
        let comments = VorbisComments(vendor: "encoder", comments: ["TITLE=One"])
        let file = flac([Self.streamInfo, (4, comments.encoded), Self.padding])

        let metadata = try FLACMetadata.parse(file, path: "a.flac").get()
        #expect(metadata.blocks.map(\.type) == [0, 4, 1])
        #expect(file[metadata.audioOffset...] == Self.audio)
        #expect(try metadata.comments(path: "a.flac").get() == comments)
    }

    @Test("Rejects files that aren't FLAC or whose blocks don't add up")
    func malformed() {
        #expect(FLACMetadata.parse(Data("RIFF....".utf8), path: "a") == .failure(.notFLAC("a")))
        // A header claiming more bytes than the file has
        #expect(
            FLACMetadata.parse(FLACMetadata.marker + Data([0x80, 0, 1, 0]), path: "a")
                == .failure(.malformed("a")))
        // STREAMINFO must come first
        #expect(
            FLACMetadata.parse(flac([Self.padding, Self.streamInfo]), path: "a")
                == .failure(.malformed("a")))
    }

    @Test("New comments keep the vendor and the block's place")
    func replacing() throws {
        let old = VorbisComments(vendor: "encoder", comments: ["TITLE=Old", "ARTIST=Gone"])
        let file = flac([Self.streamInfo, Self.padding, (4, old.encoded)])

        let metadata = try FLACMetadata.parse(file, path: "a.flac").get()
            .replacingComments(with: [(key: "TITLE", value: "New")])
        let rewritten =
            try metadata.encodedHeader(path: "a.flac").get() + file[metadata.audioOffset...]

        let reparsed = try FLACMetadata.parse(rewritten, path: "a.flac").get()
        #expect(reparsed.blocks.map(\.type) == [0, 1, 4])
        #expect(
            try reparsed.comments(path: "a.flac").get()
                == VorbisComments(vendor: "encoder", comments: ["TITLE=New"]))
        #expect(rewritten[reparsed.audioOffset...] == Self.audio)
    }

    @Test("Without a comment block, one is added right after STREAMINFO")
    func adding() throws {
        let metadata = try FLACMetadata.parse(
            flac([Self.streamInfo, Self.padding]), path: "a.flac"
        )
        .get()
        #expect(try metadata.comments(path: "a.flac").get().comments.isEmpty)

        let tagged = metadata.replacingComments(with: [(key: "TITLE", value: "One")])
        #expect(tagged.blocks.map(\.type) == [0, 4, 1])
        #expect(try tagged.comments(path: "a.flac").get().comments == ["TITLE=One"])
    }

    /// A FLAC file with these metadata blocks followed by fake audio
    private func flac(_ blocks: [(type: UInt8, body: Data)]) -> Data {
        let encoded = blocks.enumerated().map { index, block in
            let length = block.body.count
            let header: [UInt8] = [
                (index == blocks.count - 1 ? 0x80 : 0) | block.type,
                UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF),
            ]
            return Data(header) + block.body
        }
        return FLACMetadata.marker + encoded.reduce(Data(), +) + Self.audio
    }
}
