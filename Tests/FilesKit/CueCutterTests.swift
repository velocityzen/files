#if canImport(AVFoundation)
import AVFoundation
import Foundation
import Testing

@testable import FilesKit

@Suite("Cue cutting")
struct CueCutterTests {
    /// Track starts chosen so cuts land mid-packet in FLAC
    private static let cue = """
        PERFORMER "The Band"
        TITLE "Album"
        REM DATE 2001
        FILE "album.wav" WAVE
          TRACK 01 AUDIO
            TITLE "One"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Two"
            PERFORMER "Guest"
            INDEX 00 00:01:00
            INDEX 01 00:01:37
          TRACK 03 AUDIO
            TITLE "Three"
            INDEX 01 00:02:61
        """

    @Test(
        "Cuts are sample-exact and keep the source format and bit depth",
        arguments: [
            AudioFixture(fileExtension: "flac", bits: 16, sampleRate: 44_100),
            AudioFixture(fileExtension: "flac", bits: 24, sampleRate: 96_000),
            AudioFixture(fileExtension: "wav", bits: 16, sampleRate: 44_100),
            AudioFixture(fileExtension: "wav", bits: 24, sampleRate: 48_000),
            AudioFixture(fileExtension: "aiff", bits: 24, sampleRate: 44_100),
        ])
    func sampleExact(fixture: AudioFixture) async throws {
        let album = try makeAlbum(source: fixture)
        defer { try? FileManager.default.removeItem(at: album.directory) }

        let results = await collect(cutTracks(album.tracks, to: album.output))
        let outputs = try results.map { try $0.get() }
        #expect(outputs.count == 3)

        let joined = try outputs.flatMap { try readSamples($0.path) }
        #expect(joined == (try readSamples(album.source)))

        for output in outputs {
            #expect(output.path.hasSuffix(".\(fixture.fileExtension)"))
            let bits = try sourceBits(output.path)
            #expect(bits == fixture.bits)
        }
        #expect(try leftovers(in: album.output).isEmpty)
    }

