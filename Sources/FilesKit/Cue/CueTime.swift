import Foundation

/// A position in a cue sheet, in CD frames (75 per second)
public struct CueTime: Sendable, Hashable, Comparable, CustomStringConvertible {
    public static let framesPerSecond = 75
    public static let zero = CueTime(frames: 0)

    public let frames: Int

    public init(frames: Int) {
        self.frames = frames
    }

    /// Parses "mm:ss:ff" (minutes may exceed 99 for long files)
    public init?(_ text: some StringProtocol) {
        let parts = text.split(separator: ":")
        guard parts.count == 3,
            let minutes = Int(parts[0]), let seconds = Int(parts[1]), let frames = Int(parts[2]),
            minutes >= 0, (0..<60).contains(seconds), (0..<Self.framesPerSecond).contains(frames)
        else {
            return nil
        }
        self.frames = (minutes * 60 + seconds) * Self.framesPerSecond + frames
    }

    public var description: String {
        let seconds = frames / Self.framesPerSecond
        return String(
            format: "%02d:%02d:%02d", seconds / 60, seconds % 60, frames % Self.framesPerSecond)
    }

    /// Sample offset at a sample rate; CD frames divide evenly at all common rates
    public func samples(atSampleRate sampleRate: Double) -> Int64 {
        Int64(frames) * Int64(sampleRate.rounded()) / Int64(Self.framesPerSecond)
    }

    public static func < (lhs: CueTime, rhs: CueTime) -> Bool {
        lhs.frames < rhs.frames
    }
}
