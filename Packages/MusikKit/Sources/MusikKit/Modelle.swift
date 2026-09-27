import Foundation

// **Die Modelle, die beide Server gemeinsam haben.**
//
// Jellyfin und Subsonic beschreiben dieselben Dinge verschieden — hier steht
// die eine Form, mit der die Oberfläche rechnet. Was ein Server nicht kennt,
// bleibt leer; die Ansicht lässt es dann weg, statt „0" oder „unbekannt" zu
// zeigen.
//
// Alles `Codable`, weil die Ablage (geladene Lieder, „Zuletzt gehört") diese
// Werte über Fassungen hinweg lesen muss. Die Decoder stehen deshalb von Hand
// da und lesen jeden Wert mit `decodeIfPresent` gegen seine Vorgabe
// (`Fallen/ablage.md`, „Ein fehlender Schlüssel wirft die ganze Datei weg").

/// Welcher Server dahintersteht.
public enum Serverart: String, Sendable, Codable, Hashable {
    case jellyfin
    case subsonic
}

/// Ein Bild auf dem Server: bei Jellyfin die Kennung des Eintrags samt
/// `tag`, bei Subsonic die `coverArt`-Kennung.
public struct Bildbezug: Hashable, Sendable, Codable {
    public let id: String
    public let marke: String?
    /// Jellyfins breites Hintergrundbild (`Backdrop`) statt der Hülle.
    public let hintergrund: Bool

    public init(id: String, marke: String? = nil, hintergrund: Bool = false) {
        self.id = id
        self.marke = marke
        self.hintergrund = hintergrund
    }

    private enum K: String, CodingKey { case id, marke, hintergrund }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        marke = try? c.decodeIfPresent(String.self, forKey: .marke)
        hintergrund = (try? c.decodeIfPresent(Bool.self, forKey: .hintergrund)) ?? false
    }
}

/// Das Format einer Datei, soweit der Server es nennt.
public struct Tonformat: Hashable, Sendable, Codable {
    /// `flac`, `mp3`, `aac`, `alac`, `opus`, `vorbis`, `pcm_s16le` …
    public var codec: String?
    /// Dateiendung bzw. Behälter: `flac`, `mp3`, `m4a`, `ogg`, `wav` …
    public var behaelter: String?
    /// kbit/s.
    public var bitrate: Int?
    public var bitTiefe: Int?
    /// Hz.
    public var abtastrate: Int?
    public var kanaele: Int?
    /// Der Medientyp, wie der Server ihn angibt (`audio/flac`).
    public var mime: String?

    public init(codec: String? = nil, behaelter: String? = nil, bitrate: Int? = nil,
                bitTiefe: Int? = nil, abtastrate: Int? = nil, kanaele: Int? = nil,
                mime: String? = nil) {
        self.codec = codec
        self.behaelter = behaelter
        self.bitrate = bitrate
        self.bitTiefe = bitTiefe
        self.abtastrate = abtastrate
        self.kanaele = kanaele
        self.mime = mime
    }
}

/// Wie ein Album erschienen ist, soweit der Server es weiß (OpenSubsonic).
public enum Albumart: String, Sendable, Codable, Hashable {
    case album, ep, single, live, zusammenstellung
}

