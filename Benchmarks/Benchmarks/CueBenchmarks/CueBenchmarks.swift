import Benchmark
import BenchmarkSupport
import FilesKit

// The cue pipeline: parsing a sheet, planning its tracks against the files next to it, and
// cutting an album image into tracks (see AlbumFixture). Sheets have 12 tracks, a typical
// album, and 99, the most a CD holds.

let benchmarks: @Sendable () -> Void = {
    for tracks in [12, 99] {
        let tags = ["tracks": "\(tracks)"]
        let album = AlbumFixture(tracks: tracks)
        let text = album.cueSheet

        Benchmark("CueSheet.parse", configuration: .files(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(CueSheet.parse(text))
            }
        }

        // Planning looks for each track's audio file, so it touches the disk once per track
        Benchmark("CueSheet.plan", configuration: .files(tags)) {
            (benchmark: Benchmark, sheet: CueSheet) in
            for _ in benchmark.scaledIterations {
                blackHole(sheet.plan(cuePath: album.cuePath))
            }
        } setup: {
            try album.createSheet()
            return try CueSheet.parse(text).get()
        } teardown: {
            album.remove()
        }
    }

    #if canImport(AVFoundation)
    // SwiftPM's sandbox blocks the audio services AVAudioFile needs, so the cut benchmarks
    // only run with `swift package --disable-sandbox benchmark`. They are left out quietly
    // otherwise, since the plugin starts this executable once per benchmark.
    guard AlbumFixture.canWriteAudio else {
        return
    }

    // 30 seconds of audio in 10 tracks: WAV only copies samples, FLAC also decodes, encodes
    // and tags. Every call replaces the tracks the one before it wrote.
    for format in ["wav", "flac"] {
        let album = AlbumFixture(tracks: 10, format: format)
        Benchmark("cutTracks", configuration: .files(["format": format])) {
            (benchmark: Benchmark, tracks: [CueTrack]) async in
            for _ in benchmark.scaledIterations {
                for await result in cutTracks(tracks, to: album.output, overwrite: true) {
                    blackHole(result)
                }
            }
        } setup: {
            try album.createAlbum()
            return try CueSheet.parse(album.cueSheet)
                .flatMap { $0.plan(cuePath: album.cuePath) }
                .get()
        } teardown: {
            album.remove()
        }
    }
    #endif
}
