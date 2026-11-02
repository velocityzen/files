import FP
import Foundation
import Testing

@testable import FilesKit

@Suite("Cue track planning")
struct CueTrackPlanTests {
    private static let threeTracks = """
        PERFORMER "The Band"
        TITLE "Album"
        REM DATE 1999
        REM GENRE Rock
        FILE "album.wav" WAVE
          TRACK 01 AUDIO
            TITLE "Intro"
            INDEX 00 00:00:00
            INDEX 01 00:00:32
          TRACK 02 AUDIO
            TITLE "Song: Two?"
            PERFORMER "Guest"
            SONGWRITER "Writer"
            INDEX 00 01:58:00
            INDEX 01 02:00:00
          TRACK 03 AUDIO
            PERFORMER "The Band"
            INDEX 01 03:00:00
        """

    @Test("Tracks run from INDEX 01 to the next INDEX 01; the first starts at 0")
    func ranges() throws {
        let (tracks, directory) = try plan(Self.threeTracks, audio: ["album.flac"])
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(
            tracks.map(\.start) == [CueTime(frames: 0), CueTime("02:00:00"), CueTime("03:00:00")])
        #expect(tracks.map(\.end) == [CueTime("02:00:00"), CueTime("03:00:00"), nil])
        // album.wav was re-encoded to FLAC after the cue sheet was written
        #expect(tracks.allSatisfy { $0.source.hasSuffix("/album.flac") })
    }

    @Test("Names tracks NN - Title and adds a performer only when it differs")
    func names() throws {
        let (tracks, directory) = try plan(Self.threeTracks, audio: ["album.flac"])
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(
            tracks.map(\.fileName) == [
                "01 - Intro.flac",
                "02 - Guest - Song_ Two_.flac",
                "03 - Track 03.flac",
            ])
    }

    @Test("Tags come from the track, falling back to the album")
    func tags() throws {
        let (tracks, directory) = try plan(Self.threeTracks, audio: ["album.flac"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let second = tracks[1].tags
        #expect(second.title == "Song: Two?")
        #expect(second.artist == "Guest")
        #expect(second.albumArtist == "The Band")
        #expect(second.album == "Album")
        #expect(second.composer == "Writer")
        #expect(second.date == "1999")
        #expect(second.genre == "Rock")
        #expect(second.trackNumber == 2)
        #expect(second.trackTotal == 3)

        #expect(tracks[0].tags.artist == "The Band")
        #expect(tracks[2].tags.title == nil)
        #expect(tracks[2].tags.vorbisComments.contains { $0.key == "TITLE" } == false)
    }

    @Test("Across files, a track ends with its file and the next file starts at 0")
    func multipleFiles() throws {
        let (tracks, directory) = try plan(
            """
            FILE "01.wav" WAVE
              TRACK 01 AUDIO
                INDEX 01 00:00:00
              TRACK 02 AUDIO
                INDEX 00 04:10:00
            FILE "02.wav" WAVE
                INDEX 01 00:00:00
              TRACK 03 AUDIO
                INDEX 01 03:00:00
            """, audio: ["01.wav", "02.wav"])
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(
            tracks.map { ($0.source as NSString).lastPathComponent } == [
                "01.wav", "02.wav", "02.wav",
            ])
        #expect(tracks[0].end == nil)
        #expect(tracks[1].start == CueTime(frames: 0))
        #expect(tracks[1].end == CueTime("03:00:00"))
        #expect(tracks[1].fileName == "02 - Track 02.wav")
    }

    @Test("Finds the audio by the cue's own name, or by the last path component")
    func sourceResolution() throws {
        let single = """
            FILE "Something Else.wav" WAVE
              TRACK 01 AUDIO
                INDEX 01 00:00:00
            """
        let (byCueName, first) = try plan(single, audio: ["album.ape"])
        defer { try? FileManager.default.removeItem(at: first) }
        #expect(byCueName[0].source.hasSuffix("/album.ape"))
        // APE is written as FLAC
        #expect(byCueName[0].fileName == "01 - Track 01.flac")

        let windowsPath = """
            FILE "C:\\Rips\\Image.wv" WAVE
              TRACK 01 AUDIO
                INDEX 01 00:00:00
            """
        let (byComponent, second) = try plan(windowsPath, audio: ["Image.wv"])
        defer { try? FileManager.default.removeItem(at: second) }
        #expect(byComponent[0].source.hasSuffix("/Image.wv"))
    }

    @Test("Reports missing audio, unsupported formats and bad track order")
    func planErrors() throws {
        let missing = try writeAlbum(
            "FILE \"gone.flac\" WAVE\nTRACK 01 AUDIO\nINDEX 01 00:00:00", audio: [])
        defer { try? FileManager.default.removeItem(at: missing.directory) }
        #expect(throws: CueSheetError.missingAudioFile("gone.flac")) {
            try missing.sheet.plan(cuePath: missing.cuePath).get()
        }

        let mp3 = try writeAlbum(
            "FILE \"a.mp3\" MP3\nTRACK 01 AUDIO\nINDEX 01 00:00:00", audio: ["a.mp3"])
        defer { try? FileManager.default.removeItem(at: mp3.directory) }
        #expect(throws: CueSheetError.self) {
            try mp3.sheet.plan(cuePath: mp3.cuePath).get()
        }

        let noStart = try writeAlbum(
            "FILE \"a.wav\" WAVE\nTRACK 01 AUDIO\nINDEX 00 00:00:00", audio: ["a.wav"])
        defer { try? FileManager.default.removeItem(at: noStart.directory) }
        #expect(throws: CueSheetError.missingStart(track: 1)) {
            try noStart.sheet.plan(cuePath: noStart.cuePath).get()
        }

