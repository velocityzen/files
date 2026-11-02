import ArgumentParser
import FP
import FilesKit
import Foundation

extension Files {
    struct CutCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "cut",
            abstract: "Split an album image into tracks using a cue sheet",
            discussion: """
                Cuts each track of a cue sheet out of its audio file, losslessly and with the
                source bit depth. FLAC, WAV and AIFF keep their format; APE and WavPack are
                decoded with ffmpeg (if installed) and written as FLAC. FLAC tracks are tagged
                from the cue sheet.

                Tracks are named "NN - Title", or "NN - Performer - Title" when a track has its
                own performer. Pregaps stay with the track before them.
                """
        )

        @Argument(help: "The cue sheet")
        var cuePath: String

        @Option(
            name: [.short, .long],
            help: "Directory to write the tracks to (default: the cue sheet's directory)")
        var output: String?

        @Option(
            name: .long,
            help: "Cue sheet text encoding as an IANA name, e.g. windows-1251 (default: detect)")
        var encoding: String?

        @Flag(name: .long, help: "Replace track files that already exist")
        var overwrite: Bool = false

        @Flag(name: .long, help: "List the tracks without cutting them")
        var dryRun: Bool = false

        @Flag(name: [.short, .long], help: "Show the source and time range of each track")
        var verbose: Bool = false

        func validate() throws {
            if let encoding, Self.stringEncoding(named: encoding) == nil {
                throw ValidationError("Unknown encoding '\(encoding)'")
            }
        }

        mutating func run() async throws {
            let tracks = try planTracks().get()
            if dryRun {
                OutputFormatter.printDiagnostic("🔍 DRY RUN - No files will be written\n")
                tracks.forEach { printTrack($0) }
                Status.done(
                    "Dry run: \(Status.count(tracks.count, "track")) in \(albumName(tracks))")
                return
            }
            try await cut(tracks).get()
        }

        /// Reads the cue sheet and works out the tracks; cue sheet errors exit with 2
        private func planTracks() -> Result<[CueTrack], ExitCode> {
            CueSheet.load(from: cuePath, encoding: encoding.flatMap(Self.stringEncoding(named:)))
                .tap(noteEncoding)
                .flatMap { $0.sheet.plan(cuePath: cuePath) }
                .tapError(reportCueError)
                .mapError { _ in ExitCode(2) }
        }

        private func reportCueError(_ error: CueSheetError) {
            OutputFormatter.printDiagnostic("Error: \(error.localizedDescription)")
            Status.failed(error.localizedDescription)
        }

        /// A detected legacy encoding may be a wrong guess, so say which one was used
        private func noteEncoding(_ loaded: CueSheet.Loaded) {
            guard loaded.encoding != .utf8 && encoding == nil else {
                return
            }
            OutputFormatter.printDiagnostic(
                "Read cue sheet as \(String.localizedName(of: loaded.encoding)); pass --encoding if titles look wrong"
            )
        }

        /// The album title, or the cue sheet's name when it has none
        private func albumName(_ tracks: [CueTrack]) -> String {
            tracks.first?.tags.album
                ?? URL(fileURLWithPath: cuePath).deletingPathExtension().lastPathComponent
        }

        private var outputDirectory: String {
            output
                ?? URL(fileURLWithPath: cuePath).deletingLastPathComponent()
                .path(percentEncoded: false)
        }

        #if canImport(AVFoundation)
        /// Cuts the tracks, printing each as it finishes; any failed track exits with 1
        private func cut(_ tracks: [CueTrack]) async -> Result<Void, ExitCode> {
            let album = albumName(tracks)
            Status.working("Cutting \(album)", progress: 0)
            let results = await cutTracks(tracks, to: outputDirectory, overwrite: overwrite)
                .reduce(into: [CueTrackResult]()) { results, result in
                    printResult(result)
                    results.append(result)
                    Status.working(
                        "Cutting \(album) (\(results.count) of \(Status.count(tracks.count, "track")))",
                        progress: results.count * 100 / tracks.count)
                }
            return summarize(results, album: album)
        }

        private func printResult(_ result: CueTrackResult) {
            result.match(
                { printTrack($0.track, mark: "✓") },
                { failure in
                    printTrack(failure.track, mark: "✗")
                    print("    Error: \(failure.localizedDescription)")
                }
            )
        }

        private func summarize(_ results: [CueTrackResult], album: String) -> Result<
            Void, ExitCode
        > {
            let (cut, failed) = results.separate()
            print()
            print("Summary: \(cut.count) cut, \(failed.count) failed")
            guard failed.isEmpty else {
                Status.failed(
                    "\(failed.count) of \(Status.count(results.count, "track")) failed cutting \(album)"
                )
                return .failure(ExitCode(1))
            }
            Status.done("Cut \(Status.count(cut.count, "track")) from \(album)")
            return .success(())
        }
        #else
        private func cut(_ tracks: [CueTrack]) async -> Result<Void, ExitCode> {
            OutputFormatter.printDiagnostic("Error: cut requires macOS (Core Audio)")
            return .failure(ExitCode(1))
        }
        #endif

        private func printTrack(_ track: CueTrack, mark: String? = nil) {
            print([mark, track.fileName].compactMap { $0 }.joined(separator: " "))
            if verbose {
                let end = track.end.map(String.init(describing:)) ?? "end"
                let source = (track.source as NSString).lastPathComponent
                print("    \(source) \(track.start)–\(end)")
            }
        }

        /// Converts an IANA charset name such as "windows-1251" or "shift_jis"
        static func stringEncoding(named name: String) -> String.Encoding? {
            #if canImport(Darwin)
            let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            guard encoding != kCFStringEncodingInvalidId else {
                return nil
            }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
            #else
            return name.lowercased() == "utf-8" ? .utf8 : nil
            #endif
        }
    }
}
