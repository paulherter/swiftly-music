import Foundation

/// **Was schiefgehen kann, nach Ursache getrennt.**
///
/// Netzfehler (`URLError`) laufen durch — die App übersetzt sie mit derselben
/// Regel wie bei Jellyfin. `SubsonicClient.einmal()` nimmt ihnen vorher die
/// Anfrage-URL aus dem `userInfo`; sie trägt die Anmeldung (`u=`/`t=`/`s=`,
/// im Rückfall `p=enc:<hex>`).
public enum SubsonicFehler: Error, Equatable, Sendable {
    /// Aus Adresse und Endpunkt ließ sich keine URL bauen.
    case adresse
    /// Die Antwort trägt kein `subsonic-response` — dort läuft kein Subsonic.
    case keinSubsonic
    /// Ein HTTP-Status außerhalb von 2xx, ohne lesbare Subsonic-Antwort.
    case http(Int)
    /// Der Server hat mit `status: failed` geantwortet.
    case server(code: Int, text: String?)
    /// Die Antwort war da, aber nicht zu lesen.
    case dekodieren(String)

    /// Code 40: Name oder Passwort stimmen nicht.
    public var istFalscheAnmeldung: Bool {
        if case .server(40, _) = self { return true }
        return false
    }

    /// Code 41 (Token geht nicht, etwa bei LDAP) oder 42 (OpenSubsonic: diese
    /// Anmeldeweise kennt der Server nicht) — dann mit Passwort versuchen.
    public var verlangtPasswort: Bool {
        if case let .server(code, _) = self { return code == 41 || code == 42 }
        return false
    }

    /// Code 70: gibt es nicht.
    public var istNichtGefunden: Bool {
        if case .server(70, _) = self { return true }
        return false
    }

    /// Code 50: dieses Konto darf das nicht.
    public var istNichtErlaubt: Bool {
        if case .server(50, _) = self { return true }
        return false
    }
}

/// Die Nutzlast einer Antwort und der Schlüssel, unter dem sie steht.
protocol Nutzlast: Decodable, Sendable {
    /// `nil` bei Antworten ohne Nutzlast (`ping`, `star`, `scrobble`).
    static var schluessel: String? { get }
    /// Was gilt, wenn der Schlüssel fehlt — viele Server lassen leere
    /// Container ganz weg.
    static var leer: Self { get }
}

/// Der Kopf jeder Antwort.
struct Antwortkopf: Decodable, Sendable {
    let status: String
    let server: SubsonicServer
    let fehler: SubsonicFehler?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        status = c.text("status") ?? ""
        server = SubsonicServer(version: c.text("version"), type: c.text("type"),
                                serverVersion: c.text("serverVersion"),
                                openSubsonic: c.wahr("openSubsonic") ?? false)
        if let f = try? c.nestedContainer(keyedBy: Feld.self, forKey: Feld("error")) {
            fehler = .server(code: f.zahl("code") ?? 0, text: f.text("message"))
        } else {
            fehler = nil
        }
    }
}

/// `{"subsonic-response": {…}}` — der Umschlag um jede Antwort.
struct Umschlag<P: Nutzlast>: Decodable {
    let kopf: Antwortkopf
    let nutzlast: P?

    init(from decoder: any Decoder) throws {
        let aussen = try decoder.container(keyedBy: Feld.self)
        let schluessel = Feld("subsonic-response")
        guard aussen.contains(schluessel) else { throw SubsonicFehler.keinSubsonic }
        kopf = try aussen.decode(Antwortkopf.self, forKey: schluessel)
        if let name = P.schluessel {
            let innen = try aussen.nestedContainer(keyedBy: Feld.self, forKey: schluessel)
            nutzlast = try innen.decodeIfPresent(P.self, forKey: Feld(name))
        } else {
            nutzlast = nil
        }
    }