    @Test("FLAC tracks are tagged from the cue sheet")
    func flacTags() async throws {
        let album = try makeAlbum(
            source: AudioFixture(fileExtension: "flac", bits: 16, sampleRate: 44_100))
        defer { try? FileManager.default.removeItem(at: album.directory) }

        let outputs = try await collect(cutTracks(album.tracks, to: album.output))
            .map { try $0.get() }

        let tags = try FLACTags.read(at: outputs[1].path).get()
        #expect(!tags.vendor.isEmpty)
        #expect(
            tags.comments == [
                "TITLE=Two", "ARTIST=Guest", "ALBUM=Album", "ALBUMARTIST=The Band",
                "DATE=2001", "TRACKNUMBER=2", "TRACKTOTAL=3",
            ])
        // The rewritten file is still valid audio
        #expect(try AVAudioFile(forReading: URL(fileURLWithPath: outputs[1].path)).length > 0)
    }

    @Test("Rewriting tags replaces them and leaves the audio alone")
    func retag() async throws {
        let album = try makeAlbum(
            source: AudioFixture(fileExtension: "flac", bits: 24, sampleRate: 48_000))
        defer { try? FileManager.default.removeItem(at: album.directory) }

        let path = try await collect(cutTracks(album.tracks, to: album.output))[0].get().path
        let before = try readSamples(path)
        let vendor = try FLACTags.read(at: path).get().vendor

        try FLACTags.write([(key: "TITLE", value: "Новое")], to: path).get()
        try FLACTags.write([(key: "TITLE", value: "Новое название")], to: path).get()

        let tags = try FLACTags.read(at: path).get()
        #expect(tags.comments == ["TITLE=Новое название"])
        #expect(tags.vendor == vendor)
        #expect(try readSamples(path) == before)

        #expect(throws: FLACTagsError.notFLAC(album.cuePath)) {
            try FLACTags.read(at: album.cuePath).get()
        }
    }

    @Test("Existing tracks are kept unless overwrite is on")
    func overwriteProtection() async throws {
        let album = try makeAlbum(
            source: AudioFixture(fileExtension: "wav", bits: 16, sampleRate: 44_100))
        defer { try? FileManager.default.removeItem(at: album.directory) }

        let existing = URL(fileURLWithPath: album.output).appendingPathComponent(
            "02 - Guest - Two.wav")
        try FileManager.default.createDirectory(
            atPath: album.output, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: existing)

        let first = await collect(cutTracks(album.tracks, to: album.output))
        #expect(first.filter { (try? $0.get()) != nil }.count == 2)
        guard case .failure(let failure) = first[1] else {
            Issue.record("Expected track 2 to fail")
            return
        }
        #expect(failure.error == .outputExists(existing.path(percentEncoded: false)))
        #expect(try Data(contentsOf: existing) == Data("keep me".utf8))

        let second = await collect(cutTracks(album.tracks, to: album.output, overwrite: true))
        #expect(second.allSatisfy { (try? $0.get()) != nil })
        #expect(try readSamples(existing.path(percentEncoded: false)).count > 0)
        #expect(try leftovers(in: album.output).isEmpty)
    }

    @Test("A track named like its source never replaces it, even with overwrite")
    func outputIsSource() async throws {
        let directory = try TestHelpers.createTestDirectory(files: [:])
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("01 - One.wav")
        try writeAudio(
            AudioFixture(fileExtension: "wav", bits: 16, sampleRate: 44_100), to: source)
        let before = try Data(contentsOf: source)
        let cuePath = directory.appendingPathComponent("album.cue").path(percentEncoded: false)
        let tracks = try CueSheet.parse(
            "FILE \"01 - One.wav\" WAVE\nTRACK 01 AUDIO\nTITLE \"One\"\nINDEX 01 00:00:00"
        ).flatMap { $0.plan(cuePath: cuePath) }.get()

        let results = await collect(
            cutTracks(tracks, to: directory.path(percentEncoded: false), overwrite: true))
        guard case .failure(let failure) = results.first else {
            Issue.record("Expected the cut to be refused")
            return
        }
        #expect(failure.error == .outputIsSource(source.path(percentEncoded: false)))
        #expect(try Data(contentsOf: source) == before)
    }

    @Test("A track past the end fails alone")
    func startPastEnd() async throws {
        let album = try makeAlbum(
            source: AudioFixture(fileExtension: "wav", bits: 16, sampleRate: 44_100),
            cue: Self.cue + "\n  TRACK 04 AUDIO\n    INDEX 01 10:00:00")
        defer { try? FileManager.default.removeItem(at: album.directory) }

        let results = await collect(cutTracks(album.tracks, to: album.output))
        #expect(results.count == 4)
        #expect(results.prefix(3).allSatisfy { (try? $0.get()) != nil })
        guard case .failure(let failure) = results[3] else {
            Issue.record("Expected track 4 to fail")
            return
        }
        #expect(failure.error == .startPastEnd(track: 4))
    }

    @Test("WavPack is decoded with ffmpeg and written as FLAC", .enabled(if: findFFmpeg() != nil))
    func wavPack() async throws {
        let directory = try TestHelpers.createTestDirectory(files: [:])
        defer { try? FileManager.default.removeItem(at: directory) }

        let wav = directory.appendingPathComponent("reference.wav")
        try writeAudio(
            AudioFixture(fileExtension: "wav", bits: 24, sampleRate: 48_000), to: wav)
        let wavPack = directory.appendingPathComponent("album.wv")
        try runFFmpeg([
            "-i", wav.path(percentEncoded: false), "-c:a", "wavpack",
            wavPack.path(percentEncoded: false),
        ])

        let cuePath = directory.appendingPathComponent("album.cue").path(percentEncoded: false)
        let tracks = try CueSheet.parse(Self.cue).flatMap { $0.plan(cuePath: cuePath) }.get()
        let output = directory.appendingPathComponent("out").path(percentEncoded: false)

        let outputs = try await collect(cutTracks(tracks, to: output)).map { try $0.get() }
        #expect(outputs.allSatisfy { $0.path.hasSuffix(".flac") })
        #expect(
            try outputs.flatMap { try readSamples($0.path) }
                == (try readSamples(wav.path(percentEncoded: false))))
        let bits = try sourceBits(outputs[0].path)
        #expect(bits == 24)
        #expect(try FLACTags.read(at: outputs[0].path).get().comments.contains("TITLE=One"))
        #expect(!FileManager.default.fileExists(atPath: output + "/decoded.flac"))
    }

    @Test("ffmpeg is looked up on PATH, then in fallback directories")
    func ffmpegLookup() throws {
        #expect(findFFmpeg(environment: ["PATH": ""], fallbackDirectories: []) == nil)

        let directory = try TestHelpers.createTestDirectory(files: ["bin/ffmpeg": "#!/bin/sh\n"])
        defer { try? FileManager.default.removeItem(at: directory) }
        let bin = directory.appendingPathComponent("bin").path(percentEncoded: false)
        let ffmpeg = (bin as NSString).appendingPathComponent("ffmpeg")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: ffmpeg)

        #expect(
            findFFmpeg(environment: ["PATH": "/nowhere:\(bin)"], fallbackDirectories: []) == ffmpeg)
        #expect(findFFmpeg(environment: [:], fallbackDirectories: [bin]) == ffmpeg)
    }

    // MARK: - Helpers

    private func makeAlbum(source fixture: AudioFixture, cue: String = Self.cue) throws -> (
        tracks: [CueTrack], source: String, cuePath: String, output: String, directory: URL
    ) {
        let directory = try TestHelpers.createTestDirectory(files: ["album.cue": cue])
        let source = directory.appendingPathComponent("album.\(fixture.fileExtension)")
        try writeAudio(fixture, to: source)
        let cuePath = directory.appendingPathComponent("album.cue").path(percentEncoded: false)
        return (
            try CueSheet.parse(cue).flatMap { $0.plan(cuePath: cuePath) }.get(),
            source.path(percentEncoded: false),
            cuePath,
            directory.appendingPathComponent("out").path(percentEncoded: false),
            directory
        )
    }

    private func collect(_ stream: AsyncStream<CueTrackResult>) async -> [CueTrackResult] {
        await stream.reduce(into: []) { $0.append($1) }
    }

    private func leftovers(in directory: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.hasPrefix(".") }
    }

    private func runFFmpeg(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(findFFmpeg()))
        process.arguments = ["-nostdin", "-loglevel", "error", "-y"] + arguments
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }
}

