import Foundation

/// Tags written to a cut track
public struct AudioTags: Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var composer: String?
    public var genre: String?
    public var date: String?
    public var isrc: String?
    public var trackNumber: Int?
    public var trackTotal: Int?
    public var discNumber: String?
    public var discTotal: String?

    public init(
        title: String? = nil, artist: String? = nil, album: String? = nil,
        albumArtist: String? = nil, composer: String? = nil, genre: String? = nil,
        date: String? = nil, isrc: String? = nil, trackNumber: Int? = nil,
        trackTotal: Int? = nil, discNumber: String? = nil, discTotal: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.composer = composer
        self.genre = genre
        self.date = date
        self.isrc = isrc
        self.trackNumber = trackNumber
        self.trackTotal = trackTotal
        self.discNumber = discNumber
        self.discTotal = discTotal
    }

    /// Vorbis comment fields in a fixed order, without empty values
    public var vorbisComments: [(key: String, value: String)] {
        let fields: [(String, String?)] = [
            ("TITLE", title),
            ("ARTIST", artist),
            ("ALBUM", album),
            ("ALBUMARTIST", albumArtist),
            ("COMPOSER", composer),
            ("GENRE", genre),
            ("DATE", date),
            ("ISRC", isrc),
            ("TRACKNUMBER", trackNumber.map(String.init)),
            ("TRACKTOTAL", trackTotal.map(String.init)),
            ("DISCNUMBER", discNumber),
            ("DISCTOTAL", discTotal),
        ]
        return fields.compactMap { key, value in
            value.flatMap { $0.isEmpty ? nil : (key, $0) }
        }
    }
}
