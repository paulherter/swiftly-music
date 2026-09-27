import Foundation

/// **Wer angemeldet ist, bei welchem Server** — der Schlüssel für alles, was
/// je Konto abgelegt wird (geladene Lieder, „Zuletzt gehört").
///
/// Ein geladenes Lied gehört seinem Konto (`VERHALTEN.md` H11): unter der
/// Kennung allein sähe ein zweites Konto die Lieder und den Stand des ersten.
public struct Kontokennung: Hashable, Sendable, Codable {
    public let server: URL
    public let benutzerID: String

    public init(server: URL, benutzerID: String) {
        self.server = server
        self.benutzerID = benutzerID
    }

    /// Ein Name, der als Datei- oder Ordnername taugt.
    public var ablagename: String {
        let roh = "\(server.absoluteString)|\(benutzerID)"
        var wert: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in roh.utf8 {
            wert ^= UInt64(byte)
            wert &*= 0x0100_0000_01b3
        }
        return String(wert, radix: 16)
    }
}

// MARK: - Anfragen an die Bibliothek

/// Wonach die Alben sortiert werden. Die Reihenfolge der Fälle ist die der
/// Auswahl in der App.
public enum Albumsortierung: String, Sendable, Codable, CaseIterable, Hashable {
    case neu, name, kuenstler, jahr, zuletztGehoert, oftGehoert, zufall
}

public enum Liedsortierung: String, Sendable, Codable, CaseIterable, Hashable {
    case name, neu, zuletztGehoert, oftGehoert, zufall
}

public enum Playlistsortierung: String, Sendable, Codable, CaseIterable, Hashable {
    case name, geaendert
}

/// Künstler gibt es nur nach Namen — Subsonic liefert sie nicht anders, und
/// eine Auswahl mit einer Möglichkeit wäre keine (`VERHALTEN.md` D10).
public enum Kuenstlersortierung: String, Sendable, Codable, CaseIterable, Hashable {
    case name
}

/// Was der Server einschränkt. „Geladen" gehört nicht dazu — das weiß nur
/// das Gerät, und die App filtert es selbst.
public struct Serverfilter: Hashable, Sendable {
    public var nurFavoriten: Bool
    public var nurUngehoert: Bool

    public init(nurFavoriten: Bool = false, nurUngehoert: Bool = false) {
        self.nurFavoriten = nurFavoriten
        self.nurUngehoert = nurUngehoert
    }

    public static let keiner = Serverfilter()
}

public struct Listenanfrage<Sortierung: Hashable & Sendable>: Hashable, Sendable {
    public var sortierung: Sortierung
    public var filter: Serverfilter
    public var ab: Int
    public var anzahl: Int

    public init(sortierung: Sortierung, filter: Serverfilter = .keiner, ab: Int = 0, anzahl: Int = 100) {
        self.sortierung = sortierung
        self.filter = filter
        self.ab = ab
        self.anzahl = anzahl
    }
}

// MARK: - Antworten

public struct Albumdetail: Sendable, Hashable {
    public var album: Album
    public var lieder: [Lied]
    public init(album: Album, lieder: [Lied]) {
        self.album = album
        self.lieder = lieder
    }
}

public struct Kuenstlerdetail: Sendable, Hashable {
    public var kuenstler: Kuenstler
    public var alben: [Album]
    public var liedzahl: Int?
    public var genres: [String]
    public init(kuenstler: Kuenstler, alben: [Album], liedzahl: Int?, genres: [String]) {
        self.kuenstler = kuenstler
        self.alben = alben
        self.liedzahl = liedzahl
        self.genres = genres
    }
}

public struct Playlistdetail: Sendable, Hashable {
    public var playlist: Playlist
    public var lieder: [Lied]
    /// Je Lied die Kennung **des Eintrags** — bei Jellyfin die
    /// `PlaylistItemId` (nicht die Lied-ID: dasselbe Lied darf zweimal
    /// darin stehen), bei Subsonic die Stelle.
    public var eintraege: [String]
    public init(playlist: Playlist, lieder: [Lied], eintraege: [String]? = nil) {
        self.playlist = playlist
        self.lieder = lieder
        self.eintraege = eintraege ?? lieder.indices.map(String.init)
    }
}

public struct Hoerbuchdetail: Sendable, Hashable {
    public var hoerbuch: Hoerbuch
    public var teile: [Lied]
    public init(hoerbuch: Hoerbuch, teile: [Lied]) {
        self.hoerbuch = hoerbuch
        self.teile = teile
    }
}

