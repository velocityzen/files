import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

/// A cue sheet of `tracks` tracks, `secondsPerTrack` long each, and the album image it
/// describes. Creating it is a benchmark's setup and removing it its teardown.
public struct AlbumFixture: Sendable {
    public let root: String
    public let tracks: Int
    public let secondsPerTrack: Int
    /// The album image's extension: "wav" or "flac"
    public let format: String

    public var cuePath: String { root + "/album.cue" }
    public var audioPath: String { root + "/album.\(format)" }
    public var output: String { root + "/tracks" }

    public init(tracks: Int, secondsPerTrack: Int = 3, format: String = "wav") {
        self.tracks = tracks
        self.secondsPerTrack = secondsPerTrack
        self.format = format
        self.root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("files-benchmark-\(UUID().uuidString)")
    }

    /// A sheet in the shape rippers write: album tags, then each track with a title, a
    /// performer, a pregap and a start
    public var cueSheet: String {
        let header = """
            REM GENRE "Post Rock"
            REM DATE 2004
            PERFORMER "The Band"
            TITLE "The Album"
            FILE "album.\(format)" WAVE

            """
        return header
            + (1...tracks).map { number in
                let start = (number - 1) * secondsPerTrack
                return """
                      TRACK \(Self.twoDigits(number)) AUDIO
                        TITLE "Song number \(number)"
                        PERFORMER "The Band"
                        INDEX 00 \(Self.time(seconds: max(0, start - 1)))
                        INDEX 01 \(Self.time(seconds: start))

                    """
            }
            .joined()
    }

    /// Writes the cue sheet and an empty album image, which is all planning looks at
    public func createSheet() throws {
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try cueSheet.write(toFile: cuePath, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: audioPath, contents: nil)
    }

    public func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }

    /// mm:ss:ff
    private static func time(seconds: Int) -> String {
        "\(twoDigits(seconds / 60)):\(twoDigits(seconds % 60)):00"
    }

    private static func twoDigits(_ number: Int) -> String {
        number < 10 ? "0\(number)" : "\(number)"
    }
}

#if canImport(AVFoundation)
extension AlbumFixture {
    /// Whether Core Audio can write audio files in this process. SwiftPM runs benchmarks in a
    /// sandbox that blocks the audio services `AVAudioFile` needs, so cutting can only be
    /// benchmarked with `swift package --disable-sandbox benchmark`.
    public static let canWriteAudio: Bool = {
        let probe = AlbumFixture(tracks: 1, secondsPerTrack: 1, format: "flac")
        defer { probe.remove() }
        return (try? probe.createAlbum()) != nil
    }()

    /// Writes the cue sheet and a real album image of stereo noise at 44.1 kHz: 16-bit for
    /// WAV, 24-bit for FLAC
    public func createAlbum() throws {
        try createSheet()
        var settings: [String: Any] = [AVSampleRateKey: 44_100.0, AVNumberOfChannelsKey: 2]
        if format == "flac" {
            settings[AVFormatIDKey] = kAudioFormatFLAC
        } else {
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
        }

        let file = try AVAudioFile(
            forWriting: URL(fileURLWithPath: audioPath), settings: settings,
            commonFormat: .pcmFormatInt32, interleaved: false)
        let frames = AVAudioFrameCount(44_100 * secondsPerTrack * tracks)
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: frames),
            let channels = buffer.int32ChannelData
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = frames
        var state: UInt32 = 0x1234_5678
        for channel in 0..<2 {
            for frame in 0..<Int(frames) {
                state = state &* 1_664_525 &+ 1_013_904_223
                // Low byte clear, so 24-bit FLAC keeps every sample
                channels[channel][frame] = (Int32(bitPattern: state) >> 8) << 8
            }
        }
        try file.write(from: buffer)
        file.close()
    }
}
#endif
