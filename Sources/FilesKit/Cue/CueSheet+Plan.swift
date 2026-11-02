import FP
import Foundation

/// Where one track sits in its audio file, before it is named
private struct TrackSpan {
    let track: CueSheet.Track
    let source: AudioSource
    let start: CueTime
    let end: CueTime?
}

extension CueSheet {
    /// Works out the source, range, file name and tags of every track
    ///
    /// A track runs from its INDEX 01 to the next track's INDEX 01 in the same file, or to the
    /// end of its file, so pregaps stay with the track before them. The first track of each
    /// file starts at the beginning of the file, so no audio is dropped.
    /// - Parameter cuePath: Path of the cue sheet; audio files are looked up next to it
    public func plan(cuePath: String) -> Result<[CueTrack], CueSheetError> {
        guard !tracks.isEmpty else {
            return .failure(.noTracks)
        }
        return Array(tracks.indices)
            .traverse { span(ofTrackAt: $0, cuePath: cuePath) }
            .map(namedTracks)
    }

    private func span(ofTrackAt index: Int, cuePath: String) -> Result<TrackSpan, CueSheetError> {
        let track = tracks[index]
        return Result.fromOptional(
            track.start, error: CueSheetError.missingStart(track: track.number)
        )
        .bind { start in source(ofFile: start.file, cuePath: cuePath) }
        .bind { start, _ in end(ofTrackAt: index, startingAt: start) }
        .map { start, source, end in
            TrackSpan(
                track: track, source: source, start: startTime(ofTrackAt: index, start),
                end: end)
        }
    }

    private func source(ofFile file: Int, cuePath: String) -> Result<AudioSource, CueSheetError> {
        AudioSource.resolve(files[file], cuePath: cuePath, isOnlyFile: files.count == 1)
    }

    /// The first track of each file starts at the beginning of the file
    private func startTime(ofTrackAt index: Int, _ start: Position) -> CueTime {
        let isFirstInFile = index == 0 || tracks[index - 1].start?.file != start.file
        return isFirstInFile ? .zero : start.time
    }

    /// The next track's INDEX 01 when it is in the same file; nil runs to the end of the file
    private func end(ofTrackAt index: Int, startingAt start: Position) -> Result<
        CueTime?, CueSheetError
    > {
        guard index + 1 < tracks.count, let next = tracks[index + 1].start,
            next.file == start.file
        else {
            return .success(nil)
        }
        return next.time > start.time
            ? .success(next.time) : .failure(.tracksOutOfOrder(track: tracks[index + 1].number))
    }

    private func namedTracks(_ spans: [TrackSpan]) -> [CueTrack] {
        let width = TrackFileName.numberWidth(tracks.map(\.number))
        let names = spans.map { fileName(of: $0, width: width) } |> TrackFileName.deduplicated
        return zip(spans, names).map(cueTrack)
    }

    private func fileName(of span: TrackSpan, width: Int) -> String {
        TrackFileName.make(
            number: span.track.number,
            width: width,
            performer: span.track.performer == performer ? nil : span.track.performer,
            title: span.track.title,
            extension: span.source.outputExtension
        )
    }

    private func cueTrack(_ span: TrackSpan, fileName: String) -> CueTrack {
        CueTrack(
            number: span.track.number, source: span.source.path, start: span.start,
            end: span.end, fileName: fileName, tags: tags(for: span.track))
    }

    private func tags(for track: Track) -> AudioTags {
        AudioTags(
            title: track.title,
            artist: track.performer ?? performer,
            album: title,
            albumArtist: performer,
            composer: track.songwriter ?? songwriter,
            genre: genre,
            date: date,
            isrc: track.isrc,
            trackNumber: track.number,
            trackTotal: tracks.count,
            discNumber: discNumber,
            discTotal: totalDiscs
        )
    }
}