public struct Suchergebnis: Sendable, Hashable {
    public var lieder: [Lied]
    public var alben: [Album]
    public var kuenstler: [Kuenstler]
    public var playlists: [Playlist]

    public init(lieder: [Lied] = [], alben: [Album] = [], kuenstler: [Kuenstler] = [],
                playlists: [Playlist] = []) {
        self.lieder = lieder
        self.alben = alben
        self.kuenstler = kuenstler
        self.playlists = playlists
    }

    public var istLeer: Bool {
        lieder.isEmpty && alben.isEmpty && kuenstler.isEmpty && playlists.isEmpty
    }
}

/// Wofür ein Sofortmix gebaut wird.
public enum Mixziel: Hashable, Sendable {
    case album(Album)
    case kuenstler(id: String, name: String)
    case lied(Lied)
    case playlist(Playlist)
    case genre(String)
}

/// Wem ein Favorit gilt.
public enum Favoritziel: Hashable, Sendable {
    case lied(String)
    case album(String)
    case kuenstler(String)
    case playlist(String)
}

// MARK: - Wiedergabe

public enum Abspielart: String, Sendable, Codable, Hashable {
    /// Die Datei läuft, wie sie auf dem Server liegt.
    case direkt
    /// Der Server wandelt um, weil das Gerät das Format nicht spielt.
    case umgewandelt
}

/// Wohin der Server umwandelt.
public struct Umwandlung: Hashable, Sendable, Codable {
    public let codec: String
    /// kbit/s.
    public let bitrate: Int
    public init(codec: String, bitrate: Int) {
        self.codec = codec
        self.bitrate = bitrate
    }
}

/// **Wie ein Lied auf das Gerät kommt:** Adresse, Art und was die Plakette
/// darüber sagt.
public struct Abspielweg: Hashable, Sendable {
    public let adresse: URL
    /// Für `AVURLAssetOverrideMIMETypeKey` — Subsonics `stream.view` hat
    /// keine Dateiendung, an der AVFoundation das Format erkennen könnte.
    public let mime: String?
    public let art: Abspielart
    /// Das Format der Datei auf dem Server.
    public let format: Tonformat?
    /// Beim Umwandeln: das Ziel.
    public let umwandlung: Umwandlung?
    /// Jellyfins `PlaySessionId`; bei Subsonic `nil`.
    public let sitzung: String?

    public init(adresse: URL, mime: String?, art: Abspielart, format: Tonformat?,
                umwandlung: Umwandlung? = nil, sitzung: String? = nil) {
        self.adresse = adresse
        self.mime = mime
        self.art = art
        self.format = format
        self.umwandlung = umwandlung
        self.sitzung = sitzung
    }
}

/// Was der Player dem Server meldet.
public struct Wiedergabestand: Sendable, Hashable {
    public let lied: Lied
    /// Sekunden.
    public let position: TimeInterval
    public let pausiert: Bool
    public let art: Abspielart
    public let sitzung: String?
    public let gemischt: Bool
    /// **Die Schlange, damit ein anderes Gerät sie sieht** — Jellyfins
    /// `NowPlayingQueue`. Wer Swiftly Music von Jellyfin-Web oder einer
    /// zweiten Swiftly Music aus steuert, sieht so, was als Nächstes kommt,
    /// und „Hier weiterhören" dort nimmt die ganze Schlange mit.
    public let schlange: [String]
    /// Wo das laufende Lied in ``schlange`` steht.
    public let index: Int?
    public let wiederholung: Warteschlange.Wiederholung
    /// 0 bis 100 — was ein anderes Gerät per `SetVolume` gesetzt hat.
    public let lautstaerke: Int
    public let stumm: Bool

    public init(lied: Lied, position: TimeInterval, pausiert: Bool, art: Abspielart,
                sitzung: String?, gemischt: Bool, schlange: [String] = [], index: Int? = nil,
                wiederholung: Warteschlange.Wiederholung = .aus, lautstaerke: Int = 100,
                stumm: Bool = false) {
        self.lied = lied
        self.position = position
        self.pausiert = pausiert
        self.art = art
        self.sitzung = sitzung
        self.gemischt = gemischt
        self.schlange = schlange
        self.index = index
        self.wiederholung = wiederholung
        self.lautstaerke = lautstaerke
        self.stumm = stumm
    }
}

