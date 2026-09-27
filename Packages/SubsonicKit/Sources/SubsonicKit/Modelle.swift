import Foundation

// **Die Antworten der Subsonic-Schnittstelle als Werte.**
//
// Die Feldnamen folgen der Spezifikation (subsonic.org, API 1.16.1) und den
// Ergänzungen von OpenSubsonic. Alles außer der Kennung ist wahlfrei: kein
// Server füllt alles, und was fehlt, darf die Antwort nicht umwerfen
// (siehe ``Feld``).

/// Ein Verweis auf einen Künstler innerhalb eines Albums oder Liedes.
public struct SubsonicVerweis: Sendable, Hashable, Decodable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        guard let id = c.text("id"), !id.isEmpty else { throw OhneKennung() }
        self.id = id
        name = c.text("name") ?? ""
    }
}

/// `ArtistID3`.
public struct SubsonicKuenstler: Sendable, Hashable, Decodable, Identifiable {
    public let id: String
    public let name: String
    public let coverArt: String?
    public let albumCount: Int?
    public let starred: Date?
    public let artistImageUrl: URL?
    public let sortName: String?

    public init(id: String, name: String, coverArt: String? = nil, albumCount: Int? = nil,
                starred: Date? = nil, artistImageUrl: URL? = nil, sortName: String? = nil) {
        self.id = id
        self.name = name
        self.coverArt = coverArt
        self.albumCount = albumCount
        self.starred = starred
        self.artistImageUrl = artistImageUrl
        self.sortName = sortName
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        guard let id = c.text("id"), !id.isEmpty else { throw OhneKennung() }
        self.id = id
        name = c.text("name") ?? ""
        coverArt = c.text("coverArt").flatMap { $0.isEmpty ? nil : $0 }
        albumCount = c.zahl("albumCount")
        starred = c.zeit("starred")
        artistImageUrl = c.text("artistImageUrl").flatMap { $0.isEmpty ? nil : URL(string: $0) }
        sortName = c.text("sortName")
    }
}

/// `AlbumID3` — und mit ``lieder`` zugleich `AlbumWithSongsID3`.
public struct SubsonicAlbum: Sendable, Hashable, Decodable, Identifiable {
    public let id: String
    public let name: String
    public let artist: String?
    public let artistId: String?
    public let displayArtist: String?
    public let artists: [SubsonicVerweis]
    public let coverArt: String?
    public let songCount: Int?
    /// Sekunden.
    public let duration: Int?
    public let playCount: Int?
    public let created: Date?
    public let starred: Date?
    /// Wann zuletzt gespielt — OpenSubsonic.
    public let played: Date?
    public let year: Int?
    public let genre: String?
    public let genres: [String]
    public let isCompilation: Bool?
    public let sortName: String?
    /// OpenSubsonic: `album`, `ep`, `single`, `live` … in der Schreibweise
    /// des Servers.
    public let releaseTypes: [String]
    /// Nur bei `getAlbum` gefüllt.
    public let lieder: [SubsonicLied]

    public init(id: String, name: String, artist: String? = nil, artistId: String? = nil,
                displayArtist: String? = nil, artists: [SubsonicVerweis] = [],
                coverArt: String? = nil, songCount: Int? = nil, duration: Int? = nil,
                playCount: Int? = nil, created: Date? = nil, starred: Date? = nil,
                played: Date? = nil, year: Int? = nil, genre: String? = nil,
                genres: [String] = [], isCompilation: Bool? = nil, sortName: String? = nil,
                releaseTypes: [String] = [], lieder: [SubsonicLied] = []) {
        self.id = id
        self.name = name
        self.artist = artist
        self.artistId = artistId
        self.displayArtist = displayArtist
        self.artists = artists
        self.coverArt = coverArt
        self.songCount = songCount
        self.duration = duration
        self.playCount = playCount
        self.created = created
        self.starred = starred
        self.played = played
        self.year = year
        self.genre = genre
        self.genres = genres
        self.isCompilation = isCompilation
        self.sortName = sortName
        self.releaseTypes = releaseTypes
        self.lieder = lieder
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        guard let id = c.text("id"), !id.isEmpty else { throw OhneKennung() }
        self.id = id
        // `name` bei ID3, `title` bei der alten Ordneransicht.
        name = c.text("name") ?? c.text("title") ?? c.text("album") ?? ""
        artist = c.text("artist")
        artistId = c.text("artistId")
        displayArtist = c.text("displayArtist")
        artists = c.liste("artists")
        coverArt = c.text("coverArt").flatMap { $0.isEmpty ? nil : $0 }
        songCount = c.zahl("songCount")
        duration = c.zahl("duration")
        playCount = c.zahl("playCount")
        created = c.zeit("created")
        starred = c.zeit("starred")
        played = c.zeit("played")
        year = c.zahl("year").flatMap { $0 > 0 ? $0 : nil }
        genre = c.text("genre").flatMap { $0.isEmpty ? nil : $0 }
        genres = c.namen("genres")
        isCompilation = c.wahr("isCompilation")
        sortName = c.text("sortName")
        releaseTypes = c.liste("releaseTypes", String.self).filter { !$0.isEmpty }
        lieder = c.liste("song")
    }

