extension StringProtocol {
    /// The text without leading and trailing whitespace or byte order marks.
    ///
    /// Native, unlike `trimmingCharacters(in:)`, which bridges to `NSString` and is called
    /// with a character set that is built again each time; a cue sheet trims every line and
    /// value, so that cost adds up.
    func trimmingWhitespace() -> SubSequence {
        let start = firstIndex { !$0.isBlank } ?? endIndex
        let end = lastIndex { !$0.isBlank }.map(index(after:)) ?? start
        return self[start..<end]
    }
}

extension Character {
    fileprivate var isBlank: Bool {
        isWhitespace || self == "\u{FEFF}"
    }
}
