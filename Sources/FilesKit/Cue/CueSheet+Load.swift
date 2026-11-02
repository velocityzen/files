import FP
import Foundation

extension CueSheet {
    /// A cue sheet and the text encoding it was read with
    public typealias Loaded = (sheet: CueSheet, encoding: String.Encoding)

    /// Reads and parses a cue sheet file
    /// - Parameter encoding: Text encoding to use; when nil, UTF-8 is tried first, then the
    ///   encoding is detected (macOS only), since many cue sheets use legacy code pages
    public static func load(
        from path: String,
        encoding: String.Encoding? = nil
    ) -> Result<Loaded, CueSheetError> {
        readCueFile(at: path)
            .flatMap { decode($0, encoding: encoding, path: path) }
            .bind { decoded in parse(decoded.text) }
            .map { decoded, sheet in (sheet, decoded.encoding) }
    }

    private static func readCueFile(at path: String) -> Result<Data, CueSheetError> {
        fileContents(at: path).mapError { _ in .unreadable(path) }
    }

    private static func decode(
        _ data: Data,
        encoding: String.Encoding?,
        path: String
    ) -> Result<DecodedText, CueSheetError> {
        let decoded =
            if let encoding {
                DecodedText(data, encoding: encoding)
            } else {
                DecodedText(data, encoding: .utf8) ?? DecodedText(detecting: data)
            }
        return .fromOptional(decoded, error: .unknownEncoding(path))
    }
}

/// Text decoded from bytes, with the encoding that decoded it
private struct DecodedText {
    let text: String
    let encoding: String.Encoding

    init?(_ data: Data, encoding: String.Encoding) {
        guard let text = String(data: data, encoding: encoding) else {
            return nil
        }
        self.text = text
        self.encoding = encoding
    }

    /// Detects legacy code pages such as Windows-1251 or Shift JIS (macOS only)
    init?(detecting data: Data) {
        #if canImport(Darwin)
        var converted: NSString?
        let detected = NSString.stringEncoding(
            for: data,
            encodingOptions: [.allowLossyKey: false],
            convertedString: &converted,
            usedLossyConversion: nil
        )
        guard detected != 0, let converted else {
            return nil
        }
        self.text = converted as String
        self.encoding = String.Encoding(rawValue: detected)
        #else
        return nil
        #endif
    }
}