    /// Der Name, der unter dem Titel steht — `displayArtist` von OpenSubsonic,
    /// sonst `artist`.
    public var kuenstlerzeile: String? {
        if let d = displayArtist, !d.isEmpty { return d }
        if let a = artist, !a.isEmpty { return a }
        return artists.isEmpty ? nil : artists.map(\.name).joined(separator: ", ")
    }

    /// Alle Genres, das alte Einzelfeld eingeschlossen.
    public var alleGenres: [String] {
        if !genres.isEmpty { return genres }
        return genre.map { [$0] } ?? []
    }
}

/// `ReplayGain` von OpenSubsonic.
public struct SubsonicPegel: Sendable, Hashable, Decodable {
    public let trackGain: Double?
    public let albumGain: Double?
    public let trackPeak: Double?
    public let albumPeak: Double?

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        trackGain = c.kommazahl("trackGain")
        albumGain = c.kommazahl("albumGain")
        trackPeak = c.kommazahl("trackPeak")
        albumPeak = c.kommazahl("albumPeak")
    }
}

/// `Child` — ein Lied (oder ein Hörbuchteil, `type == "audiobook"`).
public struct SubsonicLied: Sendable, Hashable, Decodable, Identifiable {
    public let id: String
    public let parent: String?
    public let title: String
    public let album: String?
    public let albumId: String?
    public let artist: String?
    public let artistId: String?
    public let displayArtist: String?
    public let artists: [SubsonicVerweis]
    public let displayAlbumArtist: String?
    public let albumArtists: [SubsonicVerweis]
    public let track: Int?
    public let discNumber: Int?
    public let year: Int?
    public let genre: String?
    public let coverArt: String?
    /// Byte.
    public let size: Int?
    public let contentType: String?
    public let suffix: String?
    public let transcodedContentType: String?
    public let transcodedSuffix: String?
    /// Sekunden.
    public let duration: Int?
    /// kbit/s.
    public let bitRate: Int?
    public let bitDepth: Int?
    /// Hz.
    public let samplingRate: Int?
    public let channelCount: Int?
    public let playCount: Int?
    public let played: Date?
    public let created: Date?
    public let starred: Date?
    public let type: String?
    public let isVideo: Bool?
    public let replayGain: SubsonicPegel?