        let backwards = try writeAlbum(
            "FILE \"a.wav\" WAVE\nTRACK 01 AUDIO\nINDEX 01 01:00:00\nTRACK 02 AUDIO\nINDEX 01 00:30:00",
            audio: ["a.wav"])
        defer { try? FileManager.default.removeItem(at: backwards.directory) }
        #expect(throws: CueSheetError.tracksOutOfOrder(track: 2)) {
            try backwards.sheet.plan(cuePath: backwards.cuePath).get()
        }

        #expect(throws: CueSheetError.noTracks) {
            try CueSheet().plan(cuePath: "/tmp/a.cue").get()
        }
    }

    @Test("Duplicate titles get a suffix so no track overwrites another")
    func duplicateNames() throws {
        let (tracks, directory) = try plan(
            """
            FILE "a.wav" WAVE
              TRACK 01 AUDIO
                TITLE "Same"
                INDEX 01 00:00:00
              TRACK 01 AUDIO
                TITLE "Same"
                INDEX 01 01:00:00
            """, audio: ["a.wav"])
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(tracks.map(\.fileName) == ["01 - Same.wav", "01 - Same (2).wav"])
    }

    // MARK: - Helpers

    private func plan(_ text: String, audio: [String]) throws -> ([CueTrack], URL) {
        let album = try writeAlbum(text, audio: audio)
        return try album.sheet.plan(cuePath: album.cuePath)
            .tapError { _ in try? FileManager.default.removeItem(at: album.directory) }
            .map { ($0, album.directory) }
            .get()
    }

    /// Writes album.cue and empty audio files into a new directory
    private func writeAlbum(_ text: String, audio: [String]) throws -> (
        sheet: CueSheet, cuePath: String, directory: URL
    ) {
        var files = ["album.cue": text]
        for name in audio {
            files[name] = ""
        }
        let directory = try TestHelpers.createTestDirectory(files: files)
        let cuePath = directory.appendingPathComponent("album.cue").path(percentEncoded: false)
        return (try CueSheet.parse(text).get(), cuePath, directory)
    }
}
