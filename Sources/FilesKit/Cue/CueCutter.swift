#if canImport(AVFoundation)
import AVFoundation
import FP
import FPBracket
import Foundation

/// Frames copied per read
private let chunkFrames: AVAudioFrameCount = 65_536

/// A run of consecutive tracks that share a source, so each source is opened once
private struct SourceGroup {
    let source: String
    var tracks: [CueTrack]
}

/// Where tracks are written and what may be replaced there
private struct CutTarget {
    let directory: String
    let overwrite: Bool
    /// Every source, compared as paths; a source is never written over
    let sources: Set<String>
}

/// Cuts tracks out of their sources one at a time
///
/// Samples are copied in the source's own integer or float format, so cuts are bit-exact
/// and keep the source bit depth. FLAC outputs get the track's tags. APE and WavPack
/// sources are decoded with ffmpeg first and written as FLAC.
/// - Parameter overwrite: Replace track files that already exist
/// - Returns: A stream with one result per track, in order, as each one finishes
public func cutTracks(
    _ tracks: [CueTrack],
    to outputDirectory: String,
    overwrite: Bool = false
) -> AsyncStream<CueTrackResult> {
    let target = CutTarget(
        directory: outputDirectory, overwrite: overwrite,
        sources: Set(tracks.map { comparablePath($0.source) }))

    return AsyncStream { continuation in
        Task.detached {
            createDirectory(at: outputDirectory)
                .mapError(CueCutError.fileSystem)
                .match(
                    { _ in cutGroups(groupedBySource(tracks), to: target, continuation) },
                    { fail(tracks, with: $0, continuation) }
                )
            continuation.finish()
        }
    }
}

private func groupedBySource(_ tracks: [CueTrack]) -> [SourceGroup] {
    tracks.reduce(into: []) { groups, track in
        if groups.last?.source == track.source {
            groups[groups.count - 1].tracks.append(track)
        } else {
            groups.append(SourceGroup(source: track.source, tracks: [track]))
        }
    }
}

private func cutGroups(
    _ groups: [SourceGroup],
    to target: CutTarget,
    _ continuation: AsyncStream<CueTrackResult>.Continuation
) {
    for group in groups where !Task.isCancelled {
        let withSource = openSource(group.source)
        withSource { cut(group.tracks, from: $0, to: target, continuation) }
            .match({ _ in }, { fail(group.tracks, with: $0, continuation) })
    }
}

/// Cuts each track from the open source, reporting each one as it finishes
private func cut(
    _ tracks: [CueTrack],
    from source: OpenSource,
    to target: CutTarget,
    _ continuation: AsyncStream<CueTrackResult>.Continuation
) -> Result<Void, CueCutError> {
    for track in tracks where !Task.isCancelled {
        continuation.yield(
            cutTrack(track, from: source, to: target)
                .mapError { CueTrackError(track: track, error: $0) })
    }
    return .success(())
}

private func fail(
    _ tracks: [CueTrack],
    with error: CueCutError,
    _ continuation: AsyncStream<CueTrackResult>.Continuation
) {
    for track in tracks {
        continuation.failure(CueTrackError(track: track, error: error))
    }
}

private func cutTrack(_ track: CueTrack, from source: OpenSource, to target: CutTarget)
    -> Result<CueTrackOutput, CueCutError>
{
    let destination = URL(fileURLWithPath: target.directory).appending(path: track.fileName)
        .path(percentEncoded: false)
    return checkDestination(destination, in: target)
        .flatMap { _ in frameRange(of: track, in: source.file) }
        .bind { range in writeTrack(range, from: source, tags: track.tags, to: destination) }
        .map { range, _ in
            CueTrackOutput(
                track: track, path: destination, frames: range.upperBound - range.lowerBound)
        }
}

private func checkDestination(_ destination: String, in target: CutTarget) -> Result<
    Void, CueCutError
> {
    if target.sources.contains(comparablePath(destination)) {
        return .failure(.outputIsSource(destination))
    }
    if !target.overwrite && fileExists(at: destination) {
        return .failure(.outputExists(destination))
    }
    return .success(())
}

/// The track's frames, with an end past the file clamped to the file
private func frameRange(of track: CueTrack, in file: AVAudioFile) -> Result<
    Range<AVAudioFramePosition>, CueCutError
> {
    let sampleRate = file.fileFormat.sampleRate
    let start = track.start.samples(atSampleRate: sampleRate)
    let end = min(track.end?.samples(atSampleRate: sampleRate) ?? file.length, file.length)
    return start < end ? .success(start..<end) : .failure(.startPastEnd(track: track.number))
}

/// Writes the track next to the destination and moves it into place only once it is
/// complete and tagged, so a failed cut never touches an existing file
private func writeTrack(
    _ range: Range<AVAudioFramePosition>,
    from source: OpenSource,
    tags: AudioTags,
    to destination: String
) -> Result<Void, CueCutError> {
    let withTemporaryFile = temporaryFile(nextTo: destination).mapError(CueCutError.fileSystem)
    return withTemporaryFile { temporary in
        writeAudio(range, from: source, to: temporary)
            .flatMap { _ in tag(temporary, with: tags) }
            .flatMap { _ in moveIntoPlace(temporary, destination) }
    }
}

private func writeAudio(
    _ range: Range<AVAudioFramePosition>,
    from source: OpenSource,
    to path: String
) -> Result<Void, CueCutError> {
    let withOutput = audioOutput(
        at: path, settings: source.file.fileFormat.settings, commonFormat: source.clientFormat)
    return withOutput { copyFrames(range, from: source.file, to: $0) }
}

private func copyFrames(
    _ range: Range<AVAudioFramePosition>,
    from input: AVAudioFile,
    to output: AVAudioFile
) -> Result<Void, CueCutError> {
    input.framePosition = range.lowerBound
    return makePCMBuffer(
        for: input.processingFormat, capacity: chunkFrames,
        path: input.url.path(percentEncoded: false)
    )
    .flatMap { buffer in
        chunks(of: range).traverse { copyChunk($0, from: input, to: output, buffer) }
    }
    .asUnit()
}

/// Frame counts that cover the range, one read each
private func chunks(of range: Range<AVAudioFramePosition>) -> [AVAudioFrameCount] {
    stride(from: range.lowerBound, to: range.upperBound, by: Int(chunkFrames))
        .map { AVAudioFrameCount(min(AVAudioFramePosition(chunkFrames), range.upperBound - $0)) }
}

private func copyChunk(
    _ frames: AVAudioFrameCount,
    from input: AVAudioFile,
    to output: AVAudioFile,
    _ buffer: AVAudioPCMBuffer
) -> Result<Void, CueCutError> {
    readFrames(frames, from: input, into: buffer)
        .flatMap { _ in writeFrames(buffer, to: output) }
}

/// FLAC tracks get their tags; WAV and AIFF tracks are left untagged
private func tag(_ path: String, with tags: AudioTags) -> Result<Void, CueCutError> {
    guard (path as NSString).pathExtension.lowercased() == "flac" else {
        return .success(())
    }
    return FLACTags.write(tags.vorbisComments, to: path).mapError(CueCutError.tags)
}

private func moveIntoPlace(_ temporary: String, _ destination: String) -> Result<
    Void, CueCutError
> {
    moveReplacingItem(at: temporary, to: destination).mapError(CueCutError.fileSystem)
}

/// Path form used to tell whether two paths name the same file on a case-insensitive volume
private func comparablePath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        .path(percentEncoded: false).lowercased()
}
#endif
