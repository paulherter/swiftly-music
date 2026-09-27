import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// **Der Zugang zu einem Subsonic-Server, wie er abgelegt wird.**
///
/// Das Passwort gehört dazu, weil die Token-Anmeldung es für jedes neue Salz
/// braucht und der Rückfall auf `p=enc:` (Code 41, LDAP-Konten) es ohnehin
/// verlangt. Die App legt den Zugang deshalb in den Schlüsselbund, nie in die
/// Voreinstellungen.
public struct SubsonicZugang: Sendable, Equatable, Codable {
    public enum Weise: String, Sendable, Codable {
        /// `t = md5(passwort + salz)` und `s = salz` — das Passwort steht nie
        /// in der Adresse.
        case token
        /// `p=enc:<hex>` — für Server, die das Token ablehnen.
        case passwort
    }

    public let server: URL
    public let benutzer: String
    public let passwort: String
    public var weise: Weise

    public init(server: URL, benutzer: String, passwort: String, weise: Weise = .token) {
        self.server = server
        self.benutzer = benutzer
        self.passwort = passwort
        self.weise = weise
    }

    /// Von Hand, damit ein späteres Feld eine alte Ablage nicht unlesbar macht
    /// (`Fallen/ablage.md`, „Ein fehlender Schlüssel wirft die ganze Datei weg").
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        server = try c.decode(URL.self, forKey: Feld("server"))
        benutzer = try c.decode(String.self, forKey: Feld("benutzer"))
        passwort = try c.decode(String.self, forKey: Feld("passwort"))
        weise = (try? c.decodeIfPresent(Weise.self, forKey: Feld("weise"))) ?? .token
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Feld.self)
        try c.encode(server, forKey: Feld("server"))
        try c.encode(benutzer, forKey: Feld("benutzer"))
        try c.encode(passwort, forKey: Feld("passwort"))
        try c.encode(weise, forKey: Feld("weise"))
    }
}

/// Welche Albumliste `getAlbumList2` liefern soll.
public enum SubsonicAlbumliste: Sendable, Hashable {
    case neueste
    case zuletztGespielt
    case oftGespielt
    case zufall
    case favoriten
    case nachName
    case nachKuenstler
    case hoechstBewertet
    /// Von `von` bis `bis`; läuft `von` > `bis`, sortiert der Server absteigend.
    case nachJahr(von: Int, bis: Int)
    case nachGenre(String)

    var werte: [URLQueryItem] {
        switch self {
        case .neueste: [.init(name: "type", value: "newest")]
        case .zuletztGespielt: [.init(name: "type", value: "recent")]
        case .oftGespielt: [.init(name: "type", value: "frequent")]
        case .zufall: [.init(name: "type", value: "random")]
        case .favoriten: [.init(name: "type", value: "starred")]
        case .nachName: [.init(name: "type", value: "alphabeticalByName")]
        case .nachKuenstler: [.init(name: "type", value: "alphabeticalByArtist")]
        case .hoechstBewertet: [.init(name: "type", value: "highest")]
        case let .nachJahr(von, bis):
            [.init(name: "type", value: "byYear"),
             .init(name: "fromYear", value: String(von)),
             .init(name: "toYear", value: String(bis))]
        case let .nachGenre(genre):
            [.init(name: "type", value: "byGenre"), .init(name: "genre", value: genre)]
        }
    }
}

/// Wem ein Stern gilt.
public enum SubsonicSternziel: Sendable, Hashable {
    case lied(String)
    case album(String)
    case kuenstler(String)

    var wert: URLQueryItem {
        switch self {
        case let .lied(id): .init(name: "id", value: id)
        case let .album(id): .init(name: "albumId", value: id)
        case let .kuenstler(id): .init(name: "artistId", value: id)
        }
    }
}