public struct Album: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var titel: String
    /// Die Zeile unter dem Titel — bei mehreren Künstlern alle.
    public var kuenstler: String?
    /// Die Künstler einzeln, wie der Server sie nennt (``kuenstlernamen``).
    public var kuenstlerliste: [String]
    public var kuenstlerID: String?
    public var jahr: Int?
    public var genres: [String]
    public var liedzahl: Int?
    /// Sekunden.
    public var dauer: TimeInterval?
    public var bild: Bildbezug?
    public var favorit: Bool
    /// Wie oft gehört — die eigene Zählung des Servers.
    public var gespielt: Int?
    public var zuletztGespielt: Date?
    public var hinzugefuegt: Date?
    public var art: Albumart?

    public init(id: String, titel: String, kuenstler: String? = nil, kuenstlerID: String? = nil,
                jahr: Int? = nil, genres: [String] = [], liedzahl: Int? = nil,
                dauer: TimeInterval? = nil, bild: Bildbezug? = nil, favorit: Bool = false,
                gespielt: Int? = nil, zuletztGespielt: Date? = nil, hinzugefuegt: Date? = nil,
                art: Albumart? = nil, kuenstlerliste: [String] = []) {
        self.id = id
        self.titel = titel
        self.kuenstler = kuenstler
        self.kuenstlerliste = kuenstlerliste
        self.kuenstlerID = kuenstlerID
        self.jahr = jahr
        self.genres = genres
        self.liedzahl = liedzahl
        self.dauer = dauer
        self.bild = bild
        self.favorit = favorit
        self.gespielt = gespielt
        self.zuletztGespielt = zuletztGespielt
        self.hinzugefuegt = hinzugefuegt
        self.art = art
    }

    private enum K: String, CodingKey {
        case id, titel, kuenstler, kuenstlerliste, kuenstlerID, jahr, genres, liedzahl, dauer, bild, favorit,
             gespielt, zuletztGespielt, hinzugefuegt, art
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        titel = (try? c.decodeIfPresent(String.self, forKey: .titel)) ?? ""
        kuenstler = try? c.decodeIfPresent(String.self, forKey: .kuenstler)
        kuenstlerliste = (try? c.decodeIfPresent([String].self, forKey: .kuenstlerliste)) ?? []
        kuenstlerID = try? c.decodeIfPresent(String.self, forKey: .kuenstlerID)
        jahr = try? c.decodeIfPresent(Int.self, forKey: .jahr)
        genres = (try? c.decodeIfPresent([String].self, forKey: .genres)) ?? []
        liedzahl = try? c.decodeIfPresent(Int.self, forKey: .liedzahl)
        dauer = try? c.decodeIfPresent(TimeInterval.self, forKey: .dauer)
        bild = try? c.decodeIfPresent(Bildbezug.self, forKey: .bild)
        favorit = (try? c.decodeIfPresent(Bool.self, forKey: .favorit)) ?? false
        gespielt = try? c.decodeIfPresent(Int.self, forKey: .gespielt)
        zuletztGespielt = try? c.decodeIfPresent(Date.self, forKey: .zuletztGespielt)
        hinzugefuegt = try? c.decodeIfPresent(Date.self, forKey: .hinzugefuegt)
        art = try? c.decodeIfPresent(Albumart.self, forKey: .art)
    }
}

public struct Kuenstler: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var name: String
    public var bild: Bildbezug?
    /// Ein breites Foto für den Kopf der Künstlerseite, wenn es eins gibt.
    public var heldbild: Bildbezug?
    public var albumzahl: Int?
    public var favorit: Bool

    public init(id: String, name: String, bild: Bildbezug? = nil, heldbild: Bildbezug? = nil,
                albumzahl: Int? = nil, favorit: Bool = false) {
        self.id = id
        self.name = name
        self.bild = bild
        self.heldbild = heldbild
        self.albumzahl = albumzahl
        self.favorit = favorit
    }

    private enum K: String, CodingKey { case id, name, bild, heldbild, albumzahl, favorit }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        bild = try? c.decodeIfPresent(Bildbezug.self, forKey: .bild)
        heldbild = try? c.decodeIfPresent(Bildbezug.self, forKey: .heldbild)
        albumzahl = try? c.decodeIfPresent(Int.self, forKey: .albumzahl)
        favorit = (try? c.decodeIfPresent(Bool.self, forKey: .favorit)) ?? false
    }
}

