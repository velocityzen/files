import Foundation
import Testing

@testable import FilesKit

@Suite("Cue sheet parsing")
struct CueSheetTests {
    @Test("Reads album metadata, track metadata and indexes")
    func parsesSheet() throws {
        let sheet = try CueSheet.parse(
            """
            REM GENRE "Post Rock"
            REM DATE 2004
            REM DISCNUMBER 1
            REM TOTALDISCS 2
            REM COMMENT "ExactAudioCopy v1.0"
            CATALOG 0000000000000
            PERFORMER "The Band"
            SONGWRITER Someone Else
            TITLE "Album"
            FILE "Album Image.flac" WAVE
              TRACK 01 AUDIO
                TITLE "First"
                ISRC USRC17607839
                INDEX 01 00:00:00
              track 02 audio
                title Second Song
                performer "Guest"
                songwriter "Writer"
                FLAGS DCP
                INDEX 00 03:58:10
                INDEX 01 04:00:00
            """
        ).get()

        #expect(sheet.title == "Album")
        #expect(sheet.performer == "The Band")
        #expect(sheet.songwriter == "Someone Else")
        #expect(sheet.genre == "Post Rock")
        #expect(sheet.date == "2004")
        #expect(sheet.discNumber == "1")
        #expect(sheet.totalDiscs == "2")
        #expect(sheet.files == ["Album Image.flac"])
        #expect(sheet.tracks.count == 2)

        let first = sheet.tracks[0]
        #expect(first.number == 1)
        #expect(first.title == "First")
        #expect(first.isrc == "USRC17607839")
        #expect(first.start == CueSheet.Position(file: 0, time: CueTime(frames: 0)))

        let second = sheet.tracks[1]
        #expect(second.title == "Second Song")
        #expect(second.performer == "Guest")
        #expect(second.songwriter == "Writer")
        #expect(second.indexes[0]?.time == CueTime("03:58:10"))
        #expect(second.start?.time == CueTime(frames: 240 * 75))
    }

    @Test("Unquoted FILE names keep their spaces and drop the file type")
    func unquotedFileName() throws {
        let sheet = try CueSheet.parse(
            """
            FILE My Album.wav WAVE
              TRACK 01 AUDIO
                INDEX 01 00:00:00
            """
        ).get()
        #expect(sheet.files == ["My Album.wav"])
    }

    @Test("Tracks remember which FILE each index is in")
    func multipleFiles() throws {
        let sheet = try CueSheet.parse(
            """
            FILE "01.wav" WAVE
              TRACK 01 AUDIO
                INDEX 01 00:00:00
              TRACK 02 AUDIO
                INDEX 00 04:10:00
            FILE "02.wav" WAVE
                TITLE "Two"
                INDEX 01 00:00:00
            """
        ).get()

        #expect(sheet.files == ["01.wav", "02.wav"])
        #expect(sheet.tracks[1].indexes[0]?.file == 0)
        #expect(sheet.tracks[1].start?.file == 1)
        // Metadata after a FILE line still belongs to the open track
        #expect(sheet.tracks[1].title == "Two")
    }

    @Test("Rejects lines that make no sense where they are")
    func errors() {
        #expect(throws: CueSheetError.trackOutsideFile(line: 1)) {
            try CueSheet.parse("TRACK 01 AUDIO").get()
        }
        #expect(throws: CueSheetError.indexOutsideTrack(line: 2)) {
            try CueSheet.parse("FILE \"a.wav\" WAVE\nINDEX 01 00:00:00").get()
        }
        #expect(throws: CueSheetError.invalidTime(line: 3, "01 00:61:00")) {
            try CueSheet.parse("FILE \"a.wav\" WAVE\nTRACK 01 AUDIO\nINDEX 01 00:61:00").get()
        }
        #expect(throws: CueSheetError.invalidTrackNumber(line: 2, "X")) {
            try CueSheet.parse("FILE \"a.wav\" WAVE\nTRACK X AUDIO").get()
        }
    }

    @Test("CueTime parses mm:ss:ff and converts to sample offsets")
    func cueTime() {
        #expect(CueTime("00:00:00")?.frames == 0)
        #expect(CueTime("01:02:03")?.frames == (62 * 75) + 3)
        #expect(CueTime("120:00:00")?.frames == 120 * 60 * 75)
        #expect(CueTime("00:00:75") == nil)
        #expect(CueTime("00:60:00") == nil)
        #expect(CueTime("00:00") == nil)
        #expect(CueTime("01:02:03")?.description == "01:02:03")

        let oneFrame = CueTime(frames: 1)
        #expect(oneFrame.samples(atSampleRate: 44_100) == 588)
        #expect(oneFrame.samples(atSampleRate: 48_000) == 640)
        #expect(CueTime(frames: 75).samples(atSampleRate: 96_000) == 96_000)
    }

    // MARK: - Loading

    @Test(
        "Detects legacy code pages",
        arguments: [
            (String.Encoding.windowsCP1251, "Группа крови"),
            (String.Encoding.windowsCP1252, "Für Elise – Ça va"),
            (String.Encoding.shiftJIS, "東京の夜"),
        ])
    func detectsEncoding(encoding: String.Encoding, title: String) throws {
        let path = try writeCue(
            "PERFORMER \"\(title)\"\nTITLE \"\(title)\"\nFILE \"a.flac\" WAVE\n  TRACK 01 AUDIO\n    TITLE \"\(title)\"\n    INDEX 01 00:00:00\n",
            encoding: encoding)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let (sheet, used) = try CueSheet.load(from: path).get()
        #expect(used == encoding)
        #expect(sheet.title == title)
        #expect(sheet.tracks.first?.title == title)
    }

    @Test("Reads UTF-8 with a byte order mark, and uses an explicit encoding when given")
    func utf8AndExplicit() throws {
        let utf8 = try writeCue(
            "\u{FEFF}TITLE \"Ünïcode\"\nFILE \"a.flac\" WAVE\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n",
            encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: utf8) }

        let (sheet, used) = try CueSheet.load(from: utf8).get()
        #expect(used == .utf8)
        #expect(sheet.title == "Ünïcode")

        // Latin-1 decodes any bytes, so the explicit choice must win over detection
        let (latin1, forced) = try CueSheet.load(from: utf8, encoding: .isoLatin1).get()
        #expect(forced == .isoLatin1)
        #expect(latin1.title != "Ünïcode")
    }

    @Test("A missing cue sheet is unreadable")
    func missingFile() {
        #expect(throws: CueSheetError.unreadable("/nonexistent/a.cue")) {
            try CueSheet.load(from: "/nonexistent/a.cue").get()
        }
    }

    private func writeCue(_ text: String, encoding: String.Encoding) throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).cue").path(percentEncoded: false)
        try #require(text.data(using: encoding)).write(to: URL(fileURLWithPath: path))
        return path
    }
}
