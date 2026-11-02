import FP
import Foundation

/// A cue sheet line that affects the parsed sheet
enum CueCommand: Equatable {
    case file(String)
    case track(Int)
    case index(Int, CueTime)
    case title(String)
    case performer(String)
    case songwriter(String)
    case isrc(String)
    case genre(String)
    case date(String)
    case discNumber(String)
    case totalDiscs(String)
}

/// A command with the number of the line it came from, for error messages
struct CueLine: Equatable {
    let number: Int
    let command: CueCommand
}

extension CueLine {
    /// The command on a line, or nil for a line that doesn't affect the sheet: CATALOG,
    /// FLAGS, PREGAP, POSTGAP, CDTEXTFILE, other REM fields, and unknown keywords
    static func parse(_ line: String, number: Int) -> Result<CueLine?, CueSheetError> {
        let (keyword, rest) = splitKeyword(line)
        return command(keyword, rest, line: number)
            .map { $0.map { CueLine(number: number, command: $0) } }
    }

    private static func command(
        _ keyword: String,
        _ rest: Substring,
        line: Int
    ) -> Result<CueCommand?, CueSheetError> {
        switch keyword {
            case "FILE": .success(.file(fileName(rest)))
            case "TRACK": trackNumber(rest, line: line).map { .track($0) }
            case "INDEX": index(rest, line: line).map { $0 }
            case "TITLE": .success(.title(value(rest)))
            case "PERFORMER": .success(.performer(value(rest)))
            case "SONGWRITER": .success(.songwriter(value(rest)))
            case "ISRC": .success(.isrc(value(rest)))
            case "REM": .success(remark(rest))
            default: .success(nil)
        }
    }

    private static func trackNumber(_ rest: Substring, line: Int) -> Result<Int, CueSheetError> {
        let text = splitKeyword(rest).keyword
        return .fromOptional(Int(text), error: .invalidTrackNumber(line: line, text))
    }

    /// "nn mm:ss:ff"
    private static func index(_ rest: Substring, line: Int) -> Result<CueCommand, CueSheetError> {
        let (numberText, timeText) = splitKeyword(rest)
        guard let number = Int(numberText), let time = CueTime(timeText) else {
            return .failure(.invalidTime(line: line, String(rest)))
        }
        return .success(.index(number, time))
    }

    /// The REM fields that end up in tags
    private static func remark(_ rest: Substring) -> CueCommand? {
        let (field, text) = splitKeyword(rest)
        return switch field {
            case "GENRE": .genre(value(text))
            case "DATE": .date(value(text))
            case "DISCNUMBER": .discNumber(value(text))
            case "TOTALDISCS": .totalDiscs(value(text))
            default: nil
        }
    }

    /// Splits "KEYWORD rest of line" and uppercases the keyword
    private static func splitKeyword(_ line: some StringProtocol) -> (
        keyword: String, rest: Substring
    ) {
        let line = Substring(line).drop { $0.isWhitespace }
        guard let space = line.firstIndex(where: \.isWhitespace) else {
            return (line.uppercased(), "")
        }
        return (line[..<space].uppercased(), line[space...].drop { $0.isWhitespace })
    }

    /// A value that may be quoted; unquoted values run to the end of the line
    private static func value(_ text: Substring) -> String {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("\""), let close = text.dropFirst().firstIndex(of: "\"") else {
            return text
        }
        return String(text[text.index(after: text.startIndex)..<close])
    }

    /// The file name of a FILE line, without its trailing type (WAVE, MP3, ...)
    private static func fileName(_ text: Substring) -> String {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\"") {
            return value(Substring(text))
        }
        guard let space = text.lastIndex(where: \.isWhitespace) else {
            return text
        }
        return text[..<space].trimmingCharacters(in: .whitespaces)
    }
}
