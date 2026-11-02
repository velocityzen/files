import FP
import Foundation

/// Safe, unique file names for cut tracks
enum TrackFileName {
    /// Leaves room for an extension and a " (2)" suffix within the 255-byte name limit
    private static let maxStemBytes = 240
    private static let reserved: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]

    /// Digits to pad track numbers to: two, or more for a sheet with 100 tracks or more
    static func numberWidth(_ numbers: [Int]) -> Int {
        max(2, String(numbers.max() ?? 0).count)
    }

    /// "NN - Title.ext", or "NN - Performer - Title.ext" when the track has its own performer
    static func make(
        number: Int, width: Int, performer: String?, title: String?, extension pathExtension: String
    ) -> String {
        let stem = stem(number: number, width: width, performer: performer, title: title)
        return "\(sanitized(stem)).\(pathExtension)"
    }

    static func stem(number: Int, width: Int, performer: String?, title: String?) -> String {
        let paddedNumber =
            String(repeating: "0", count: max(0, width - String(number).count)) + String(number)
        return [paddedNumber, performer, title ?? "Track \(paddedNumber)"]
            .compact()
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }

    /// Adds " (2)", " (3)", … to names that repeat, ignoring case, so no track replaces another
    static func deduplicated(_ names: [String]) -> [String] {
        names.reduce(into: (names: [String](), used: Set<String>())) { result, name in
            let unique = uniqueName(name, avoiding: result.used)
            result.names.append(unique)
            result.used.insert(unique.lowercased())
        }
        .names
    }

    private static func uniqueName(_ name: String, avoiding used: Set<String>) -> String {
        let stem = (name as NSString).deletingPathExtension
        let pathExtension = (name as NSString).pathExtension
        let numbered = (2...).lazy.map { "\(stem) (\($0)).\(pathExtension)" }
        return ([name] + numbered.prefix(used.count + 1))
            .first { !used.contains($0.lowercased()) } ?? name
    }

    /// Replaces characters that file systems reject or that split paths, then trims what
    /// Finder and Windows strip anyway
    static func sanitized(_ name: String, maxBytes: Int = maxStemBytes) -> String {
        let trimmed = prefix(String(name.map(safeCharacter)), maxBytes: maxBytes)
            .trimmingCharacters(in: .whitespaces)
        let withoutDots = String(trimmed.reversed().drop { $0 == "." }.reversed())
        return withoutDots.isEmpty ? "_" : withoutDots
    }

    private static func safeCharacter(_ character: Character) -> Character {
        let isControl = character.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
        return reserved.contains(character) || isControl ? "_" : character
    }

    /// The longest run of whole characters from the start that fits in `maxBytes` of UTF-8
    private static func prefix(_ text: String, maxBytes: Int) -> String {
        let characterEnds = Array(text.indices.dropFirst()) + [text.endIndex]
        let end = characterEnds.last { text[..<$0].utf8.count <= maxBytes } ?? text.startIndex
        return String(text[..<end])
    }
}