public struct Lied: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var titel: String
    public var kuenstler: String?
    /// Die Künstler einzeln, wie der Server sie nennt (``kuenstlernamen``).
    public var kuenstlerliste: [String]
    public var kuenstlerID: String?
    public var album: String?
    public var albumID: String?
    public var nummer: Int?
    public var cd: Int?
    /// Sekunden.
    public var dauer: TimeInterval?
    public var bild: Bildbezug?
    public var favorit: Bool
    public var gespielt: Int?
    public var format: Tonformat?
    /// Jellyfins `MediaSourceId`.
    public var quellID: String?
    /// Byte, für das Laden.
    public var groesse: Int64?
    /// Ein Teil eines Hörbuchs: merkt sich die Stelle, zählt nicht als Lied.
    public var istHoerbuch: Bool
    /// Wo es bei einem Hörbuch weitergeht, Sekunden.
    public var fortsetzen: TimeInterval?
    /// Ob der Server einen Liedtext kennt — `nil`, wenn er es nicht sagt.
    public var hatLiedtext: Bool?
    public var genre: String?
    public var jahr: Int?
    /// ReplayGain bzw. `NormalizationGain` (``Lautheitsregel``).
    public var lautheit: Lautheit?

    public init(id: String, titel: String, kuenstler: String? = nil, kuenstlerID: String? = nil,
                album: String? = nil, albumID: String? = nil, nummer: Int? = nil, cd: Int? = nil,
                dauer: TimeInterval? = nil, bild: Bildbezug? = nil, favorit: Bool = false,
                gespielt: Int? = nil, format: Tonformat? = nil, quellID: String? = nil,
                groesse: Int64? = nil, istHoerbuch: Bool = false, fortsetzen: TimeInterval? = nil,
                hatLiedtext: Bool? = nil, genre: String? = nil, jahr: Int? = nil,
                kuenstlerliste: [String] = [], lautheit: Lautheit? = nil) {
        self.id = id
        self.titel = titel
        self.kuenstler = kuenstler
        self.kuenstlerliste = kuenstlerliste
        self.lautheit = lautheit
        self.kuenstlerID = kuenstlerID
        self.album = album
        self.albumID = albumID
        self.nummer = nummer
        self.cd = cd
        self.dauer = dauer
        self.bild = bild
        self.favorit = favorit
        self.gespielt = gespielt
        self.format = format
        self.quellID = quellID
        self.groesse = groesse
        self.istHoerbuch = istHoerbuch
        self.fortsetzen = fortsetzen
        self.hatLiedtext = hatLiedtext
        self.genre = genre
        self.jahr = jahr
    }

    private enum K: String, CodingKey {
        case id, titel, kuenstler, kuenstlerliste, kuenstlerID, album, albumID, nummer, cd, dauer, bild, favorit,
             gespielt, format, quellID, groesse, istHoerbuch, fortsetzen, hatLiedtext, genre, jahr, lautheit
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        titel = (try? c.decodeIfPresent(String.self, forKey: .titel)) ?? ""
        kuenstler = try? c.decodeIfPresent(String.self, forKey: .kuenstler)
        kuenstlerliste = (try? c.decodeIfPresent([String].self, forKey: .kuenstlerliste)) ?? []
        kuenstlerID = try? c.decodeIfPresent(String.self, forKey: .kuenstlerID)
        album = try? c.decodeIfPresent(String.self, forKey: .album)
        albumID = try? c.decodeIfPresent(String.self, forKey: .albumID)
        nummer = try? c.decodeIfPresent(Int.self, forKey: .nummer)
        cd = try? c.decodeIfPresent(Int.self, forKey: .cd)
        dauer = try? c.decodeIfPresent(TimeInterval.self, forKey: .dauer)
        bild = try? c.decodeIfPresent(Bildbezug.self, forKey: .bild)
        favorit = (try? c.decodeIfPresent(Bool.self, forKey: .favorit)) ?? false
        gespielt = try? c.decodeIfPresent(Int.self, forKey: .gespielt)
        format = try? c.decodeIfPresent(Tonformat.self, forKey: .format)
        quellID = try? c.decodeIfPresent(String.self, forKey: .quellID)
        groesse = try? c.decodeIfPresent(Int64.self, forKey: .groesse)
        istHoerbuch = (try? c.decodeIfPresent(Bool.self, forKey: .istHoerbuch)) ?? false
        fortsetzen = try? c.decodeIfPresent(TimeInterval.self, forKey: .fortsetzen)
        hatLiedtext = try? c.decodeIfPresent(Bool.self, forKey: .hatLiedtext)
        genre = try? c.decodeIfPresent(String.self, forKey: .genre)
        jahr = try? c.decodeIfPresent(Int.self, forKey: .jahr)
        lautheit = try? c.decodeIfPresent(Lautheit.self, forKey: .lautheit)
    }
}

public struct Playlist: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var name: String
    public var liedzahl: Int?
    /// Sekunden.
    public var dauer: TimeInterval?
    public var bild: Bildbezug?
    public var geaendert: Date?
    public var favorit: Bool
    /// Wem sie gehört, wenn der Server es sagt (Subsonic `owner`).
    public var besitzer: String?

    public init(id: String, name: String, liedzahl: Int? = nil, dauer: TimeInterval? = nil,
                bild: Bildbezug? = nil, geaendert: Date? = nil, favorit: Bool = false, besitzer: String? = nil) {
        self.besitzer = besitzer
        self.id = id
        self.name = name
        self.liedzahl = liedzahl
        self.dauer = dauer
        self.bild = bild
        self.geaendert = geaendert
        self.favorit = favorit
    }

    private enum K: String, CodingKey { case id, name, liedzahl, dauer, bild, geaendert, favorit, besitzer }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        liedzahl = try? c.decodeIfPresent(Int.self, forKey: .liedzahl)
        dauer = try? c.decodeIfPresent(TimeInterval.self, forKey: .dauer)
        bild = try? c.decodeIfPresent(Bildbezug.self, forKey: .bild)
        geaendert = try? c.decodeIfPresent(Date.self, forKey: .geaendert)
        besitzer = try? c.decodeIfPresent(String.self, forKey: .besitzer)
        favorit = (try? c.decodeIfPresent(Bool.self, forKey: .favorit)) ?? false
    }
}