public enum Wiedergabemeldung: Sendable {
    /// Das Lied läuft wirklich — nicht beim Einreihen (`VERHALTEN.md` C1).
    case beginn(Wiedergabestand)
    /// Alle zehn Sekunden und bei jeder Zustandsänderung (C2).
    case fortschritt(Wiedergabestand)
    /// Mit der Stelle **vor** dem Anhalten (C3).
    case ende(Wiedergabestand)
    /// Die Hälfte oder vier Minuten sind gehört (``Scrobbleregel``) — einmal
    /// je Wiedergabe. `beginn` ist der Zeitpunkt, an dem das Lied anfing.
    case gehoert(Lied, beginn: Date)
}

// MARK: - Die Quelle

/// **Ein Musikserver, gleich welcher Art.**
///
/// Die Oberfläche kennt nur dieses Protokoll. Jellyfin und Subsonic setzen es
/// um (``JellyfinQuelle``, ``SubsonicQuelle``); was einer nicht kann, meldet
/// er über ``Faehigkeiten`` statt mit einem Fehler.
public protocol Musikquelle: AnyObject, Sendable {
    var serverart: Serverart { get }
    var konto: Kontokennung { get }
    var benutzername: String { get }
    /// Was die Oberfläche anbieten darf.
    var faehigkeiten: Faehigkeiten { get }

    // Bibliothek
    func alben(_ anfrage: Listenanfrage<Albumsortierung>) async throws -> Seite<Album>
    func kuenstlerliste(_ anfrage: Listenanfrage<Kuenstlersortierung>) async throws -> Seite<Kuenstler>
    func playlists() async throws -> [Playlist]
    func lieder(_ anfrage: Listenanfrage<Liedsortierung>) async throws -> Seite<Lied>
    func hoerbuecher() async throws -> [Hoerbuch]
    /// Ob es auf dem Server Hörbücher gibt — nur dann gibt es den vierten
    /// Bereich unten.
    func hatHoerbuecher() async -> Bool

    // Seiten
    func album(_ id: String) async throws -> Albumdetail
    func kuenstler(_ id: String) async throws -> Kuenstlerdetail
    /// Die meistgehörten Lieder eines Künstlers, nach der eigenen Zählung.
    func oftGehoert(von kuenstler: Kuenstler, anzahl: Int) async throws -> [Lied]
    /// Alle Lieder eines Künstlers: die Alben vom neuesten an, jedes in
    /// seiner Reihenfolge — für „Abspielen" und „Zufall" auf der Künstlerseite.
    func alleLieder(von kuenstler: Kuenstler) async throws -> [Lied]
    func playlist(_ id: String) async throws -> Playlistdetail
    func hoerbuch(_ id: String) async throws -> Hoerbuchdetail

    // Start
    func zuletztHinzugefuegt(anzahl: Int) async throws -> [Album]
    /// Alben, aus denen zuletzt gespielt wurde, neueste zuerst.
    func zuletztGehoert(anzahl: Int) async throws -> [Album]
    func oftGehoerteAlben(anzahl: Int) async throws -> [Album]
    func sofortmix(_ ziel: Mixziel, anzahl: Int) async throws -> [Lied]

    func suche(_ begriff: String) async throws -> Suchergebnis
    func liedtext(_ lied: Lied) async throws -> Liedtext?
    func favorit(_ ziel: Favoritziel, an: Bool) async throws
    /// Viele Lieder auf einmal zu den Lieblingssongs oder heraus
    /// (``Lieblingsauswahl``). Ohne eigenen Weg: eins nach dem anderen.
    func lieblingeSetzen(_ ids: [String], an: Bool) async throws

    // Wiedergabe
    /// `sitzung` ist eine neue Kennung je Wiedergabe (Jellyfins
    /// `PlaySessionId`); Subsonic braucht sie nicht. `hoechstens`: die
    /// Höchstrate in kbit/s für das Netz, in dem das Gerät gerade ist —
    /// `nil` für Original (``Abspielregel/umwandlung(fuer:hoechstens:)``).
    func abspielweg(_ lied: Lied, sitzung: String, hoechstens: Int?) -> Abspielweg?
    /// Die Adresse zum Laden aufs Gerät: die Originaldatei, wenn das Gerät sie
    /// spielen kann, sonst dieselbe Umwandlung wie beim Streamen.
    func ladeweg(_ lied: Lied) -> Abspielweg?
    /// **Die Adresse für einen Sonos-Lautsprecher**, der selbst beim Server
    /// holt — direkt, wenn Sonos das Format kann (``Sonosregel``), sonst
    /// umgewandelt. `nil`, wenn es keine Adresse ohne Passwort im Klartext
    /// gibt (``sonosMoeglich``).
    func sonosweg(_ lied: Lied) -> Abspielweg?
    /// Ob sich eine Adresse für Sonos bauen lässt. Subsonic nur mit
    /// Token-Anmeldung: `p=` trüge das Passwort in die Sonos-App.
    var sonosMoeglich: Bool { get }
    /// **Mit dem Server aushandeln, bevor gespielt wird** — was er direkt
    /// zulässt und bis zu welcher Rate. Jellyfin fragt `PlaybackInfo` mit
    /// einem Geräteprofil; die Antwort gilt danach für ``abspielweg(_:sitzung:hoechstens:)``.
    /// Subsonic kennt das nicht.
    func vorbereiten(_ lieder: [Lied], hoechstens: Int?) async
    func melde(_ meldung: Wiedergabemeldung) async
    /// **Ein Lied gilt als gehört** — mit Fehler, damit der Spieler es
    /// nachtragen kann (``Nachtragsliste``). `nachtraeglich`: es lief, als
    /// der Server nicht erreichbar war. Jellyfin zählt ein Lied live selbst
    /// (über „Stopped") und braucht nur den Nachtrag; Subsonic scrobbelt in
    /// beiden Fällen.
    func scrobbeln(_ lied: Lied, beginn: Date, nachtraeglich: Bool) async throws