    /// Liest eine Antwort und wirft, was der Server als Fehler meldet.
    static func lesen(_ daten: Data, status: Int) throws -> (Antwortkopf, P) {
        let umschlag: Umschlag<P>
        do {
            umschlag = try JSONDecoder().decode(Umschlag<P>.self, from: daten)
        } catch let fehler as SubsonicFehler {
            // Ein Proxy oder eine Webseite statt Subsonic.
            if !(200 ..< 300).contains(status) { throw SubsonicFehler.http(status) }
            throw fehler
        } catch {
            if !(200 ..< 300).contains(status) { throw SubsonicFehler.http(status) }
            // Kein JSON (etwa eine HTML-Seite) heißt: hier antwortet kein Subsonic.
            if (try? JSONSerialization.jsonObject(with: daten)) == nil {
                throw SubsonicFehler.keinSubsonic
            }
            throw SubsonicFehler.dekodieren(String(describing: error))
        }
        if umschlag.kopf.status != "ok" {
            throw umschlag.kopf.fehler ?? .server(code: 0, text: nil)
        }
        return (umschlag.kopf, umschlag.nutzlast ?? P.leer)
    }
}

// MARK: - Nutzlasten je Endpunkt

struct OhneNutzlast: Nutzlast {
    static let schluessel: String? = nil
    static let leer = OhneNutzlast()
    init() {}
    init(from decoder: any Decoder) throws {}
}

struct KuenstlerIndex: Nutzlast {
    static let schluessel: String? = "artists"
    static let leer = KuenstlerIndex(kuenstler: [])
    let kuenstler: [SubsonicKuenstler]

    init(kuenstler: [SubsonicKuenstler]) { self.kuenstler = kuenstler }

    init(from decoder: any Decoder) throws {
        struct Abschnitt: Decodable {
            let kuenstler: [SubsonicKuenstler]
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: Feld.self)
                kuenstler = c.liste("artist")
            }
        }
        let c = try decoder.container(keyedBy: Feld.self)
        kuenstler = c.liste("index", Abschnitt.self).flatMap(\.kuenstler)
    }
}

/// `getMusicFolders` — die Musikordner (Bibliotheken) des Servers.
struct MusikordnerNutzlast: Nutzlast {
    static let schluessel: String? = "musicFolders"
    static let leer = MusikordnerNutzlast(ordner: [])
    let ordner: [SubsonicVerweis]
    init(ordner: [SubsonicVerweis]) { self.ordner = ordner }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        ordner = c.liste("musicFolder")
    }
}

struct KuenstlerNutzlast: Nutzlast {
    static let schluessel: String? = "artist"
    static var leer: KuenstlerNutzlast { KuenstlerNutzlast(wert: nil) }
    let wert: SubsonicKuenstlerMitAlben?
    init(wert: SubsonicKuenstlerMitAlben?) { self.wert = wert }
    init(from decoder: any Decoder) throws { wert = try SubsonicKuenstlerMitAlben(from: decoder) }
}

struct AlbenNutzlast: Nutzlast {
    static let schluessel: String? = "albumList2"
    static let leer = AlbenNutzlast(alben: [])
    let alben: [SubsonicAlbum]
    init(alben: [SubsonicAlbum]) { self.alben = alben }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        alben = c.liste("album")
    }
}

struct AlbumNutzlast: Nutzlast {
    static let schluessel: String? = "album"
    static var leer: AlbumNutzlast { AlbumNutzlast(wert: nil) }
    let wert: SubsonicAlbum?
    init(wert: SubsonicAlbum?) { self.wert = wert }
    init(from decoder: any Decoder) throws { wert = try SubsonicAlbum(from: decoder) }
}

struct PlaylistsNutzlast: Nutzlast {
    static let schluessel: String? = "playlists"
    static let leer = PlaylistsNutzlast(playlists: [])
    let playlists: [SubsonicPlaylist]
    init(playlists: [SubsonicPlaylist]) { self.playlists = playlists }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        playlists = c.liste("playlist")
    }
}

struct PlaylistNutzlast: Nutzlast {
    static let schluessel: String? = "playlist"
    static var leer: PlaylistNutzlast { PlaylistNutzlast(wert: nil) }
    let wert: SubsonicPlaylist?
    init(wert: SubsonicPlaylist?) { self.wert = wert }
    init(from decoder: any Decoder) throws { wert = try SubsonicPlaylist(from: decoder) }
}