/// Ein Hörbuch: eine Sammlung von Teilen, die man der Reihe nach hört.
public struct Hoerbuch: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var titel: String
    public var autor: String?
    public var bild: Bildbezug?
    /// Sekunden, alle Teile zusammen.
    public var dauer: TimeInterval?
    public var jahr: Int?
    public var teilzahl: Int?

    public init(id: String, titel: String, autor: String? = nil, bild: Bildbezug? = nil,
                dauer: TimeInterval? = nil, jahr: Int? = nil, teilzahl: Int? = nil) {
        self.id = id
        self.titel = titel
        self.autor = autor
        self.bild = bild
        self.dauer = dauer
        self.jahr = jahr
        self.teilzahl = teilzahl
    }

    private enum K: String, CodingKey { case id, titel, autor, bild, dauer, jahr, teilzahl }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        titel = (try? c.decodeIfPresent(String.self, forKey: .titel)) ?? ""
        autor = try? c.decodeIfPresent(String.self, forKey: .autor)
        bild = try? c.decodeIfPresent(Bildbezug.self, forKey: .bild)
        dauer = try? c.decodeIfPresent(TimeInterval.self, forKey: .dauer)
        jahr = try? c.decodeIfPresent(Int.self, forKey: .jahr)
        teilzahl = try? c.decodeIfPresent(Int.self, forKey: .teilzahl)
    }
}

/// Die vier Arten von Sammlungen, aus denen man spielen kann — und die in
/// „Zuletzt gehört" stehen. Einzelne Lieder sind bewusst keine.
public enum Sammlungsart: String, Sendable, Codable, Hashable, CaseIterable {
    case album, kuenstler, playlist, hoerbuch
}

/// Ein Verweis auf eine Sammlung, klein genug zum Ablegen.
public struct Sammlungsverweis: Identifiable, Hashable, Sendable, Codable {
    public var id: String { "\(art.rawValue):\(kennung)" }
    public let art: Sammlungsart
    public let kennung: String
    public var titel: String
    public var bild: Bildbezug?
    /// Wann zuletzt daraus gespielt wurde.
    public var zeit: Date?
    /// Bei Alben: Album, EP oder Single (``Veroeffentlichung``) — daran sieht
    /// „Zuletzt gehört", was nicht hineingehört. Ältere Einträge haben keine.
    public var albumart: Albumart?

    public init(art: Sammlungsart, kennung: String, titel: String, bild: Bildbezug? = nil,
                zeit: Date? = nil, albumart: Albumart? = nil) {
        self.art = art
        self.kennung = kennung
        self.titel = titel
        self.bild = bild
        self.zeit = zeit
        self.albumart = albumart
    }

    public init(_ album: Album, zeit: Date? = nil) {
        self.init(art: .album, kennung: album.id, titel: album.titel, bild: album.bild,
                  zeit: zeit ?? album.zuletztGespielt, albumart: Veroeffentlichung.art(album))
    }

    public init(_ kuenstler: Kuenstler, zeit: Date? = nil) {
        self.init(art: .kuenstler, kennung: kuenstler.id, titel: kuenstler.name,
                  bild: kuenstler.bild, zeit: zeit)
    }

    public init(_ playlist: Playlist, zeit: Date? = nil) {
        self.init(art: .playlist, kennung: playlist.id, titel: playlist.name, bild: playlist.bild,
                  zeit: zeit)
    }

    public init(_ hoerbuch: Hoerbuch, zeit: Date? = nil) {
        self.init(art: .hoerbuch, kennung: hoerbuch.id, titel: hoerbuch.titel, bild: hoerbuch.bild,
                  zeit: zeit)
    }

    private enum K: String, CodingKey { case art, kennung, titel, bild, zeit, albumart }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        art = try c.decode(Sammlungsart.self, forKey: .art)
        kennung = try c.decode(String.self, forKey: .kennung)
        titel = (try? c.decodeIfPresent(String.self, forKey: .titel)) ?? ""
        bild = try? c.decodeIfPresent(Bildbezug.self, forKey: .bild)
        zeit = try? c.decodeIfPresent(Date.self, forKey: .zeit)
        albumart = try? c.decodeIfPresent(Albumart.self, forKey: .albumart)
    }
}

/// Eine Seite einer langen Liste.
public struct Seite<T: Sendable>: Sendable {
    public let eintraege: [T]
    /// Wie viele es insgesamt gibt, wenn der Server es sagt.
    public let gesamt: Int?
    /// Wo die nächste Seite anfängt — `nil` heißt: das war die letzte.
    public let weiterAb: Int?

    public init(eintraege: [T], gesamt: Int? = nil, weiterAb: Int?) {
        self.eintraege = eintraege
        self.gesamt = gesamt
        self.weiterAb = weiterAb
    }

    /// Die Stelle, an der die nächste Seite anfängt: `nil`, wenn weniger kam
    /// als verlangt oder das Ende erreicht ist.
    public static func weiter(ab start: Int, bekommen: Int, verlangt: Int, gesamt: Int?) -> Int? {
        let naechste = start + bekommen
        if let gesamt { return naechste < gesamt && bekommen > 0 ? naechste : nil }
        return bekommen >= verlangt && bekommen > 0 ? naechste : nil
    }
}
