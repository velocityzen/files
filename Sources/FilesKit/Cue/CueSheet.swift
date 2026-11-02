import Foundation

/// A parsed cue sheet: album metadata plus the audio files and tracks it describes
public struct CueSheet: Sendable, Equatable {
    public var title: String?
    public var performer: String?
    public var songwriter: String?
    public var genre: String?
    public var date: String?
    public var discNumber: String?
    public var totalDiscs: String?
    /// Audio file names from FILE lines, in order
    public var files: [String] = []
    public var tracks: [Track] = []

    public struct Track: Sendable, Equatable {
        public var number: Int
        public var title: String?
        public var performer: String?
        public var songwriter: String?
        public var isrc: String?
        /// INDEX number to position; INDEX 01 is where the track starts. A track's
        /// indexes can sit in different files when its pregap ends the previous file.
        public var indexes: [Int: Position] = [:]

        public init(number: Int) {
            self.number = number
        }

        /// Where the track starts (INDEX 01)
        public var start: Position? {
            indexes[1]
        }
    }

    /// A point in one of the sheet's files
    public struct Position: Sendable, Equatable {
        /// Index into `files`
        public var file: Int
        public var time: CueTime

        public init(file: Int, time: CueTime) {
            self.file = file
            self.time = time
        }
    }

    public init() {}
}