/// Ein zufälliges Salz für die Token-Anmeldung.
public enum Salz {
    /// Zwölf Hexzeichen aus dem Systemzufall.
    public static func neu() -> String {
        var erzeuger = SystemRandomNumberGenerator()
        let zahl = UInt64.random(in: 0 ... UInt64.max, using: &erzeuger)
        let text = String(zahl, radix: 16)
        return String(repeating: "0", count: max(0, 16 - text.count)) + text
    }
}

/// **Spricht mit einem Subsonic-Server.**
///
/// Eine Klasse mit unveränderlichen Werten und einem abgeschlossenen Stand:
/// die Adressen für Strom und Hüllen müssen ohne `await` zu haben sein, weil
/// die Oberfläche sie beim Zeichnen braucht.
///
/// **Ein Salz je Sitzung, nicht je Anfrage.** Die Spezifikation empfiehlt ein
/// neues Salz für jede Anfrage — dann hieße aber jede Hüllenadresse bei jedem
/// Zeichnen anders, und kein Bildspeicher träfe je. Der Server prüft nur, ob
/// `md5(passwort + s)` zu `t` passt; das gilt für ein wiederholtes Salz genauso.
public final class SubsonicClient: Sendable {

    public typealias Abruf = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Die Fassung der Schnittstelle, die wir sprechen. 1.16.1 ist die letzte
    /// von Subsonic selbst; OpenSubsonic baut darauf auf.
    public static let schnittstelle = "1.16.1"
    /// Unter diesem Namen führt uns der Server, etwa in Navidromes Spielerliste.
    public static let programm = "Swiftly Music"

    public let zugang: SubsonicZugang
    public let salz: String
    private let abruf: Abruf
    private let stand: Stand

    public init(zugang: SubsonicZugang, salz: String = Salz.neu(), abruf: @escaping Abruf) {
        self.zugang = zugang
        self.salz = salz
        self.abruf = abruf
        self.stand = Stand(weise: zugang.weise)
    }

    public convenience init(zugang: SubsonicZugang, sitzung: URLSession = .shared,
                            salz: String = Salz.neu()) {
        self.init(zugang: zugang, salz: salz) { anfrage in
            try await sitzung.data(for: anfrage)
        }
    }

    /// Die Anmeldeweise, die gerade gilt — nach einem Rückfall auf das
    /// Passwort (Code 41) eine andere als beim Anlegen.
    public var weise: SubsonicZugang.Weise { stand.weise }

    /// Der Zugang mit der geltenden Anmeldeweise, zum Ablegen.
    public var geltenderZugang: SubsonicZugang {
        var z = zugang
        z.weise = stand.weise
        return z
    }

    // MARK: - Anmelden und Erkennen

    /// **Meldet sich an und findet die Anmeldeweise heraus.**
    ///
    /// Erst mit Token; lehnt der Server das ab (41 oder 42), mit Passwort.
    /// Code 40 heißt: Name oder Passwort stimmen nicht — dann gibt es keinen
    /// zweiten Versuch, der würde das Passwort nur ein weiteres Mal senden.
    public static func anmelden(server: URL, benutzer: String, passwort: String,
                                abruf: @escaping Abruf) async throws -> (SubsonicClient, SubsonicServer) {
        let mitToken = SubsonicClient(
            zugang: SubsonicZugang(server: server, benutzer: benutzer, passwort: passwort, weise: .token),
            abruf: abruf)
        do {
            let info = try await mitToken.pingOhneRueckfall()
            return (mitToken, info)
        } catch let fehler as SubsonicFehler where fehler.verlangtPasswort {
            let mitPasswort = SubsonicClient(
                zugang: SubsonicZugang(server: server, benutzer: benutzer, passwort: passwort,
                                       weise: .passwort),
                abruf: abruf)
            let info = try await mitPasswort.pingOhneRueckfall()
            return (mitPasswort, info)
        }
    }

