#if canImport(AVFoundation)
import AVFoundation
import FP
import FPBracket

/// A track source open for reading in the sample format that carries its samples unchanged
struct OpenSource {
    let file: AVAudioFile
    let clientFormat: AVAudioCommonFormat
}

/// Opens a source for the length of a scope. APE and WavPack are decoded with ffmpeg first,
/// and the decoded copy is removed when the scope ends.
func openSource(_ path: String) -> Bracket<OpenSource, CueCutError> {
    readablePath(of: path)
        .flatMap { readable in Bracket.fromAcquire { open(readable, reportingAs: path) } }
}

private func readablePath(of path: String) -> Bracket<String, CueCutError> {
    needsFFmpeg(path) ? decodedWithFFmpeg(path) : .of(path)
}

private func open(_ readable: String, reportingAs path: String) -> Result<
    OpenSource, CueCutError
> {
    openAudioFile(at: readable)
        .flatMap { clientFormat(for: $0.fileFormat, path: path) }
        .bind { format in openAudioFile(at: readable, commonFormat: format) }
        .map { format, file in OpenSource(file: file, clientFormat: format) }
}

/// The sample format that carries the source's samples unchanged, so cuts are bit-exact. The
/// FLAC encoder also takes its bit depth from it: Int16 writes 16-bit FLAC, Int32 24-bit.
private func clientFormat(for format: AVAudioFormat, path: String) -> Result<
    AVAudioCommonFormat, CueCutError
> {
    // streamDescription points into `format`, which the parameter keeps alive
    let description = format.streamDescription.pointee
    switch description.mFormatID {
        case kAudioFormatLinearPCM:
            return .success(linearPCMFormat(description))

        case kAudioFormatFLAC:
            // FLAC reports the source bit depth with the Apple Lossless flags
            switch description.mFormatFlags {
                case kAppleLosslessFormatFlag_16BitSourceData:
                    return .success(.pcmFormatInt16)
                case kAppleLosslessFormatFlag_20BitSourceData,
                    kAppleLosslessFormatFlag_24BitSourceData:
                    return .success(.pcmFormatInt32)
                default:
                    // Core Audio can't write 32-bit FLAC
                    return .failure(.unsupportedAudio(path))
            }

        default:
            return .failure(.unsupportedAudio(path))
    }
}

private func linearPCMFormat(_ description: AudioStreamBasicDescription) -> AVAudioCommonFormat {
    if description.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
        return description.mBitsPerChannel > 32 ? .pcmFormatFloat64 : .pcmFormatFloat32
    }
    return description.mBitsPerChannel <= 16 ? .pcmFormatInt16 : .pcmFormatInt32
}
#endif
