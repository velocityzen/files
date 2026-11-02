import FP
import Foundation

extension CueSheet {
    /// Parses the text of a cue sheet
    public static func parse(_ text: String) -> Result<CueSheet, CueSheetError> {
        numberedLines(text)
            .traverse { CueLine.parse($0.text, number: $0.number) }
            .map { $0.compact() }
            .flatMap(assemble)
    }

    /// Lines with text, numbered from 1 and trimmed of whitespace and byte order marks
    private static func numberedLines(_ text: String) -> [(number: Int, text: String)] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .enumerated()
            .map {
                ($0.offset + 1, $0.element.trimmingCharacters(in: .whitespaces.union(["\u{FEFF}"])))
            }
            .filter { !$0.text.isEmpty }
    }

    /// Applies each line in order to an empty sheet, stopping at the first that doesn't fit
    private static func assemble(_ lines: [CueLine]) -> Result<CueSheet, CueSheetError> {
        lines.reduce(.success(CueSheet())) { sheet, line in sheet.flatMap { $0.applying(line) } }
    }

    /// The sheet with one more line applied
    func applying(_ line: CueLine) -> Result<CueSheet, CueSheetError> {
        switch line.command {
            case .file(let name): .success(addingFile(name))
            case .track(let number): addingTrack(number, line: line.number)
            case .index(let number, let time): settingIndex(number, to: time, line: line.number)
            case .title(let value): .success(setting(\.title, \.title, to: value))
            case .performer(let value): .success(setting(\.performer, \.performer, to: value))
            case .songwriter(let value): .success(setting(\.songwriter, \.songwriter, to: value))
            case .isrc(let value): .success(settingTrack(\.isrc, to: value))
            case .genre(let value): .success(settingAlbum(\.genre, to: value))
            case .date(let value): .success(settingAlbum(\.date, to: value))
            case .discNumber(let value): .success(settingAlbum(\.discNumber, to: value))
            case .totalDiscs(let value): .success(settingAlbum(\.totalDiscs, to: value))
        }
    }

    private func addingFile(_ name: String) -> CueSheet {
        var sheet = self
        sheet.files.append(name)
        return sheet
    }

    private func addingTrack(_ number: Int, line: Int) -> Result<CueSheet, CueSheetError> {
        guard !files.isEmpty else {
            return .failure(.trackOutsideFile(line: line))
        }
        var sheet = self
        sheet.tracks.append(Track(number: number))
        return .success(sheet)
    }

    /// An index belongs to the latest track and to the latest FILE, which can differ when
    /// a pregap ends the previous file
    private func settingIndex(_ number: Int, to time: CueTime, line: Int) -> Result<
        CueSheet, CueSheetError
    > {
        guard !tracks.isEmpty else {
            return .failure(.indexOutsideTrack(line: line))
        }
        let position = Position(file: files.count - 1, time: time)
        return .success(updatingLastTrack { $0.indexes[number] = position })
    }

    /// Metadata before the first TRACK line is the album's; after it, the latest track's,
    /// even across a FILE line
    private func setting(
        _ album: WritableKeyPath<CueSheet, String?>,
        _ track: WritableKeyPath<Track, String?>,
        to value: String
    ) -> CueSheet {
        tracks.isEmpty ? settingAlbum(album, to: value) : settingTrack(track, to: value)
    }

    private func settingAlbum(_ field: WritableKeyPath<CueSheet, String?>, to value: String)
        -> CueSheet
    {
        var sheet = self
        sheet[keyPath: field] = value
        return sheet
    }

    /// Track fields before the first TRACK line have no track to belong to
    private func settingTrack(_ field: WritableKeyPath<Track, String?>, to value: String)
        -> CueSheet
    {
        tracks.isEmpty ? self : updatingLastTrack { $0[keyPath: field] = value }
    }

    private func updatingLastTrack(_ update: (inout Track) -> Void) -> CueSheet {
        var sheet = self
        update(&sheet.tracks[sheet.tracks.count - 1])
        return sheet
    }
}
