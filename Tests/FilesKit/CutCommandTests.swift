#if canImport(AVFoundation)
import Foundation
import Testing

@testable import FilesKit
@testable import files

@Suite("files cut")
struct CutCommandTests {
    private static let cue = """
        PERFORMER "Кино"
        TITLE "Группа крови"
        FILE "album.flac" WAVE
          TRACK 01 AUDIO
            TITLE "Группа крови"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Закрой за мной дверь, я ухожу"
            INDEX 01 00:01:00
        """

    @Test("Cuts the tracks, refuses to overwrite them, and replaces them with --overwrite")
    func cutAndOverwrite() throws {
        let directory = try makeAlbum(encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dryRun = try TestHelpers.runFiles(["cut", "album.cue", "--dry-run"], in: directory)
        #expect(dryRun.status == 0)
        #expect(dryRun.stderr.contains("DRY RUN"))
        #expect(
            String(decoding: dryRun.stdout, as: UTF8.self)
                == "01 - Группа крови.flac\n02 - Закрой за мной дверь, я ухожу.flac\n")
        #expect(!FileManager.default.fileExists(atPath: path(directory, "01 - Группа крови.flac")))

        let cut = try TestHelpers.runFiles(["cut", "album.cue", "-o", "tracks"], in: directory)
        #expect(cut.status == 0)
        #expect(String(decoding: cut.stdout, as: UTF8.self).contains("Summary: 2 cut, 0 failed"))
        let tracks = try FileManager.default.contentsOfDirectory(
            atPath: path(directory, "tracks"))
        #expect(
            tracks.sorted() == [
                "01 - Группа крови.flac", "02 - Закрой за мной дверь, я ухожу.flac",
            ])

        let again = try TestHelpers.runFiles(["cut", "album.cue", "-o", "tracks"], in: directory)
        #expect(again.status == 1)
        #expect(String(decoding: again.stdout, as: UTF8.self).contains("--overwrite"))

        let overwrite = try TestHelpers.runFiles(
            ["cut", "album.cue", "-o", "tracks", "--overwrite"], in: directory)
        #expect(overwrite.status == 0)
    }

    @Test("Notes a detected legacy encoding on stderr")
    func legacyEncoding() throws {
        let directory = try makeAlbum(encoding: .windowsCP1251)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try TestHelpers.runFiles(["cut", "album.cue", "--dry-run"], in: directory)
        #expect(result.status == 0)
        #expect(result.stderr.contains("Cyrillic"))
        #expect(String(decoding: result.stdout, as: UTF8.self).contains("01 - Группа крови.flac"))

        // An explicit encoding is trusted without a note
        let explicit = try TestHelpers.runFiles(
            ["cut", "album.cue", "--dry-run", "--encoding", "windows-1251"], in: directory)
        #expect(explicit.status == 0)
        #expect(!explicit.stderr.contains("Cyrillic"))
    }

    @Test("Cue sheet errors exit with 2 and bad options with 64")
    func exitCodes() throws {
        let directory = try TestHelpers.createTestDirectory(files: [
            "broken.cue": "TRACK 01 AUDIO\n",
            "silent.cue": "FILE \"gone.flac\" WAVE\nTRACK 01 AUDIO\nINDEX 01 00:00:00\n",
        ])
        defer { try? FileManager.default.removeItem(at: directory) }

        let broken = try TestHelpers.runFiles(["cut", "broken.cue"], in: directory)
        #expect(broken.status == 2)
        #expect(broken.stderr.contains("TRACK before any FILE"))

        let missing = try TestHelpers.runFiles(["cut", "silent.cue"], in: directory)
        #expect(missing.status == 2)
        #expect(missing.stderr.contains("gone.flac"))

        let badEncoding = try TestHelpers.runFiles(
            ["cut", "silent.cue", "--encoding", "klingon"], in: directory)
        #expect(badEncoding.status == 64)
    }

    @Test("Encoding names are IANA charset names")
    func encodingNames() {
        #expect(Files.CutCommand.stringEncoding(named: "windows-1251") == .windowsCP1251)
        // IANA Shift_JIS maps to Apple's Shift JIS rather than .shiftJIS (CP932), which
        // reads the same text
        let shiftJIS = Files.CutCommand.stringEncoding(named: "Shift_JIS")
        let bytes = Data("東京の夜".data(using: .shiftJIS) ?? Data())
        #expect(shiftJIS.flatMap { String(data: bytes, encoding: $0) } == "東京の夜")
        #expect(Files.CutCommand.stringEncoding(named: "utf-8") == .utf8)
        #expect(Files.CutCommand.stringEncoding(named: "klingon") == nil)
    }

    private func makeAlbum(encoding: String.Encoding) throws -> URL {
        let directory = try TestHelpers.createTestDirectory(files: [:])
        try #require(Self.cue.data(using: encoding))
            .write(to: directory.appendingPathComponent("album.cue"))
        try writeAudio(
            AudioFixture(fileExtension: "flac", bits: 16, sampleRate: 44_100, seconds: 2),
            to: directory.appendingPathComponent("album.flac"))
        return directory
    }

    private func path(_ directory: URL, _ name: String) -> String {
        directory.appendingPathComponent(name).path(percentEncoded: false)
    }
}
#endif
