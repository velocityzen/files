import FP
import FPBracket
import Foundation

/// Formats Core Audio can't read
func needsFFmpeg(_ path: String) -> Bool {
    ["ape", "wv"].contains((path as NSString).pathExtension.lowercased())
}

/// ffmpeg on PATH, or in the usual Homebrew locations that GUI-launched shells miss
func findFFmpeg(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fallbackDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]
) -> String? {
    ((environment["PATH"] ?? "").split(separator: ":").map(String.init) + fallbackDirectories)
        .map { ($0 as NSString).appendingPathComponent("ffmpeg") }
        .first(where: isExecutableFile(at:))
}

/// Decodes APE or WavPack into a temporary FLAC at the fastest compression level, which is
/// removed with its directory when the scope ends. Core Audio then cuts it like any FLAC.
func decodedWithFFmpeg(_ source: String) -> Bracket<String, CueCutError> {
    BracketDo<CueCutError>()
        .bind { Bracket.fromAcquire { locateFFmpeg(for: source) } }
        .bind { _ in temporaryDirectory(prefix: "files-cut").mapError(CueCutError.fileSystem) }
        .bind { ffmpeg, directory in
            Bracket.fromAcquire { runFFmpeg(ffmpeg, decoding: source, into: directory) }
        }
        .map { _, _, decoded in decoded }
}

private func locateFFmpeg(for source: String) -> Result<String, CueCutError> {
    .fromOptional(findFFmpeg(), error: .ffmpegNotFound(source))
}

private func runFFmpeg(_ ffmpeg: String, decoding source: String, into directory: String)
    -> Result<String, CueCutError>
{
    let output = (directory as NSString).appendingPathComponent("decoded.flac")
    let errors = Pipe()
    let process = ffmpegProcess(ffmpeg, input: source, output: output, errors: errors)
    return Result { try process.run() }
        .mapError { CueCutError.ffmpegFailed(source, $0.localizedDescription) }
        .map { waitForExit(process, errors: errors) }
        .flatMap { message in
            process.terminationStatus == 0
                ? .success(output) : .failure(.ffmpegFailed(source, message))
        }
}

private func ffmpegProcess(_ ffmpeg: String, input: String, output: String, errors: Pipe)
    -> Process
{
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffmpeg)
    // The file: prefix stops ffmpeg from reading names like "pipe:x" as protocols
    process.arguments = [
        "-nostdin", "-loglevel", "error",
        "-i", "file:\(URL(fileURLWithPath: input).path(percentEncoded: false))",
        "-map", "0:a:0", "-c:a", "flac", "-compression_level", "0", "file:\(output)",
    ]
    process.standardError = errors
    process.standardOutput = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    return process
}

/// Drains stderr before waiting, so a chatty process can't fill the pipe and block, and
/// returns what it printed
private func waitForExit(_ process: Process, errors: Pipe) -> String {
    let message = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: message, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