    // Playlists und Lieblingssongs
    /// Die Lieder mit Herz.
    func lieblingssongs() async throws -> [Lied]
    func playlistAnlegen(name: String, lieder: [Lied]) async throws -> Playlist
    func playlistUmbenennen(_ id: String, name: String) async throws
    func playlistLoeschen(_ id: String) async throws
    /// Hinten an.
    func playlistErgaenzen(_ id: String, lieder: [Lied]) async throws
    /// `stellen` zählen in `vorher`, der Playlist, wie sie geladen ist.
    func playlistEntfernen(_ id: String, stellen: [Int], vorher: Playlistdetail) async throws
    /// Ein Eintrag von `von` an die Stelle `nach` (gezählt in der neuen Folge).
    func playlistVerschieben(_ id: String, von: Int, nach: Int, vorher: Playlistdetail) async throws

    // Bibliotheken
    /// Die Musikbibliotheken des Servers (Jellyfin: Bibliotheken der Art
    /// Musik, Subsonic: Musikordner).
    func bibliotheken() async throws -> [Musikbibliothek]
    /// **Nur eine Bibliothek zeigen** — `nil` heißt alle. Gilt für Listen,
    /// Start und Suche, nicht für einzelne Seiten.
    var bibliothek: String? { get set }

    // Bilder
    func bildadresse(_ bild: Bildbezug, kante: Int) -> URL?
    func heldbildadresse(_ bild: Bildbezug, breite: Int) -> URL?
    func profilbildadresse(kante: Int) -> URL?

    /// Meldet das Gerät beim Server ab, soweit der Server das kennt.
    func abmelden() async

    /// **Gilt die gespeicherte Anmeldung noch?** Beim Start gefragt, bevor
    /// die App so tut, als sei sie angemeldet (``Anmeldestand``).
    func anmeldungPruefen() async -> Anmeldestand
}

extension Musikquelle {
    public func lieblingeSetzen(_ ids: [String], an: Bool) async throws {
        for id in ids { try await favorit(.lied(id), an: an) }
    }

    /// Ohne Aushandeln nichts vorzubereiten.
    public func vorbereiten(_ lieder: [Lied], hoechstens: Int?) async {}

    /// Ohne Höchstrate — die Datei, wie sie ist, wo das Gerät sie spielt.
    public func abspielweg(_ lied: Lied, sitzung: String) -> Abspielweg? {
        abspielweg(lied, sitzung: sitzung, hoechstens: nil)
    }
}

/// Eine Bibliothek des Servers.
public struct Musikbibliothek: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Was ein Server kann — die Oberfläche richtet ihre Auswahl danach.
public struct Faehigkeiten: Sendable, Hashable {
    public var albumsortierungen: [Albumsortierung]
    public var liedsortierungen: [Liedsortierung]
    /// Künstler lassen sich als Favorit markieren.
    public var kuenstlerFavoriten: Bool
    /// Playlists lassen sich als Favorit markieren.
    public var playlistFavoriten: Bool

    public init(albumsortierungen: [Albumsortierung], liedsortierungen: [Liedsortierung],
                kuenstlerFavoriten: Bool, playlistFavoriten: Bool) {
        self.albumsortierungen = albumsortierungen
        self.liedsortierungen = liedsortierungen
        self.kuenstlerFavoriten = kuenstlerFavoriten
        self.playlistFavoriten = playlistFavoriten
    }
}