    /// **Läuft unter dieser Adresse ein Subsonic-Server?**
    ///
    /// Fragt `ping` ohne Anmeldung. Ein Subsonic-Server antwortet darauf mit
    /// einem Fehler (10 oder 40) — aber im Umschlag `subsonic-response`, und
    /// der verrät ihn. Eine Webseite, ein Jellyfin oder ein Proxy tut das nicht.
    public static func erkennen(server: URL, abruf: @escaping Abruf) async throws -> SubsonicServer {
        guard let url = adresse(server: server, endpunkt: "ping", werte: [
            .init(name: "v", value: schnittstelle),
            .init(name: "c", value: programm),
            .init(name: "f", value: "json"),
        ]) else { throw SubsonicFehler.adresse }
        var anfrage = URLRequest(url: url)
        anfrage.setValue("application/json", forHTTPHeaderField: "Accept")
        let (daten, antwort) = try await abruf(anfrage)
        let status = (antwort as? HTTPURLResponse)?.statusCode ?? 0
        do {
            let (kopf, _) = try Umschlag<OhneNutzlast>.lesen(daten, status: status)
            return kopf.server
        } catch let fehler as SubsonicFehler {
            // Ein Fehler **im Umschlag** ist die Antwort, die wir erwarten.
            if case .server = fehler,
               let umschlag = try? JSONDecoder().decode(Umschlag<OhneNutzlast>.self, from: daten) {
                return umschlag.kopf.server
            }
            throw fehler
        }
    }

    // MARK: - Adressen

    static func adresse(server: URL, endpunkt: String, werte: [URLQueryItem]) -> URL? {
        guard var teile = URLComponents(url: server.appendingPathComponent("rest/\(endpunkt).view"),
                                        resolvingAgainstBaseURL: false) else { return nil }
        teile.queryItems = werte
        // **`+` muss maskiert werden.** `URLComponents` lässt es im
        // Abfrageteil stehen, und Server lesen es als Leerzeichen — ein
        // Passwort oder eine Suche mit „+" käme verfälscht an.
        teile.percentEncodedQuery = teile.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return teile.url
    }

    /// Die Anmeldung als Abfragewerte — mit der geltenden Weise.
    func ausweis(_ weise: SubsonicZugang.Weise? = nil) -> [URLQueryItem] {
        var werte = [URLQueryItem(name: "u", value: zugang.benutzer)]
        switch weise ?? stand.weise {
        case .token:
            werte.append(.init(name: "t", value: Pruefsumme.md5Hex(zugang.passwort + salz)))
            werte.append(.init(name: "s", value: salz))
        case .passwort:
            let hex = zugang.passwort.utf8.map { String(format: "%02x", $0) }.joined()
            werte.append(.init(name: "p", value: "enc:" + hex))
        }
        werte.append(.init(name: "v", value: Self.schnittstelle))
        werte.append(.init(name: "c", value: Self.programm))
        return werte
    }

    func adresse(_ endpunkt: String, _ werte: [URLQueryItem] = [],
                 weise: SubsonicZugang.Weise? = nil, json: Bool = true) -> URL? {
        var alle = ausweis(weise)
        if json { alle.append(.init(name: "f", value: "json")) }
        alle.append(contentsOf: werte)
        if let ordner = stand.musikordner, Self.nachOrdner.contains(endpunkt),
           !werte.contains(where: { $0.name == "musicFolderId" }) {
            alle.append(.init(name: "musicFolderId", value: ordner))
        }
        return Self.adresse(server: zugang.server, endpunkt: endpunkt, werte: alle)
    }

    /// **Die Abspieladresse.** `format: "raw"` heißt: die Datei, wie sie
    /// liegt. Ein anderes Format lässt den Server umwandeln; dann schätzt er
    /// auf Wunsch die Länge (`estimateContentLength`), damit der Player eine
    /// Dauer und eine Spulleiste hat.
    public func streamAdresse(id: String, format: String? = nil, hoechstBitrate: Int? = nil,
                              laengeSchaetzen: Bool = false) -> URL? {
        var werte = [URLQueryItem(name: "id", value: id)]
        if let format { werte.append(.init(name: "format", value: format)) }
        if let hoechstBitrate { werte.append(.init(name: "maxBitRate", value: String(hoechstBitrate))) }
        if laengeSchaetzen { werte.append(.init(name: "estimateContentLength", value: "true")) }
        return adresse("stream", werte, json: false)
    }

