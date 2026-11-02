import Foundation

/// One track to cut out of an album image
public struct CueTrack: Sendable, Equatable {
    public var number: Int
    /// Audio file the track is cut from
    public var source: String
    public var start: CueTime
    /// Where the track ends; nil runs to the end of the source
    public var end: CueTime?
    /// Output file name, including the extension
    public var fileName: String
    public var tags: AudioTags

    public init(
        number: Int, source: String, start: CueTime, end: CueTime?, fileName: String,
        tags: AudioTags
    ) {
        self.number = number
        self.source = source
        self.start = start
        self.end = end
        self.fileName = fileName
        self.tags = tags
    }
}
