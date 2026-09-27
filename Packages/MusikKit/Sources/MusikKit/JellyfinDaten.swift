import Foundation
import SubsonicKit

// **Jellyfins Antworten, soweit Musik sie braucht.**
//
// Eigene Typen statt `JellyfinKit.Item`: der Player-Typ trägt Filmfelder und
// kennt weder `AlbumArtists` noch `ArtistItems` noch die Tonspur einer
// Audiodatei. Jedes Feld ist wahlfrei und wird einzeln gelesen — ein Feld mit
// unerwartetem Typ lässt nur dieses Feld leer, nicht die ganze Liste
// (dieselbe Regel wie in SubsonicKit, `Nachsicht.swift`).

struct JSchluessel: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer where Key == JSchluessel {
    func wert<T: Decodable>(_ name: String, _ typ: T.Type = T.self) -> T? {
        (try? decodeIfPresent(T.self, forKey: JSchluessel(name))) ?? nil
    }

    func zahl(_ name: String) -> Int? {
        if let i = wert(name, Int.self) { return i }
        if let d = wert(name, Double.self), d.isFinite, abs(d) < 9e18 { return Int(d) }
        return nil
    }

    func zahl64(_ name: String) -> Int64? {
        if let i = wert(name, Int64.self) { return i }
        if let d = wert(name, Double.self), d.isFinite, abs(d) < 9e18 { return Int64(d) }
        return nil
    }

    func liste<T: Decodable>(_ name: String, _ typ: T.Type = T.self) -> [T] {
        (wert(name, [Vielleicht<T>].self) ?? []).compactMap(\.wert)
    }
}

/// Ein Listeneintrag, der beim Lesen nicht wirft.
struct Vielleicht<T: Decodable>: Decodable {
    let wert: T?
    init(from decoder: any Decoder) throws { wert = try? T(from: decoder) }
}

struct JVerweis: Decodable, Sendable {
    let id: String
    let name: String
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: JSchluessel.self)
        guard let id = c.wert("Id", String.self) else { throw DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: "Id")) }
        self.id = id
        name = c.wert("Name", String.self) ?? ""
    }
}

struct JNutzerdaten: Decodable, Sendable {
    let favorit: Bool
    let gespielt: Bool
    let zaehler: Int?
    let zuletzt: Date?
    let stelleTicks: Int64?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: JSchluessel.self)
        favorit = c.wert("IsFavorite", Bool.self) ?? false
        gespielt = c.wert("Played", Bool.self) ?? false
        zaehler = c.zahl("PlayCount")
        zuletzt = c.wert("LastPlayedDate", String.self).flatMap(JDatum.lesen)
        stelleTicks = c.zahl64("PlaybackPositionTicks")
    }
}

struct JStrom: Decodable, Sendable {
    let typ: String?
    let codec: String?
    let bitrate: Int?
    let bitTiefe: Int?
    let abtastrate: Int?
    let kanaele: Int?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: JSchluessel.self)
        typ = c.wert("Type", String.self)
        codec = c.wert("Codec", String.self)
        bitrate = c.zahl("BitRate")
        bitTiefe = c.zahl("BitDepth")
        abtastrate = c.zahl("SampleRate")
        kanaele = c.zahl("Channels")
    }
}

struct JQuelle: Decodable, Sendable {
    let id: String?
    let behaelter: String?
    let pfad: String?
    let bitrate: Int?
    let groesse: Int64?
    let stroeme: [JStrom]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: JSchluessel.self)
        id = c.wert("Id", String.self)
        behaelter = c.wert("Container", String.self)
        pfad = c.wert("Path", String.self)
        bitrate = c.zahl("Bitrate")
        groesse = c.zahl64("Size")
        stroeme = c.liste("MediaStreams")
    }
}

