import Foundation

/// Two directory trees to compare, `left` and `right`, of `count` 4 KB files, ten per folder.
///
/// 80% of the files are the same on both sides, so their contents are read and compared;
/// 10% have the same size but a different last byte; and 10% are renamed on the right with
/// two letters swapped, so fuzzy matching has pairs to find.
///
/// Creating it is a benchmark's setup and removing it its teardown, so the path is chosen
/// when the benchmark is registered.
public struct DirectoryFixture: Sendable {
    public let root: String
    public let count: Int

    public var left: String { root + "/left" }
    public var right: String { root + "/right" }

    public init(count: Int) {
        self.count = count
        self.root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("files-benchmark-\(UUID().uuidString)")
    }

    /// Every relative path on the left, the paths `Ignore` is matched against
    public var leftPaths: [String] {
        (0..<count).map(Self.leftPath)
    }

    public func create() throws {
        for index in 0..<count {
            let contents = Data(repeating: UInt8(index % 251), count: 4096)
            try write(contents, to: left + "/" + Self.leftPath(index))
            switch index % 10 {
                case 8:
                    try write(contents.dropLast() + [255], to: right + "/" + Self.leftPath(index))
                case 9:
                    try write(contents, to: right + "/" + Self.renamedPath(index))
                default:
                    try write(contents, to: right + "/" + Self.leftPath(index))
            }
        }
    }

    public func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }

    private static func leftPath(_ index: Int) -> String {
        "album \(index / 10)/photo-\(index).jpg"
    }

    /// "phtoo-49.jpg": two letters swapped, which fuzzy matching at 0.8 still pairs up
    private static func renamedPath(_ index: Int) -> String {
        "album \(index / 10)/phtoo-\(index).jpg"
    }

    private func write(_ data: Data, to path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path))
    }
}
