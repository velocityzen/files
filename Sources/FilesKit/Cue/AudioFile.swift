#if canImport(AVFoundation)
import AVFoundation
import FP
import FPBracket

/// Opens an audio file in its default processing format, to inspect it
func openAudioFile(at path: String) -> Result<AVAudioFile, CueCutError> {
    Result { try AVAudioFile(forReading: URL(fileURLWithPath: path)) }
        .mapError { audioError($0, path: path) }
}

/// Opens an audio file to read deinterleaved samples in `commonFormat`
func openAudioFile(at path: String, commonFormat: AVAudioCommonFormat) -> Result<
    AVAudioFile, CueCutError
> {
    Result {
        try AVAudioFile(
            forReading: URL(fileURLWithPath: path), commonFormat: commonFormat, interleaved: false)
    }
    .mapError { audioError($0, path: path) }
}

/// An audio file being written; it is closed, and so complete on disk, when the scope ends.
/// The path's extension picks the file type.
func audioOutput(
    at path: String,
    settings: [String: Any],
    commonFormat: AVAudioCommonFormat
) -> Bracket<AVAudioFile, CueCutError> {
    Bracket(
        acquire: {
            Result {
                try AVAudioFile(
                    forWriting: URL(fileURLWithPath: path), settings: settings,
                    commonFormat: commonFormat, interleaved: false)
            }
            .mapError { audioError($0, path: path) }
        },
        dispose: { file in
            file.close()
            return .success(())
        }
    )
}

func makePCMBuffer(for format: AVAudioFormat, capacity: AVAudioFrameCount, path: String)
    -> Result<AVAudioPCMBuffer, CueCutError>
{
    .fromOptional(
        AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity),
        error: .unsupportedAudio(path))
}

func readFrames(
    _ count: AVAudioFrameCount,
    from file: AVAudioFile,
    into buffer: AVAudioPCMBuffer
) -> Result<Void, CueCutError> {
    Result { try file.read(into: buffer, frameCount: count) }
        .mapError { audioError($0, path: file.url.path(percentEncoded: false)) }
}

func writeFrames(_ buffer: AVAudioPCMBuffer, to file: AVAudioFile) -> Result<Void, CueCutError> {
    Result { try file.write(from: buffer) }
        .mapError { audioError($0, path: file.url.path(percentEncoded: false)) }
}

private func audioError(_ error: any Error, path: String) -> CueCutError {
    .audio(path: path, reason: error.localizedDescription)
}
#endif