struct JEintrag: Decodable, Sendable {
    let id: String
    let name: String
    let typ: String?
    let albumKuenstler: String?
    let albumKuenstlerListe: [JVerweis]
    let kuenstlerNamen: [String]
    let kuenstlerListe: [JVerweis]
    let album: String?
    let albumID: String?
    let albumBildmarke: String?
    let elternID: String?
    let nummer: Int?
    let cd: Int?
    let jahr: Int?
    let laufzeitTicks: Int64?
    let kinder: Int?
    let genres: [String]
    let bildmarken: [String: String]
    let hintergrundmarken: [String]
    let nutzer: JNutzerdaten?
    let quellen: [JQuelle]
    let angelegt: Date?
    let medienart: String?
    let hatLiedtext: Bool?
    let behaelter: String?
    let pfad: String?
    /// `NormalizationGain`, dB (Jellyfin 10.9+).
    let pegel: Double?
    /// `CollectionType` einer Bibliothek — „music", „books" …
    let sammlungsart: String?
    /// In einer Playlist: die Kennung des Eintrags.
    let eintragID: String?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: JSchluessel.self)
        guard let id = c.wert("Id", String.self), !id.isEmpty else {
            throw DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: "Id"))
        }
        self.id = id
        name = c.wert("Name", String.self) ?? ""
        typ = c.wert("Type", String.self)
        albumKuenstler = c.wert("AlbumArtist", String.self)
        albumKuenstlerListe = c.liste("AlbumArtists")
        kuenstlerNamen = c.wert("Artists", [String].self) ?? []
        kuenstlerListe = c.liste("ArtistItems")
        album = c.wert("Album", String.self)
        albumID = c.wert("AlbumId", String.self)
        albumBildmarke = c.wert("AlbumPrimaryImageTag", String.self)
        elternID = c.wert("ParentId", String.self)
        nummer = c.zahl("IndexNumber")
        cd = c.zahl("ParentIndexNumber")
        jahr = c.zahl("ProductionYear")
        laufzeitTicks = c.zahl64("RunTimeTicks")
        kinder = c.zahl("ChildCount") ?? c.zahl("SongCount")
        genres = c.wert("Genres", [String].self) ?? []
        bildmarken = c.wert("ImageTags", [String: String].self) ?? [:]
        hintergrundmarken = c.wert("BackdropImageTags", [String].self) ?? []
        nutzer = c.wert("UserData", JNutzerdaten.self)
        quellen = c.liste("MediaSources")
        angelegt = c.wert("DateCreated", String.self).flatMap(JDatum.lesen)
        medienart = c.wert("MediaType", String.self)
        hatLiedtext = c.wert("HasLyrics", Bool.self)
        behaelter = c.wert("Container", String.self)
        pfad = c.wert("Path", String.self)
        pegel = c.wert("NormalizationGain", Double.self).flatMap { $0.isFinite ? $0 : nil }
        sammlungsart = c.wert("CollectionType", String.self)
        eintragID = c.wert("PlaylistItemId", String.self)
    }

    var dauer: TimeInterval? {
        laufzeitTicks.map { TimeInterval($0) / 10_000_000 }.flatMap { $0 > 0 ? $0 : nil }
    }
}

struct JListe: Decodable, Sendable {
    let eintraege: [JEintrag]
    let gesamt: Int?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: JSchluessel.self)
        eintraege = c.liste("Items")
        gesamt = c.zahl("TotalRecordCount")
    }
}

/// `/Audio/{id}/Lyrics`.
struct JLiedtext: Decodable, Sendable {
    struct Zeile: Decodable, Sendable {
        let text: String
        let startTicks: Int64?
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: JSchluessel.self)
            text = c.wert("Text", String.self) ?? ""
            startTicks = c.zahl64("Start")
        }
    }
    let zeilen: [Zeile]
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: JSchluessel.self)
        zeilen = c.liste("Lyrics")
    }
}

/// Jellyfin schreibt Zeiten als ISO 8601 mit bis zu sieben Nachkommastellen —
/// dieselbe nachsichtige Lesart wie bei Subsonic (``Zeitangabe``).
enum JDatum {
    static func lesen(_ text: String) -> Date? {
        Zeitangabe.lesen(text)
    }
}