    /// Die Originaldatei — zum Laden aufs Gerät.
    public func downloadAdresse(id: String) -> URL? {
        adresse("download", [.init(name: "id", value: id)], json: false)
    }

    /// Die Hülle in `groesse` Bildpunkten Kantenlänge.
    public func coverAdresse(id: String, groesse: Int? = nil) -> URL? {
        var werte = [URLQueryItem(name: "id", value: id)]
        if let groesse { werte.append(.init(name: "size", value: String(groesse))) }
        return adresse("getCoverArt", werte, json: false)
    }

    /// Das Profilbild des angemeldeten Benutzers.
    public func avatarAdresse() -> URL? {
        adresse("getAvatar", [.init(name: "username", value: zugang.benutzer)], json: false)
    }

    // MARK: - Anfragen

    func holen<P: Nutzlast>(_ endpunkt: String, _ werte: [URLQueryItem] = [],
                            als: P.Type = P.self) async throws -> P {
        try await holenMitKopf(endpunkt, werte, als: P.self).1
    }

    /// Mit Rückfall: meldet der Server 41 oder 42, gilt ab jetzt das Passwort.
    func holenMitKopf<P: Nutzlast>(_ endpunkt: String, _ werte: [URLQueryItem] = [],
                                   als: P.Type = P.self) async throws -> (Antwortkopf, P) {
        do {
            return try await einmal(endpunkt, werte, weise: nil, als: P.self)
        } catch let fehler as SubsonicFehler where fehler.verlangtPasswort && stand.weise == .token {
            stand.weise = .passwort
            return try await einmal(endpunkt, werte, weise: .passwort, als: P.self)
        }
    }

    private func einmal<P: Nutzlast>(_ endpunkt: String, _ werte: [URLQueryItem],
                                     weise: SubsonicZugang.Weise?,
                                     als: P.Type) async throws -> (Antwortkopf, P) {
        guard let url = adresse(endpunkt, werte, weise: weise) else { throw SubsonicFehler.adresse }
        var anfrage = URLRequest(url: url)
        anfrage.setValue("application/json", forHTTPHeaderField: "Accept")
        let daten: Data
        let antwort: URLResponse
        do {
            (daten, antwort) = try await abruf(anfrage)
        } catch {
            // Die Adresse trägt `u=`/`t=`/`s=`, im Rückfall auch `p=enc:<hex>` —
            // ein `URLError` (oder eine andere NSError) hält sie in seinem
            // `userInfo` (`NSURLErrorFailingURLErrorKey`). Ohne diese Zeile
            // wäre sie im Protokoll, sobald „Protokoll teilen" den Fehler zeigt.
            throw Self.ohneAnfrageAdresse(error)
        }
        let status = (antwort as? HTTPURLResponse)?.statusCode ?? 200
        return try Umschlag<P>.lesen(daten, status: status)
    }

    /// Ein Fehler aus `abruf`, ohne die Anfrage-URL in seinem `userInfo`.
    ///
    /// `URLError(_:)` ohne `userInfo`-Argument setzt keins — das reicht für
    /// den häufigen Fall. Eine andere `NSError` mit demselben Schlüssel wird
    /// ohne ihn neu gebaut; alles andere kommt unverändert durch.
    static func ohneAnfrageAdresse(_ fehler: any Error) -> any Error {
        if let u = fehler as? URLError { return URLError(u.code) }
        let n = fehler as NSError
        guard n.userInfo[NSURLErrorFailingURLErrorKey] != nil else { return fehler }
        var info = n.userInfo
        info[NSURLErrorFailingURLErrorKey] = nil
        return NSError(domain: n.domain, code: n.code, userInfo: info)
    }