/// An audio file to generate for a test
struct AudioFixture: Sendable, CustomTestStringConvertible {
    var fileExtension: String
    var bits: Int
    var sampleRate: Double
    var seconds: Double = 4

    var testDescription: String {
        "\(bits)-bit \(fileExtension) at \(Int(sampleRate)) Hz"
    }
}

/// Writes noise that uses every bit of the fixture's bit depth, so any lossy step shows
func writeAudio(_ fixture: AudioFixture, to url: URL) throws {
    var settings: [String: Any] = [
        AVSampleRateKey: fixture.sampleRate,
        AVNumberOfChannelsKey: 2,
    ]
    if fixture.fileExtension == "flac" {
        settings[AVFormatIDKey] = kAudioFormatFLAC
    } else {
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMBitDepthKey] = fixture.bits
        settings[AVLinearPCMIsFloatKey] = false
        settings[AVLinearPCMIsBigEndianKey] = fixture.fileExtension == "aiff"
    }

    let file = try AVAudioFile(
        forWriting: url, settings: settings, commonFormat: .pcmFormatInt32, interleaved: false)
    let frames = AVAudioFrameCount(fixture.sampleRate * fixture.seconds)
    let buffer = try #require(
        AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
    buffer.frameLength = frames

    // Int32 samples are left-aligned, so the low bits below the bit depth stay zero
    let unusedBits = Int32(32 - fixture.bits)
    var state: UInt32 = 0x1234_5678
    for channel in 0..<2 {
        let samples = try #require(buffer.int32ChannelData)[channel]
        for frame in 0..<Int(frames) {
            state = state &* 1_664_525 &+ 1_013_904_223
            samples[frame] = (Int32(bitPattern: state) >> unusedBits) << unusedBits
        }
    }
    try file.write(from: buffer)
    if fixture.fileExtension == "flac" {
        // 16-bit FLAC needs an Int16 client format; convert by rewriting
        file.close()
        if fixture.bits == 16 {
            try rewriteFLACAs16Bit(url)
        }
    }
}

/// Core Audio writes 24-bit FLAC from Int32 samples; re-encode through Int16 for 16-bit
private func rewriteFLACAs16Bit(_ url: URL) throws {
    let input = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
    let temp = url.deletingLastPathComponent().appendingPathComponent("16-\(url.lastPathComponent)")
    let output = try AVAudioFile(
        forWriting: temp, settings: input.fileFormat.settings, commonFormat: .pcmFormatInt16,
        interleaved: false)
    let buffer = try #require(
        AVAudioPCMBuffer(
            pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length)))
    try input.read(into: buffer)
    try output.write(from: buffer)
    output.close()
    _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
}

/// All samples of a file, interleaved and left-aligned in Int32
func readSamples(_ path: String) throws -> [Int32] {
    let file = try AVAudioFile(
        forReading: URL(fileURLWithPath: path), commonFormat: .pcmFormatInt32, interleaved: true)
    let buffer = try #require(
        AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let channels = Int(file.processingFormat.channelCount)
    return Array(
        UnsafeBufferPointer(
            start: try #require(buffer.int32ChannelData)[0],
            count: Int(buffer.frameLength) * channels))
}

/// Bit depth the file stores, from the PCM format or the FLAC source flags
func sourceBits(_ path: String) throws -> Int {
    // streamDescription points into the format, so keep the format alive while reading it
    let format = try AVAudioFile(forReading: URL(fileURLWithPath: path)).fileFormat
    let description = withExtendedLifetime(format) { format.streamDescription.pointee }
    if description.mFormatID == kAudioFormatFLAC {
        return [1: 16, 2: 20, 3: 24, 4: 32][description.mFormatFlags] ?? 0
    }
    return Int(description.mBitsPerChannel)
}
#endif