    public init(id: String, title: String, parent: String? = nil, album: String? = nil,
                albumId: String? = nil, artist: String? = nil, artistId: String? = nil,
                displayArtist: String? = nil, artists: [SubsonicVerweis] = [],
                displayAlbumArtist: String? = nil, albumArtists: [SubsonicVerweis] = [],
                track: Int? = nil, discNumber: Int? = nil, year: Int? = nil,
                genre: String? = nil, coverArt: String? = nil, size: Int? = nil,
                contentType: String? = nil, suffix: String? = nil,
                transcodedContentType: String? = nil, transcodedSuffix: String? = nil,
                duration: Int? = nil, bitRate: Int? = nil, bitDepth: Int? = nil,
                samplingRate: Int? = nil, channelCount: Int? = nil, playCount: Int? = nil,
                played: Date? = nil, created: Date? = nil, starred: Date? = nil,
                type: String? = nil, isVideo: Bool? = nil, replayGain: SubsonicPegel? = nil) {
        self.id = id
        self.parent = parent
        self.title = title
        self.album = album
        self.albumId = albumId
        self.artist = artist
        self.artistId = artistId
        self.displayArtist = displayArtist
        self.artists = artists
        self.displayAlbumArtist = displayAlbumArtist
        self.albumArtists = albumArtists
        self.track = track
        self.discNumber = discNumber
        self.year = year
        self.genre = genre
        self.coverArt = coverArt
        self.size = size
        self.contentType = contentType
        self.suffix = suffix
        self.transcodedContentType = transcodedContentType
        self.transcodedSuffix = transcodedSuffix
        self.duration = duration
        self.bitRate = bitRate
        self.bitDepth = bitDepth
        self.samplingRate = samplingRate
        self.channelCount = channelCount
        self.playCount = playCount
        self.played = played
        self.created = created
        self.starred = starred
        self.type = type
        self.isVideo = isVideo
        self.replayGain = replayGain
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        guard let id = c.text("id"), !id.isEmpty else { throw OhneKennung() }
        self.id = id
        parent = c.text("parent")
        title = c.text("title") ?? c.text("name") ?? ""
        album = c.text("album")
        albumId = c.text("albumId")
        artist = c.text("artist")
        artistId = c.text("artistId")
        displayArtist = c.text("displayArtist")
        artists = c.liste("artists")
        displayAlbumArtist = c.text("displayAlbumArtist")
        albumArtists = c.liste("albumArtists")
        track = c.zahl("track").flatMap { $0 > 0 ? $0 : nil }
        discNumber = c.zahl("discNumber").flatMap { $0 > 0 ? $0 : nil }
        year = c.zahl("year").flatMap { $0 > 0 ? $0 : nil }
        genre = c.text("genre").flatMap { $0.isEmpty ? nil : $0 }
        coverArt = c.text("coverArt").flatMap { $0.isEmpty ? nil : $0 }
        size = c.zahl("size")
        contentType = c.text("contentType")
        suffix = c.text("suffix")
        transcodedContentType = c.text("transcodedContentType")
        transcodedSuffix = c.text("transcodedSuffix")
        duration = c.zahl("duration")
        bitRate = c.zahl("bitRate").flatMap { $0 > 0 ? $0 : nil }
        // Navidrome schreibt 0, wenn es die Tiefe nicht kennt (verlustbehaftete
        // Formate haben keine) — 0 ist also „unbekannt", nicht „null Bit".
        bitDepth = c.zahl("bitDepth").flatMap { $0 > 0 ? $0 : nil }
        samplingRate = c.zahl("samplingRate").flatMap { $0 > 0 ? $0 : nil }
        channelCount = c.zahl("channelCount").flatMap { $0 > 0 ? $0 : nil }
        playCount = c.zahl("playCount")
        played = c.zeit("played")
        created = c.zeit("created")
        starred = c.zeit("starred")
        type = c.text("type")
        isVideo = c.wahr("isVideo")
        replayGain = try? c.decodeIfPresent(SubsonicPegel.self, forKey: Feld("replayGain"))
    }

    public var kuenstlerzeile: String? {
        if let d = displayArtist, !d.isEmpty { return d }
        if let a = artist, !a.isEmpty { return a }
        return artists.isEmpty ? nil : artists.map(\.name).joined(separator: ", ")
    }
}

/// `ArtistWithAlbumsID3`.
public struct SubsonicKuenstlerMitAlben: Sendable, Hashable, Decodable {
    public let kuenstler: SubsonicKuenstler
    public let alben: [SubsonicAlbum]

    public init(from decoder: any Decoder) throws {
        kuenstler = try SubsonicKuenstler(from: decoder)
        let c = try decoder.container(keyedBy: Feld.self)
        alben = c.liste("album")
    }
}