    private func pingOhneRueckfall() async throws -> SubsonicServer {
        try await einmal("ping", [], weise: nil, als: OhneNutzlast.self).0.server
    }

    // MARK: - Endpunkte

    /// Erreichbar und angemeldet? Liefert, was der Server über sich sagt.
    @discardableResult
    public func ping() async throws -> SubsonicServer {
        try await holenMitKopf("ping", als: OhneNutzlast.self).0.server
    }

    /// Die OpenSubsonic-Erweiterungen. Ein Server ohne OpenSubsonic kennt den
    /// Endpunkt nicht — das ist keine Störung, sondern eine leere Liste.
    public func erweiterungen() async throws -> [SubsonicErweiterung] {
        do {
            return try await holen("getOpenSubsonicExtensions", als: ErweiterungenNutzlast.self)
                .erweiterungen
        } catch let fehler as SubsonicFehler {
            switch fehler {
            case .server, .http(404), .keinSubsonic: return []
            default: throw fehler
            }
        }
    }

    // MARK: Musikordner

    /// Die Endpunkte, die `musicFolderId` kennen — Listen und Suche, nicht
    /// die Seiten einzelner Alben oder Künstler.
    static let nachOrdner: Set<String> = [
        "getAlbumList2", "getRandomSongs", "getArtists", "getIndexes", "search3", "getStarred2", "getSongsByGenre",
    ]

    /// **Nur eine Bibliothek** (Feishins Auswahl je Server): gesetzt, tragen
    /// alle Listen und die Suche `musicFolderId`; `nil` heißt alle.
    public var musikordner: String? {
        get { stand.musikordner }
        set { stand.musikordner = newValue }
    }

    /// `getMusicFolders`.
    public func musikordnerliste() async throws -> [SubsonicVerweis] {
        try await holen("getMusicFolders", als: MusikordnerNutzlast.self).ordner
    }

    /// Alle Künstler, ohne die Gliederung nach Anfangsbuchstaben.
    public func alleKuenstler() async throws -> [SubsonicKuenstler] {
        try await holen("getArtists", als: KuenstlerIndex.self).kuenstler
    }

    public func kuenstler(id: String) async throws -> SubsonicKuenstlerMitAlben {
        guard let wert = try await holen("getArtist", [.init(name: "id", value: id)],
                                         als: KuenstlerNutzlast.self).wert
        else { throw SubsonicFehler.server(code: 70, text: nil) }
        return wert
    }

    /// Höchstens 500 je Aufruf — mehr gibt die Schnittstelle nicht her.
    public func albumliste(_ art: SubsonicAlbumliste, anzahl: Int = 50,
                           ab: Int = 0) async throws -> [SubsonicAlbum] {
        var werte = art.werte
        werte.append(.init(name: "size", value: String(min(max(anzahl, 1), 500))))
        werte.append(.init(name: "offset", value: String(max(ab, 0))))
        return try await holen("getAlbumList2", werte, als: AlbenNutzlast.self).alben
    }

    public func album(id: String) async throws -> SubsonicAlbum {
        guard let wert = try await holen("getAlbum", [.init(name: "id", value: id)],
                                         als: AlbumNutzlast.self).wert
        else { throw SubsonicFehler.server(code: 70, text: nil) }
        return wert
    }

    public func playlists() async throws -> [SubsonicPlaylist] {
        try await holen("getPlaylists", als: PlaylistsNutzlast.self).playlists
    }

    /// `createPlaylist` — neuere Server geben die neue Playlist zurück,
    /// ältere nur „ok"; dann `nil`.
    public func playlistAnlegen(name: String, liedIDs: [String]) async throws -> SubsonicPlaylist? {
        let werte = [URLQueryItem(name: "name", value: name)] + liedIDs.map { .init(name: "songId", value: $0) }
        return try await holen("createPlaylist", werte, als: PlaylistNutzlast.self).wert
    }

