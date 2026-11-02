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
    private static func numberedLines(_ text: String) -> [(number: Int, text: Substring)] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .enumerated()
            .map { ($0.offset + 1, $0.element.trimmingWhitespace()) }
            .filter { !$0.text.isEmpty }
    }

    /// Applies each line in order to an empty sheet, stopping at the first that doesn't fit.
    /// The sheet is changed in place: a new sheet per line would copy every track before it.
    private static func assemble(_ lines: [CueLine]) -> Result<CueSheet, CueSheetError> {
        var sheet = CueSheet()
        return lines.traverse { sheet.apply($0) }.map { _ in sheet }
    }

    /// Applies one line to the sheet
    mutating func apply(_ line: CueLine) -> Result<Void, CueSheetError> {
        switch line.command {
            case .file(let name): files.append(name)
            case .track(let number): return addTrack(number, line: line.number)
            case .index(let number, let time): return setIndex(number, to: time, line: line.number)
            case .title(let value): set(\.title, \.title, to: value)
            case .performer(let value): set(\.performer, \.performer, to: value)
            case .songwriter(let value): set(\.songwriter, \.songwriter, to: value)
            case .isrc(let value): setTrack(\.isrc, to: value)
            case .genre(let value): genre = value
            case .date(let value): date = value
            case .discNumber(let value): discNumber = value
            case .totalDiscs(let value): totalDiscs = value
        }
        return .success(())
    }

    private mutating func addTrack(_ number: Int, line: Int) -> Result<Void, CueSheetError> {
        guard !files.isEmpty else {
            return .failure(.trackOutsideFile(line: line))
        }
        tracks.append(Track(number: number))
        return .success(())
    }

    /// An index belongs to the latest track and to the latest FILE, which can differ when
    /// a pregap ends the previous file
    private mutating func setIndex(_ number: Int, to time: CueTime, line: Int) -> Result<
        Void, CueSheetError
    > {
        guard !tracks.isEmpty else {
            return .failure(.indexOutsideTrack(line: line))
        }
        let position = Position(file: files.count - 1, time: time)
        updateLastTrack { $0.indexes[number] = position }
        return .success(())
    }

    /// Metadata before the first TRACK line is the album's; after it, the latest track's,
    /// even across a FILE line
    private mutating func set(
        _ album: WritableKeyPath<CueSheet, String?>,
        _ track: WritableKeyPath<Track, String?>,
        to value: String
    ) {
        if tracks.isEmpty {
            self[keyPath: album] = value
        } else {
            setTrack(track, to: value)
        }
    }

    /// Track fields before the first TRACK line have no track to belong to
    private mutating func setTrack(_ field: WritableKeyPath<Track, String?>, to value: String) {
        updateLastTrack { $0[keyPath: field] = value }
    }

    private mutating func updateLastTrack(_ update: (inout Track) -> Void) {
        guard !tracks.isEmpty else {
            return
        }
        update(&tracks[tracks.count - 1])
    }
}