struct FavoritenNutzlast: Nutzlast {
    static let schluessel: String? = "starred2"
    static let leer = FavoritenNutzlast(wert: SubsonicSuchergebnis())
    let wert: SubsonicSuchergebnis
    init(wert: SubsonicSuchergebnis) { self.wert = wert }
    init(from decoder: any Decoder) throws { wert = try SubsonicSuchergebnis(from: decoder) }
}

struct SuchNutzlast: Nutzlast {
    static let schluessel: String? = "searchResult3"
    static let leer = SuchNutzlast(wert: SubsonicSuchergebnis())
    let wert: SubsonicSuchergebnis
    init(wert: SubsonicSuchergebnis) { self.wert = wert }
    init(from decoder: any Decoder) throws { wert = try SubsonicSuchergebnis(from: decoder) }
}

/// Lieder unter einem Schlüssel, der je Endpunkt anders heißt.
protocol Liederliste: Nutzlast {
    init(lieder: [SubsonicLied])
    var lieder: [SubsonicLied] { get }
}

extension Liederliste {
    static var leer: Self { Self(lieder: []) }
    /// Ausdrücklich je Typ aufgerufen: ein erzeugter Decoder hätte sonst
    /// Vorrang und suchte den Schlüssel `lieder` statt `song`.
    static func lieder(aus decoder: any Decoder) throws -> [SubsonicLied] {
        try decoder.container(keyedBy: Feld.self).liste("song")
    }
}

struct ZufallsNutzlast: Liederliste {
    static let schluessel: String? = "randomSongs"
    let lieder: [SubsonicLied]
    init(lieder: [SubsonicLied]) { self.lieder = lieder }
    init(from decoder: any Decoder) throws { lieder = try Self.lieder(aus: decoder) }
}

struct AehnlicheNutzlast: Liederliste {
    static let schluessel: String? = "similarSongs2"
    let lieder: [SubsonicLied]
    init(lieder: [SubsonicLied]) { self.lieder = lieder }
    init(from decoder: any Decoder) throws { lieder = try Self.lieder(aus: decoder) }
}

struct TopNutzlast: Liederliste {
    static let schluessel: String? = "topSongs"
    let lieder: [SubsonicLied]
    init(lieder: [SubsonicLied]) { self.lieder = lieder }
    init(from decoder: any Decoder) throws { lieder = try Self.lieder(aus: decoder) }
}

struct LiedtextlisteNutzlast: Nutzlast {
    static let schluessel: String? = "lyricsList"
    static let leer = LiedtextlisteNutzlast(texte: [])
    let texte: [SubsonicLiedtext]
    init(texte: [SubsonicLiedtext]) { self.texte = texte }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        texte = c.liste("structuredLyrics")
    }
}

struct LiedtextNutzlast: Nutzlast {
    static let schluessel: String? = "lyrics"
    static var leer: LiedtextNutzlast { LiedtextNutzlast(wert: nil) }
    let wert: SubsonicEinfacherLiedtext?
    init(wert: SubsonicEinfacherLiedtext?) { self.wert = wert }
    init(from decoder: any Decoder) throws { wert = try SubsonicEinfacherLiedtext(from: decoder) }
}

struct ErweiterungenNutzlast: Nutzlast {
    static let schluessel: String? = "openSubsonicExtensions"
    static let leer = ErweiterungenNutzlast(erweiterungen: [])
    let erweiterungen: [SubsonicErweiterung]
    init(erweiterungen: [SubsonicErweiterung]) { self.erweiterungen = erweiterungen }
    init(from decoder: any Decoder) throws {
        // Hier steht die Liste unmittelbar unter dem Schlüssel.
        var c = try decoder.unkeyedContainer()
        var liste: [SubsonicErweiterung] = []
        while !c.isAtEnd {
            if let e = try? c.decode(SubsonicErweiterung.self) { liste.append(e) } else {
                _ = try? c.decode(Nachsichtig<SubsonicErweiterung>.self)
            }
        }
        erweiterungen = liste
    }
}