    /// `updatePlaylist` mit `songIdToAdd` — hinten an.
    public func playlistErgaenzen(id: String, liedIDs: [String]) async throws {
        let werte = [URLQueryItem(name: "playlistId", value: id)]
            + liedIDs.map { .init(name: "songIdToAdd", value: $0) }
        _ = try await holen("updatePlaylist", werte, als: OhneNutzlast.self)
    }

    /// `updatePlaylist` mit `songIndexToRemove` — Stellen zählen ab 0 in
    /// der Liste, wie sie der Server gerade hat.
    public func playlistEntfernen(id: String, stellen: [Int]) async throws {
        let werte = [URLQueryItem(name: "playlistId", value: id)]
            + stellen.map { .init(name: "songIndexToRemove", value: String($0)) }
        _ = try await holen("updatePlaylist", werte, als: OhneNutzlast.self)
    }

    /// `updatePlaylist` mit `name`.
    public func playlistUmbenennen(id: String, name: String) async throws {
        _ = try await holen("updatePlaylist", [.init(name: "playlistId", value: id), .init(name: "name", value: name)],
                            als: OhneNutzlast.self)
    }

    /// **Neu schreiben**: `createPlaylist` mit `playlistId` ersetzt die
    /// Lieder durch diese Folge — so sortiert Subsonic um.
    public func playlistNeuSchreiben(id: String, liedIDs: [String]) async throws {
        let werte = [URLQueryItem(name: "playlistId", value: id)] + liedIDs.map { .init(name: "songId", value: $0) }
        _ = try await holen("createPlaylist", werte, als: PlaylistNutzlast.self)
    }

    /// `deletePlaylist`.
    public func playlistLoeschen(id: String) async throws {
        _ = try await holen("deletePlaylist", [.init(name: "id", value: id)], als: OhneNutzlast.self)
    }

    public func playlist(id: String) async throws -> SubsonicPlaylist {
        guard let wert = try await holen("getPlaylist", [.init(name: "id", value: id)],
                                         als: PlaylistNutzlast.self).wert
        else { throw SubsonicFehler.server(code: 70, text: nil) }
        return wert
    }

    /// **Suche — und mit leerem Begriff die ganze Sammlung.** Einen Endpunkt
    /// „alle Lieder" gibt es in Subsonic nicht; ein leerer Begriff liefert bei
    /// Navidrome und den meisten anderen alles, seitenweise über die `…Ab`-Werte.
    public func suche(_ begriff: String, kuenstler: Int = 5, alben: Int = 10, lieder: Int = 20,
                      kuenstlerAb: Int = 0, albenAb: Int = 0,
                      liederAb: Int = 0) async throws -> SubsonicSuchergebnis {
        var werte: [URLQueryItem] = [
            .init(name: "query", value: begriff),
            .init(name: "artistCount", value: String(kuenstler)),
            .init(name: "albumCount", value: String(alben)),
            .init(name: "songCount", value: String(lieder)),
        ]
        if kuenstlerAb > 0 { werte.append(.init(name: "artistOffset", value: String(kuenstlerAb))) }
        if albenAb > 0 { werte.append(.init(name: "albumOffset", value: String(albenAb))) }
        if liederAb > 0 { werte.append(.init(name: "songOffset", value: String(liederAb))) }
        return try await holen("search3", werte, als: SuchNutzlast.self).wert
    }

    /// Alles mit Stern: Künstler, Alben, Lieder (`getStarred2`).
    public func favoriten() async throws -> SubsonicSuchergebnis {
        try await holen("getStarred2", als: FavoritenNutzlast.self).wert
    }

    public func zufallslieder(anzahl: Int = 50, genre: String? = nil,
                              vonJahr: Int? = nil, bisJahr: Int? = nil) async throws -> [SubsonicLied] {
        var werte = [URLQueryItem(name: "size", value: String(min(max(anzahl, 1), 500)))]
        if let genre { werte.append(.init(name: "genre", value: genre)) }
        if let vonJahr { werte.append(.init(name: "fromYear", value: String(vonJahr))) }
        if let bisJahr { werte.append(.init(name: "toYear", value: String(bisJahr))) }
        return try await holen("getRandomSongs", werte, als: ZufallsNutzlast.self).lieder
    }