/// `Playlist` — mit ``lieder`` zugleich `PlaylistWithSongs`.
public struct SubsonicPlaylist: Sendable, Hashable, Decodable, Identifiable {
    public let id: String
    public let name: String
    public let comment: String?
    public let owner: String?
    public let isPublic: Bool?
    public let songCount: Int?
    /// Sekunden.
    public let duration: Int?
    public let created: Date?
    public let changed: Date?
    public let coverArt: String?
    public let lieder: [SubsonicLied]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        guard let id = c.text("id"), !id.isEmpty else { throw OhneKennung() }
        self.id = id
        name = c.text("name") ?? ""
        comment = c.text("comment")
        owner = c.text("owner")
        isPublic = c.wahr("public")
        songCount = c.zahl("songCount")
        duration = c.zahl("duration")
        created = c.zeit("created")
        changed = c.zeit("changed")
        coverArt = c.text("coverArt").flatMap { $0.isEmpty ? nil : $0 }
        lieder = c.liste("entry")
    }
}

/// `searchResult3`.
public struct SubsonicSuchergebnis: Sendable, Hashable, Decodable {
    public let kuenstler: [SubsonicKuenstler]
    public let alben: [SubsonicAlbum]
    public let lieder: [SubsonicLied]

    public init(kuenstler: [SubsonicKuenstler] = [], alben: [SubsonicAlbum] = [],
                lieder: [SubsonicLied] = []) {
        self.kuenstler = kuenstler
        self.alben = alben
        self.lieder = lieder
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        kuenstler = c.liste("artist")
        alben = c.liste("album")
        lieder = c.liste("song")
    }
}

/// Eine Zeile eines Liedtexts von `getLyricsBySongId`.
public struct SubsonicLiedtextzeile: Sendable, Hashable, Decodable {
    /// Millisekunden ab Liedbeginn, bei ungetaktetem Text `nil`.
    public let start: Int?
    public let value: String

    public init(start: Int?, value: String) {
        self.start = start
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        start = c.zahl("start")
        value = c.text("value") ?? ""
    }
}

/// `structuredLyrics` — ein Liedtext in einer Sprache.
public struct SubsonicLiedtext: Sendable, Hashable, Decodable {
    public let lang: String?
    public let synced: Bool
    /// Millisekunden, um die alle Zeiten zu verschieben sind. Positiv heißt:
    /// der Text kommt **früher** (so steht es in der OpenSubsonic-Beschreibung).
    public let offset: Int
    public let displayArtist: String?
    public let displayTitle: String?
    public let zeilen: [SubsonicLiedtextzeile]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        lang = c.text("lang")
        synced = c.wahr("synced") ?? false
        offset = c.zahl("offset") ?? 0
        displayArtist = c.text("displayArtist")
        displayTitle = c.text("displayTitle")
        zeilen = c.liste("line")
    }
}

/// `lyrics` von `getLyrics` — nur Text, ohne Zeiten.
public struct SubsonicEinfacherLiedtext: Sendable, Hashable, Decodable {
    public let artist: String?
    public let title: String?
    public let value: String

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        artist = c.text("artist")
        title = c.text("title")
        value = c.text("value") ?? ""
    }
}

/// Eine OpenSubsonic-Erweiterung, etwa `songLyrics`.
public struct SubsonicErweiterung: Sendable, Hashable, Decodable {
    public let name: String
    public let versions: [Int]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        name = c.text("name") ?? ""
        versions = c.liste("versions", Int.self)
    }
}

/// Was jede Antwort über den Server verrät.
public struct SubsonicServer: Sendable, Hashable {
    /// Die Fassung der Schnittstelle, etwa `1.16.1`.
    public let version: String?
    /// Der Name der Umsetzung, etwa `navidrome` — nur bei OpenSubsonic.
    public let type: String?
    public let serverVersion: String?
    public let openSubsonic: Bool

    public init(version: String?, type: String?, serverVersion: String?, openSubsonic: Bool) {
        self.version = version
        self.type = type
        self.serverVersion = serverVersion
        self.openSubsonic = openSubsonic
    }

    /// Wie der Server sich nennt: „Navidrome 0.64.0", sonst „Subsonic 1.16.1".
    public var anzeigename: String {
        if let type, !type.isEmpty {
            let name = type.prefix(1).uppercased() + type.dropFirst()
            if let serverVersion, let kurz = serverVersion.split(separator: " ").first {
                return "\(name) \(kurz)"
            }
            return name
        }
        return version.map { "Subsonic \($0)" } ?? "Subsonic"
    }
}