    /// Ähnliche Lieder zu einem **Künstler** — Navidrome fragt dafür Last.fm.
    /// Ohne Anbindung kommt eine leere Liste; darum kümmert sich der Aufrufer.
    public func aehnlicheLieder(kuenstlerID: String, anzahl: Int = 50) async throws -> [SubsonicLied] {
        try await holen("getSimilarSongs2", [
            .init(name: "id", value: kuenstlerID),
            .init(name: "count", value: String(anzahl)),
        ], als: AehnlicheNutzlast.self).lieder
    }

    public func topLieder(kuenstler name: String, anzahl: Int = 50) async throws -> [SubsonicLied] {
        try await holen("getTopSongs", [
            .init(name: "artist", value: name),
            .init(name: "count", value: String(anzahl)),
        ], als: TopNutzlast.self).lieder
    }

    /// Getaktete Liedtexte (OpenSubsonic `songLyrics`), je Sprache einer.
    public func liedtexte(liedID: String) async throws -> [SubsonicLiedtext] {
        try await holen("getLyricsBySongId", [.init(name: "id", value: liedID)],
                        als: LiedtextlisteNutzlast.self).texte
    }

    /// Der alte Weg über Künstler und Titel — nur Text, ohne Zeiten. Ein leerer
    /// Text heißt: keiner da.
    public func liedtext(kuenstler: String, titel: String) async throws -> SubsonicEinfacherLiedtext? {
        let wert = try await holen("getLyrics", [
            .init(name: "artist", value: kuenstler),
            .init(name: "title", value: titel),
        ], als: LiedtextNutzlast.self).wert
        guard let wert, !wert.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return wert
    }

    public func stern(_ ziel: SubsonicSternziel, an: Bool) async throws {
        _ = try await holen(an ? "star" : "unstar", [ziel.wert], als: OhneNutzlast.self)
    }

    /// **Viele Lieder mit einem Aufruf**: `star`/`unstar` nehmen `id` beliebig
    /// oft (Subsonic-API 1.8). Wer mehr als ein paar Dutzend schickt, teilt
    /// selbst auf — die Adresse wird sonst zu lang.
    public func sterne(lieder ids: [String], an: Bool) async throws {
        guard !ids.isEmpty else { return }
        _ = try await holen(an ? "star" : "unstar", ids.map { URLQueryItem(name: "id", value: $0) },
                            als: OhneNutzlast.self)
    }

    /// `abgeschlossen: false` meldet „läuft gerade", `true` zählt das Lied als
    /// gehört — so, wie es Last.fm und die Wiedergabezählung erwarten.
    public func scrobble(id: String, zeit: Date? = nil, abgeschlossen: Bool) async throws {
        var werte = [URLQueryItem(name: "id", value: id),
                     URLQueryItem(name: "submission", value: abgeschlossen ? "true" : "false")]
        if let zeit {
            werte.append(.init(name: "time", value: String(Int64(zeit.timeIntervalSince1970 * 1000))))
        }
        _ = try await holen("scrobble", werte, als: OhneNutzlast.self)
    }
}

/// Der eine veränderliche Wert, hinter einem Schloss.
private final class Stand: @unchecked Sendable {
    private let schloss = NSLock()
    private var _weise: SubsonicZugang.Weise
    private var _musikordner: String?

    init(weise: SubsonicZugang.Weise) { _weise = weise }

    var musikordner: String? {
        get { schloss.lock(); defer { schloss.unlock() }; return _musikordner }
        set { schloss.lock(); _musikordner = newValue; schloss.unlock() }
    }

    var weise: SubsonicZugang.Weise {
        get { schloss.lock(); defer { schloss.unlock() }; return _weise }
        set { schloss.lock(); _weise = newValue; schloss.unlock() }
    }
}
