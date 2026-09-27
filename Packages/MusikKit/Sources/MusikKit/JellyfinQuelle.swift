import Foundation
import JellyfinKit

/// **Musik von einem Jellyfin-Server.**
///
/// Angemeldet wird über `JellyfinClient` (Name und Passwort oder Quick
/// Connect); alles Weitere fragt diese Quelle über ``JellyfinClient/rohdaten``
/// mit demselben Ausweis ab. Der Client trägt `programm: "Swiftly Music"` und
/// eine **eigene** Gerätekennung — mit der des Players auf demselben iPhone
/// nähme Jellyfin dem Player die Anmeldung weg.
public final class JellyfinQuelle: Musikquelle {

    public let serverart: Serverart = .jellyfin
    public let konto: Kontokennung
    public let benutzername: String
    public let faehigkeiten = Faehigkeiten(
        albumsortierungen: Albumsortierung.allCases,
        liedsortierungen: Liedsortierung.allCases,
        kuenstlerFavoriten: true,
        playlistFavoriten: true)

    public let client: JellyfinClient
    private let sitzung: Session
    /// Die eigene Kennung — ohne sie zeigt sich das Gerät in der Geräteliste selbst.
    public let geraeteID: String
    private let bilder: Bildadresse
    /// Umgeschaltete Lieder und der Weg zum Setzen (``Favoritenstand``).
    let favoritenstand = Favoritenstand()
    var benutzerID: String { sitzung.userID }

    public init(client: JellyfinClient, sitzung: Session, geraeteID: String) {
        self.client = client
        self.sitzung = sitzung
        self.geraeteID = geraeteID
        konto = Kontokennung(server: client.baseURL, benutzerID: sitzung.userID)
        benutzername = sitzung.userName
        bilder = Bildadresse(basis: client.baseURL, token: sitzung.accessToken)
    }

    // MARK: - Abfragen

    static let albumFelder = "DateCreated,Genres,ChildCount,SortName"
    static let liedFelder = "MediaSources,DateCreated,Genres,ParentId"

    private func holen<T: Decodable>(_ pfad: String, _ werte: [URLQueryItem],
                                     als: T.Type) async throws -> T {
        let daten = try await client.rohdaten(pfad, abfrage: werte)
        do {
            return try JSONDecoder().decode(T.self, from: daten)
        } catch {
            throw JellyfinError.decoding(String(describing: error))
        }
    }

    private func eintraege(_ werte: [URLQueryItem]) async throws -> JListe {
        try await holen("Items", [.init(name: "userId", value: sitzung.userID)] + Self.eingegrenzt(werte, bibliothek),
                        als: JListe.self)
    }

    // MARK: - Bibliothek

    private let gewaehlt = Gewaehlt()

    public var bibliothek: String? {
        get { gewaehlt.wert }
        set { gewaehlt.wert = newValue }
    }

    public func bibliotheken() async throws -> [Musikbibliothek] {
        let antwort = try await holen("UserViews", [.init(name: "userId", value: sitzung.userID)], als: JListe.self)
        return antwort.eintraege.filter { $0.sammlungsart?.lowercased() == "music" }
            .map { Musikbibliothek(id: $0.id, name: $0.name) }
    }

    /// **Eine Liste auf die gewählte Bibliothek eingrenzen** — nur Alben,
    /// Lieder und Künstler; Playlists und Hörbücher liegen anderswo, und
    /// eine Abfrage nach Kennungen oder in einem Ordner ist schon eng genug.
    static func eingegrenzt(_ werte: [URLQueryItem], _ bibliothek: String?) -> [URLQueryItem] {
        guard let bibliothek,
              !werte.contains(where: { ["ParentId", "Ids"].contains($0.name) }),
              let typen = werte.first(where: { $0.name == "IncludeItemTypes" })?.value,
              ["MusicAlbum", "Audio", "MusicArtist"].contains(typen) else { return werte }
        return werte + [.init(name: "ParentId", value: bibliothek)]
    }

    private func eintrag(_ id: String) async throws -> JEintrag {
        try await holen("Items/\(id)", [.init(name: "userId", value: sitzung.userID)], als: JEintrag.self)
    }

    /// Was jede Listenabfrage mitbringt.
    static func liste(_ typen: String, felder: String) -> [URLQueryItem] {
        [.init(name: "IncludeItemTypes", value: typen),
         .init(name: "Recursive", value: "true"),
         .init(name: "Fields", value: felder),
         .init(name: "EnableUserData", value: "true"),
         .init(name: "EnableImageTypes", value: "Primary,Backdrop"),
         .init(name: "ImageTypeLimit", value: "1")]
    }

    static func seite(_ ab: Int, _ anzahl: Int) -> [URLQueryItem] {
        [.init(name: "StartIndex", value: String(ab)), .init(name: "Limit", value: String(anzahl))]
    }

    static func filterwerte(_ filter: Serverfilter, dazu: [String] = []) -> [URLQueryItem] {
        var liste = dazu
        if filter.nurFavoriten { liste.append("IsFavorite") }
        if filter.nurUngehoert { liste.append("IsUnplayed") }
        return liste.isEmpty ? [] : [.init(name: "Filters", value: liste.joined(separator: ","))]
    }

    static func sortierung(_ nach: String, absteigend: Bool) -> [URLQueryItem] {
        [.init(name: "SortBy", value: nach),
         .init(name: "SortOrder", value: absteigend ? "Descending" : "Ascending")]
    }

    // MARK: - Umsetzen

    func albumAus(_ e: JEintrag) -> Album {
        // Ohne Albumkünstler (oder mit einem Platzhalter) gelten die
        // Liedkünstler — nicht „Unbekannt".
        let albumkuenstler = e.albumKuenstler.flatMap { Veroeffentlichung.istPlatzhalter($0) ? nil : $0 }
        let albumliste = e.albumKuenstlerListe.filter { !Veroeffentlichung.istPlatzhalter($0.name) }
        var album = Album(id: e.id, titel: e.name,
              kuenstler: Self.zeile(albumkuenstler, albumliste.map(\.name), e.kuenstlerNamen),
              kuenstlerID: albumliste.first?.id ?? e.kuenstlerListe.first?.id,
              jahr: e.jahr, genres: e.genres, liedzahl: e.kinder, dauer: e.dauer,
              bild: e.bildmarken["Primary"].map { Bildbezug(id: e.id, marke: $0) },
              favorit: e.nutzer?.favorit ?? false, gespielt: e.nutzer?.zaehler,
              zuletztGespielt: e.nutzer?.zuletzt, hinzugefuegt: e.angelegt,
              kuenstlerliste: Self.namen(albumliste.map(\.name), [albumkuenstler].compactMap { $0 },
                                         e.kuenstlerListe.map(\.name), e.kuenstlerNamen))
        album.art = Veroeffentlichung.art(album)
        return album
    }

    func liedAus(_ e: JEintrag) -> Lied {
        let quelle = e.quellen.first
        let ton = quelle?.stroeme.first { $0.typ == "Audio" }
        let behaelter = Self.behaelter(pfad: quelle?.pfad ?? e.pfad,
                                       container: quelle?.behaelter ?? e.behaelter)
        let bitrate = (ton?.bitrate ?? quelle?.bitrate).map { max(1, Int(($0 + 500) / 1000)) }
        let format = Tonformat(codec: ton?.codec?.lowercased(), behaelter: behaelter, bitrate: bitrate,
                               bitTiefe: ton?.bitTiefe.flatMap { $0 > 0 ? $0 : nil },
                               abtastrate: ton?.abtastrate, kanaele: ton?.kanaele,
                               mime: nil)
        let eigenesBild = e.bildmarken["Primary"].map { Bildbezug(id: e.id, marke: $0) }
        let albumbild = e.albumID.map { Bildbezug(id: $0, marke: e.albumBildmarke) }
        let stelle = e.nutzer?.stelleTicks.map { TimeInterval($0) / 10_000_000 }
        return Lied(id: e.id, titel: e.name,
                    kuenstler: Self.zeile(nil, e.kuenstlerNamen, [e.albumKuenstler].compactMap { $0 }),
                    kuenstlerID: e.kuenstlerListe.first?.id ?? e.albumKuenstlerListe.first?.id,
                    album: e.album, albumID: e.albumID, nummer: e.nummer, cd: e.cd, dauer: e.dauer,
                    bild: e.albumBildmarke != nil ? albumbild : (eigenesBild ?? albumbild),
                    favorit: e.nutzer?.favorit ?? false, gespielt: e.nutzer?.zaehler,
                    format: format, quellID: quelle?.id, groesse: quelle?.groesse,
                    istHoerbuch: e.typ == "AudioBook",
                    fortsetzen: (stelle ?? 0) > 1 && e.nutzer?.gespielt != true ? stelle : nil,
                    hatLiedtext: e.hatLiedtext, genre: e.genres.first, jahr: e.jahr,
                    kuenstlerliste: Self.namen(e.kuenstlerListe.map(\.name), e.kuenstlerNamen,
                                               [e.albumKuenstler].compactMap { $0 }),
                    lautheit: e.pegel.map { Lautheit(lied: $0) })
    }

    /// Die erste Liste, die etwas enthält, zerlegt (`Kuenstlernamen`).
    static func namen(_ listen: [String]...) -> [String] {
        for liste in listen {
            let namen = Kuenstlernamen.liste(liste)
            if !namen.isEmpty { return namen }
        }
        return []
    }

    func kuenstlerAus(_ e: JEintrag) -> Kuenstler {
        let primaer = e.bildmarken["Primary"].map { Bildbezug(id: e.id, marke: $0) }
        let hintergrund = e.hintergrundmarken.first.map { Bildbezug(id: e.id, marke: $0, hintergrund: true) }
        return Kuenstler(id: e.id, name: e.name, bild: primaer, heldbild: hintergrund ?? primaer,
                         albumzahl: e.kinder, favorit: e.nutzer?.favorit ?? false)
    }

    func playlistAus(_ e: JEintrag) -> Playlist {
        Playlist(id: e.id, name: e.name, liedzahl: e.kinder, dauer: e.dauer,
                 bild: e.bildmarken["Primary"].map { Bildbezug(id: e.id, marke: $0) },
                 geaendert: e.angelegt, favorit: e.nutzer?.favorit ?? false)
    }

    /// Die Künstlerzeile: der erste nicht leere Wert.
    static func zeile(_ einzeln: String?, _ liste: [String], _ sonst: [String]) -> String? {
        if let einzeln, !einzeln.isEmpty { return einzeln }
        let a = liste.filter { !$0.isEmpty }
        if !a.isEmpty { return a.joined(separator: ", ") }
        let b = sonst.filter { !$0.isEmpty }
        return b.isEmpty ? nil : b.joined(separator: ", ")
    }

    /// **Der Behälter nach der Dateiendung, sonst nach Jellyfins Angabe.**
    /// Jellyfin nennt MP4-Verwandte oft als Liste (`mov,mp4,m4a,…`); die
    /// Endung ist eindeutiger.
    static func behaelter(pfad: String?, container: String?) -> String? {
        if let pfad, let punkt = pfad.lastIndex(of: ".") {
            let endung = pfad[pfad.index(after: punkt)...].lowercased()
            if !endung.isEmpty, endung.count <= 5, !endung.contains("/"), !endung.contains("\\") {
                return endung
            }
        }
        guard let container else { return nil }
        let teile = container.lowercased().split(separator: ",").map(String.init)
        for bevorzugt in ["m4a", "m4b", "mp4", "flac", "mp3", "ogg", "opus", "wav"] where teile.contains(bevorzugt) {
            return bevorzugt
        }
        return teile.first
    }

    // MARK: - Bibliothek

    public func alben(_ anfrage: Listenanfrage<Albumsortierung>) async throws -> Seite<Album> {
        switch anfrage.sortierung {
        case .zuletztGehoert:
            return try await albenAusLiedern(sortiertNach: "DatePlayed", anfrage)
        case .oftGehoert:
            return try await albenAusLiedern(sortiertNach: "PlayCount", anfrage)
        default:
            let sortierung: [URLQueryItem] = switch anfrage.sortierung {
            case .neu: Self.sortierung("DateCreated", absteigend: true)
            case .name: Self.sortierung("SortName", absteigend: false)
            case .kuenstler: Self.sortierung("AlbumArtist,SortName", absteigend: false)
            case .jahr: Self.sortierung("ProductionYear", absteigend: true)
            default: [.init(name: "SortBy", value: "Random")]
            }
            let antwort = try await eintraege(Self.liste("MusicAlbum", felder: Self.albumFelder)
                + sortierung + Self.filterwerte(anfrage.filter) + Self.seite(anfrage.ab, anfrage.anzahl))
            return Seite(eintraege: antwort.eintraege.map(albumAus), gesamt: antwort.gesamt,
                         weiterAb: Seite<Album>.weiter(ab: anfrage.ab, bekommen: antwort.eintraege.count,
                                                       verlangt: anfrage.anzahl, gesamt: antwort.gesamt))
        }
    }

    /// **Alben nach ihren Liedern.** Jellyfin führt „zuletzt gespielt" und
    /// die Zählung am Lied, nicht am Album — also die Lieder danach sortiert
    /// holen und ihre Alben in dieser Reihenfolge nehmen.
    ///
    /// Mit `mindestensHalb` bleibt nur, wovon mindestens die Hälfte der
    /// Lieder gespielt wurde (``Zuletztgehoert/albumGehoert(gespielt:liedzahl:)``)
    /// — gezählt an denselben gespielten Liedern, ohne weitere Anfrage.
    /// Dafür werden dreimal so viele Alben angesehen wie verlangt.
    private func albenAusLiedern(sortiertNach feld: String, mindestensHalb: Bool = false,
                                 _ anfrage: Listenanfrage<Albumsortierung>) async throws -> Seite<Album> {
        let lieder = try await eintraege([
            .init(name: "IncludeItemTypes", value: "Audio"),
            .init(name: "Recursive", value: "true"),
            .init(name: "Filters", value: "IsPlayed"),
            .init(name: "Limit", value: "800"),
            .init(name: "EnableImages", value: "false"),
            .init(name: "EnableUserData", value: "true"),
        ] + Self.sortierung(feld, absteigend: true))
        var folge: [String] = []
        var gesehen = Set<String>()
        var zeit: [String: Date] = [:]
        var gespielt: [String: Int] = [:]
        for e in lieder.eintraege {
            guard let id = e.albumID else { continue }
            gespielt[id, default: 0] += 1
            guard !gesehen.contains(id) else { continue }
            gesehen.insert(id)
            folge.append(id)
            zeit[id] = e.nutzer?.zuletzt
        }
        let teil = Array(folge.dropFirst(anfrage.ab).prefix(mindestensHalb ? anfrage.anzahl * 3 : anfrage.anzahl))
        guard !teil.isEmpty else { return Seite(eintraege: [], gesamt: folge.count, weiterAb: nil) }
        let antwort = try await eintraege(Self.liste("MusicAlbum", felder: Self.albumFelder)
            + [.init(name: "Ids", value: teil.joined(separator: ","))]
            + Self.filterwerte(anfrage.filter))
        let nachID = Dictionary(antwort.eintraege.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var alben = teil.compactMap { id -> Album? in
            guard let e = nachID[id] else { return nil }
            var a = albumAus(e)
            a.zuletztGespielt = zeit[id] ?? a.zuletztGespielt
            return a
        }
        if mindestensHalb {
            alben = Array(alben.filter {
                Zuletztgehoert.albumGehoert(gespielt: gespielt[$0.id] ?? 0, liedzahl: $0.liedzahl)
            }.prefix(anfrage.anzahl))
            return Seite(eintraege: alben, gesamt: nil, weiterAb: nil)
        }
        let naechste = anfrage.ab + teil.count
        return Seite(eintraege: alben, gesamt: folge.count,
                     weiterAb: naechste < folge.count ? naechste : nil)
    }

    public func kuenstlerliste(_ anfrage: Listenanfrage<Kuenstlersortierung>) async throws -> Seite<Kuenstler> {
        var werte: [URLQueryItem] = [
            .init(name: "userId", value: sitzung.userID),
            .init(name: "Fields", value: "SortName,ChildCount"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "EnableImageTypes", value: "Primary,Backdrop"),
            .init(name: "ImageTypeLimit", value: "1"),
        ] + Self.sortierung("SortName", absteigend: false) + Self.seite(anfrage.ab, anfrage.anzahl)
        if anfrage.filter.nurFavoriten { werte.append(.init(name: "isFavorite", value: "true")) }
        if let bibliothek { werte.append(.init(name: "parentId", value: bibliothek)) }
        let antwort = try await holen("Artists/AlbumArtists", werte, als: JListe.self)
        return Seite(eintraege: antwort.eintraege.map(kuenstlerAus), gesamt: antwort.gesamt,
                     weiterAb: Seite<Kuenstler>.weiter(ab: anfrage.ab, bekommen: antwort.eintraege.count,
                                                       verlangt: anfrage.anzahl, gesamt: antwort.gesamt))
    }

    public func playlists() async throws -> [Playlist] {
        let antwort = try await eintraege(Self.liste("Playlist", felder: "ChildCount,DateCreated,SortName")
            + [.init(name: "MediaTypes", value: "Audio")]
            + Self.sortierung("SortName", absteigend: false))
        return antwort.eintraege.map(playlistAus)
    }

    public func lieder(_ anfrage: Listenanfrage<Liedsortierung>) async throws -> Seite<Lied> {
        var dazu: [String] = []
        let sortierung: [URLQueryItem]
        switch anfrage.sortierung {
        case .name: sortierung = Self.sortierung("SortName", absteigend: false)
        case .neu: sortierung = Self.sortierung("DateCreated", absteigend: true)
        case .zuletztGehoert:
            sortierung = Self.sortierung("DatePlayed", absteigend: true)
            dazu = ["IsPlayed"]
        case .oftGehoert:
            sortierung = Self.sortierung("PlayCount", absteigend: true)
            dazu = ["IsPlayed"]
        case .zufall: sortierung = [.init(name: "SortBy", value: "Random")]
        }
        let antwort = try await eintraege(Self.liste("Audio", felder: Self.liedFelder) + sortierung
            + Self.filterwerte(anfrage.filter, dazu: dazu) + Self.seite(anfrage.ab, anfrage.anzahl))
        return Seite(eintraege: antwort.eintraege.map(liedAus), gesamt: antwort.gesamt,
                     weiterAb: Seite<Lied>.weiter(ab: anfrage.ab, bekommen: antwort.eintraege.count,
                                                  verlangt: anfrage.anzahl, gesamt: antwort.gesamt))
    }

    // MARK: - Hörbücher

    public func hatHoerbuecher() async -> Bool {
        guard let antwort = try? await eintraege([
            .init(name: "IncludeItemTypes", value: "AudioBook"),
            .init(name: "Recursive", value: "true"),
            .init(name: "Limit", value: "1"),
            .init(name: "EnableImages", value: "false"),
            .init(name: "EnableUserData", value: "false"),
        ]) else { return false }
        return (antwort.gesamt ?? antwort.eintraege.count) > 0
    }

    public func hoerbuecher() async throws -> [Hoerbuch] {
        let antwort = try await eintraege(Self.liste("AudioBook", felder: "ParentId,DateCreated,SortName")
            + Self.sortierung("SortName", absteigend: false)
            + [.init(name: "Limit", value: "3000")])
        return Hoerbuchgruppen.bilden(antwort.eintraege.map { ($0, liedAus($0)) })
    }

    public func hoerbuch(_ id: String) async throws -> Hoerbuchdetail {
        let schluessel = Hoerbuchgruppen.Schluessel(id)
        let teile: [(JEintrag, Lied)]
        switch schluessel {
        case let .teil(itemID):
            let e = try await eintrag(itemID)
            teile = [(e, liedAus(e))]
        case let .ordner(eltern, album):
            let antwort = try await eintraege(Self.liste("AudioBook", felder: Self.liedFelder)
                + [.init(name: "ParentId", value: eltern)]
                + Self.sortierung("ParentIndexNumber,IndexNumber,SortName", absteigend: false))
            teile = antwort.eintraege
                .filter { album == nil || ($0.album ?? $0.name) == album }
                .map { ($0, liedAus($0)) }
        }
        guard let gebaut = Hoerbuchgruppen.bilden(teile).first else {
            throw JellyfinError.http(status: 404, body: nil)
        }
        // Unter der Kennung, unter der es verlangt wurde — sonst stünde es in
        // „Zuletzt gehört" zweimal.
        let buch = Hoerbuch(id: id, titel: gebaut.titel, autor: gebaut.autor, bild: gebaut.bild,
                            dauer: gebaut.dauer, jahr: gebaut.jahr, teilzahl: gebaut.teilzahl)
        return Hoerbuchdetail(hoerbuch: buch, teile: teile.map(\.1))
    }

    // MARK: - Seiten

    public func album(_ id: String) async throws -> Albumdetail {
        async let kopf = eintrag(id)
        async let liste = eintraege(Self.liste("Audio", felder: Self.liedFelder)
            + [.init(name: "ParentId", value: id)]
            + Self.sortierung("ParentIndexNumber,IndexNumber,SortName", absteigend: false))
        let (e, l) = try await (kopf, liste)
        var a = albumAus(e)
        // Der Albumpegel steht am Album, nicht am Lied — er gilt für alle.
        let lieder = l.eintraege.map(liedAus).map { lied in
            var lied = lied
            if let albumpegel = e.pegel {
                var l = lied.lautheit ?? Lautheit()
                l.album = albumpegel
                lied.lautheit = l
            }
            return lied
        }
        if a.liedzahl == nil { a.liedzahl = lieder.count }
        if a.dauer == nil {
            let summe = lieder.compactMap(\.dauer).reduce(0, +)
            a.dauer = summe > 0 ? summe : nil
        }
        return Albumdetail(album: a, lieder: lieder)
    }

    public func kuenstler(_ id: String) async throws -> Kuenstlerdetail {
        async let kopf = holen("Items/\(id)", [.init(name: "userId", value: sitzung.userID),
                                                .init(name: "Fields", value: "Genres")], als: JEintrag.self)
        async let albenAnfrage = eintraege(Self.liste("MusicAlbum", felder: Self.albumFelder)
            + [.init(name: "AlbumArtistIds", value: id)]
            + Self.sortierung("ProductionYear,SortName", absteigend: true))
        async let zahl = eintraege([
            .init(name: "IncludeItemTypes", value: "Audio"),
            .init(name: "Recursive", value: "true"),
            .init(name: "ArtistIds", value: id),
            .init(name: "Limit", value: "1"),
            .init(name: "EnableImages", value: "false"),
            .init(name: "EnableUserData", value: "false"),
        ])
        let e = try await kopf
        var alben = try await albenAnfrage.eintraege.map(albumAus)
        if alben.isEmpty {
            // Wer nur auf fremden Alben mitsingt, ist nirgends Albumkünstler.
            alben = (try? await eintraege(Self.liste("MusicAlbum", felder: Self.albumFelder)
                + [.init(name: "ArtistIds", value: id)]
                + Self.sortierung("ProductionYear,SortName", absteigend: true)).eintraege.map(albumAus)) ?? []
        }
        let liedzahl = (try? await zahl).flatMap { $0.gesamt }
        var k = kuenstlerAus(e)
        k.albumzahl = alben.count
        let genres = e.genres.isEmpty ? Haeufigkeit.ordnen(alben.flatMap(\.genres)) : e.genres
        return Kuenstlerdetail(kuenstler: k, alben: alben, liedzahl: liedzahl, genres: genres)
    }

    public func oftGehoert(von kuenstler: Kuenstler, anzahl: Int) async throws -> [Lied] {
        let antwort = try await eintraege(Self.liste("Audio", felder: Self.liedFelder)
            + [.init(name: "ArtistIds", value: kuenstler.id),
               .init(name: "Filters", value: "IsPlayed"),
               .init(name: "Limit", value: String(anzahl))]
            + Self.sortierung("PlayCount", absteigend: true))
        return antwort.eintraege.map(liedAus).filter { ($0.gespielt ?? 0) > 0 }
    }

    /// Eine Abfrage, aufsteigend nach Album und Nummer — die Folge der Alben
    /// (das neueste zuerst) ordnet danach eine stabile Sortierung nach Jahr.
    /// Mehrere Richtungen in einer Abfrage kennt Jellyfin erst ab 10.9.
    public func alleLieder(von kuenstler: Kuenstler) async throws -> [Lied] {
        let antwort = try await eintraege(Self.liste("Audio", felder: Self.liedFelder)
            + [.init(name: "ArtistIds", value: kuenstler.id), .init(name: "Limit", value: "1500")]
            + Self.sortierung("Album,ParentIndexNumber,IndexNumber,SortName", absteigend: false))
        return antwort.eintraege.map(liedAus).enumerated()
            .sorted { a, b in
                let (ja, jb) = (a.element.jahr ?? 0, b.element.jahr ?? 0)
                return ja != jb ? ja > jb : a.offset < b.offset
            }
            .map(\.element)
    }

    public func playlist(_ id: String) async throws -> Playlistdetail {
        async let kopf = eintrag(id)
        async let liste = holen("Playlists/\(id)/Items", [
            .init(name: "userId", value: sitzung.userID),
            .init(name: "Fields", value: Self.liedFelder),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "EnableImageTypes", value: "Primary"),
            .init(name: "ImageTypeLimit", value: "1"),
        ], als: JListe.self)
        let (e, l) = try await (kopf, liste)
        var p = playlistAus(e)
        let lieder = l.eintraege.map(liedAus)
        p.liedzahl = lieder.count
        if p.dauer == nil {
            let summe = lieder.compactMap(\.dauer).reduce(0, +)
            p.dauer = summe > 0 ? summe : nil
        }
        return Playlistdetail(playlist: p, lieder: lieder,
                              eintraege: l.eintraege.enumerated().map { $1.eintragID ?? String($0) })
    }

    // MARK: - Playlists bearbeiten

    /// Alle Lieder mit Herz — ohne `ParentId` (``lieblingsabfrage(benutzer:)``).
    public func lieblingssongs() async throws -> [Lied] {
        try await holen("Items", Self.lieblingsabfrage(benutzer: sitzung.userID), als: JListe.self)
            .eintraege.map(liedAus)
    }

    public func playlistAnlegen(name: String, lieder: [Lied]) async throws -> Playlist {
        let rumpf = try JSONSerialization.data(withJSONObject: [
            "Name": name, "Ids": lieder.map(\.id), "UserId": sitzung.userID, "MediaType": "Audio",
        ])
        let daten = try await client.rohdaten("Playlists", methode: "POST", rumpf: rumpf)
        guard let wurzel = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let id = wurzel["Id"] as? String else {
            throw JellyfinError.decoding("Playlists: keine Id")
        }
        return Playlist(id: id, name: name, liedzahl: lieder.count,
                        dauer: lieder.compactMap(\.dauer).reduce(0, +), geaendert: Date())
    }

    /// Seit 10.9 `POST /Playlists/{id}` mit dem neuen Namen.
    public func playlistUmbenennen(_ id: String, name: String) async throws {
        let rumpf = try JSONSerialization.data(withJSONObject: ["Name": name])
        _ = try await client.rohdaten("Playlists/\(id)", methode: "POST", rumpf: rumpf)
    }

    public func playlistLoeschen(_ id: String) async throws {
        _ = try await client.rohdaten("Items/\(id)", methode: "DELETE")
    }

    /// In Bündeln zu 50 — die Kennungen stehen in der Adresse.
    public func playlistErgaenzen(_ id: String, lieder: [Lied]) async throws {
        for teil in Playlistfolge.buendel(lieder.map(\.id)) {
            _ = try await client.rohdaten("Playlists/\(id)/Items", methode: "POST", abfrage: [
                .init(name: "ids", value: teil.joined(separator: ",")),
                .init(name: "userId", value: sitzung.userID),
            ])
        }
    }

    /// Entfernt über die **Eintragskennung** (`PlaylistItemId`), nicht über
    /// die Lied-ID — sonst fiele bei doppelten Liedern das falsche heraus.
    public func playlistEntfernen(_ id: String, stellen: [Int], vorher: Playlistdetail) async throws {
        let kennungen = stellen.compactMap { vorher.eintraege.indices.contains($0) ? vorher.eintraege[$0] : nil }
        for teil in Playlistfolge.buendel(kennungen) {
            _ = try await client.rohdaten("Playlists/\(id)/Items", methode: "DELETE", abfrage: [
                .init(name: "entryIds", value: teil.joined(separator: ",")),
            ])
        }
    }

    public func playlistVerschieben(_ id: String, von: Int, nach: Int, vorher: Playlistdetail) async throws {
        guard vorher.eintraege.indices.contains(von) else { return }
        _ = try await client.rohdaten("Playlists/\(id)/Items/\(vorher.eintraege[von])/Move/\(nach)",
                                      methode: "POST")
    }

    // MARK: - Start

    public func zuletztHinzugefuegt(anzahl: Int) async throws -> [Album] {
        try await alben(Listenanfrage(sortierung: .neu, anzahl: anzahl)).eintraege
    }

    /// Nur Alben, von denen mindestens die Hälfte gespielt wurde — ein
    /// einzelnes Lied macht ein Album nicht zu „zuletzt gehört".
    public func zuletztGehoert(anzahl: Int) async throws -> [Album] {
        try await albenAusLiedern(sortiertNach: "DatePlayed", mindestensHalb: true,
                                  Listenanfrage(sortierung: .zuletztGehoert, anzahl: anzahl)).eintraege
    }

    public func oftGehoerteAlben(anzahl: Int) async throws -> [Album] {
        try await alben(Listenanfrage(sortierung: .oftGehoert, anzahl: anzahl)).eintraege
    }

    public func sofortmix(_ ziel: Mixziel, anzahl: Int) async throws -> [Lied] {
        let kennung: String
        switch ziel {
        case let .album(a): kennung = a.id
        case let .kuenstler(id, _): kennung = id
        case let .lied(l): kennung = l.id
        case let .playlist(p): kennung = p.id
        case let .genre(name):
            // Ein Genre-Mix ist bei Jellyfin ohnehin eine Zufallsauswahl aus
            // dem Genre; über den Namen spart es die Suche nach der Kennung.
            let antwort = try await eintraege(Self.liste("Audio", felder: Self.liedFelder)
                + [.init(name: "Genres", value: name),
                   .init(name: "SortBy", value: "Random"),
                   .init(name: "Limit", value: String(anzahl))])
            return antwort.eintraege.map(liedAus)
        }
        let antwort = try await holen("Items/\(kennung)/InstantMix", [
            .init(name: "userId", value: sitzung.userID),
            .init(name: "Limit", value: String(anzahl)),
            .init(name: "Fields", value: Self.liedFelder),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "EnableImageTypes", value: "Primary"),
            .init(name: "ImageTypeLimit", value: "1"),
        ], als: JListe.self)
        return antwort.eintraege.map(liedAus)
    }

    // MARK: - Suche

    public func suche(_ begriff: String) async throws -> Suchergebnis {
        let such = [URLQueryItem(name: "searchTerm", value: begriff)]
        async let lieder = eintraege(Self.liste("Audio", felder: Self.liedFelder) + such
            + [.init(name: "Limit", value: "25")])
        async let alben = eintraege(Self.liste("MusicAlbum", felder: Self.albumFelder) + such
            + [.init(name: "Limit", value: "12")])
        async let playlists = eintraege(Self.liste("Playlist", felder: "ChildCount") + such
            + [.init(name: "MediaTypes", value: "Audio"), .init(name: "Limit", value: "8")])
        async let kuenstler = holen("Artists", such + (bibliothek.map { [.init(name: "parentId", value: $0)] } ?? []) + [
            .init(name: "userId", value: sitzung.userID),
            .init(name: "Limit", value: "6"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "EnableImageTypes", value: "Primary,Backdrop"),
            .init(name: "ImageTypeLimit", value: "1"),
        ], als: JListe.self)
        let (l, a, p, k) = try await (lieder, alben, playlists, kuenstler)
        return Suchergebnis(lieder: l.eintraege.map(liedAus), alben: a.eintraege.map(albumAus),
                            kuenstler: k.eintraege.map(kuenstlerAus), playlists: p.eintraege.map(playlistAus))
    }

    // MARK: - Liedtext und Favorit

    public func liedtext(_ lied: Lied) async throws -> Liedtext? {
        let text: JLiedtext
        do {
            text = try await holen("Audio/\(lied.id)/Lyrics", [], als: JLiedtext.self)
        } catch let JellyfinError.http(status, _) where status == 404 {
            return nil
        }
        let zeilen = text.zeilen.map {
            Liedtext.Zeile(zeit: $0.startTicks.map { TimeInterval($0) / 10_000_000 }, text: $0.text)
        }
        let ergebnis = Liedtext(zeilen: zeilen)
        return ergebnis.istLeer ? nil : ergebnis
    }

    public func favorit(_ ziel: Favoritziel, an: Bool) async throws {
        let id: String
        switch ziel {
        case let .lied(x), let .album(x), let .kuenstler(x), let .playlist(x): id = x
        }
        // Ein Lied kann gerade laufen — dann setzt die nächste Meldung das
        // Herz zurück, wenn es nicht nachgesetzt wird (``Favoritenstand``).
        if case .lied = ziel { favoritenstand.merken(id, an: an) }
        try await favoritSenden(id, an: an)
    }

    // MARK: - Wiedergabe

    public func abspielweg(_ lied: Lied, sitzung spielkennung: String, hoechstens: Int?) -> Abspielweg? {
        weg(lied, spielkennung: spielkennung, hoechstens: hoechstens)
    }

    public func ladeweg(_ lied: Lied) -> Abspielweg? {
        weg(lied, spielkennung: nil, hoechstens: nil)
    }

    /// Mit `ApiKey` in der Adresse wie beim iPhone — der Lautsprecher holt
    /// selbst und kann keine Köpfe mitschicken.
    public func sonosweg(_ lied: Lied) -> Abspielweg? {
        weg(lied, spielkennung: nil, hoechstens: nil, fuerSonos: true)
    }

    public var sonosMoeglich: Bool { true }

    /// **Die Abspieladresse.** Direkt: `/Audio/{id}/stream.{endung}` mit
    /// `static=true` — die Datei unverändert, mit Endung, an der AVFoundation
    /// das Format erkennt. Sonst MP3 in 320 kbit/s, fortlaufend
    /// (``Abspielregel/umwandlung(fuer:)``).
    ///
    /// Das Zugangsmerkmal steht als `ApiKey` in der Adresse: AVFoundation holt
    /// selbst und schickt keine eigenen Köpfe mit. `api_key` kennt Jellyfin 12
    /// nicht mehr, `ApiKey` gibt es seit 10.8 (siehe `JellyfinClient.streamURL`).
    // MARK: - Aushandeln

    let entscheidungen = Entscheidungen()

    /// Fragt für jedes Lied, das noch keine Antwort hat, `PlaybackInfo` mit
    /// dem Geräteprofil. Scheitert es, gilt die eigene Regel wie vorher.
    public func vorbereiten(_ lieder: [Lied], hoechstens: Int?) async {
        for lied in lieder where entscheidungen[lied.id] == nil {
            guard let daten = try? await client.rohdaten(
                "Items/\(lied.id)/PlaybackInfo", methode: "POST",
                abfrage: [.init(name: "userId", value: sitzung.userID),
                          .init(name: "AutoOpenLiveStream", value: "false")],
                rumpf: Geraeteprofil.rumpf(hoechstens: hoechstens)),
                  let entscheid = Serverentscheid.lesen(daten) else { continue }
            entscheidungen[lied.id] = entscheid
        }
    }

    private func weg(_ lied: Lied, spielkennung: String?, hoechstens: Int?,
                     fuerSonos: Bool = false) -> Abspielweg? {
        // Zum Laden (ohne Wiedergabekennung) gilt das Original; für Sonos,
        // was der Lautsprecher kann.
        let entscheidung = fuerSonos ? Sonosregel.umwandlung(fuer: lied.format)
            : spielkennung == nil
            ? Abspielregel.umwandlung(fuer: lied.format, hoechstens: nil)
            : Serverentscheid.umwandlung(fuer: lied.format, hoechstens: hoechstens,
                                         server: entscheidungen[lied.id])
        let direkt = entscheidung == nil
        var werte: [URLQueryItem] = [
            .init(name: "mediaSourceId", value: lied.quellID ?? lied.id),
            .init(name: "deviceId", value: geraeteID),
        ]
        if let spielkennung { werte.append(.init(name: "playSessionId", value: spielkennung)) }
        let pfad: String
        let mime: String?
        let umwandlung: Umwandlung?
        if direkt {
            let endung = lied.format?.behaelter.flatMap { Abspielregel.behaelter.contains($0) ? $0 : nil }
            pfad = endung.map { "Audio/\(lied.id)/stream.\($0)" } ?? "Audio/\(lied.id)/stream"
            werte.insert(.init(name: "static", value: "true"), at: 0)
            mime = lied.format?.mime ?? Abspielregel.mime(fuer: endung)
            umwandlung = nil
        } else {
            let ziel = entscheidung ?? Abspielregel.umwandlung(fuer: .jellyfin)
            pfad = "Audio/\(lied.id)/stream.\(ziel.codec)"
            werte.insert(contentsOf: [
                .init(name: "static", value: "false"),
                .init(name: "audioCodec", value: ziel.codec),
                .init(name: "audioBitRate", value: String(ziel.bitrate * 1000)),
                .init(name: "maxAudioChannels", value: "2"),
                .init(name: "estimateContentLength", value: "true"),
            ], at: 0)
            mime = "audio/mpeg"
            umwandlung = ziel
        }
        werte.append(.init(name: "ApiKey", value: sitzung.accessToken))
        guard var teile = URLComponents(url: client.baseURL.appendingPathComponent(pfad),
                                        resolvingAgainstBaseURL: false) else { return nil }
        teile.queryItems = werte
        guard let adresse = teile.url else { return nil }
        return Abspielweg(adresse: adresse, mime: mime, art: direkt ? .direkt : .umgewandelt,
                          format: lied.format, umwandlung: umwandlung, sitzung: spielkennung)
    }

    /// Der Rumpf der Wiedergabemeldungen, in Jellyfins Schreibweise.
    struct Meldekoerper: Encodable {
        let ItemId: String
        let MediaSourceId: String?
        let PlaySessionId: String?
        let PositionTicks: Int64
        let IsPaused: Bool
        let CanSeek: Bool
        let PlayMethod: String
        let PlaybackOrder: String
        let RepeatMode: String
        let EventName: String?
        let VolumeLevel: Int
        let IsMuted: Bool
        /// Wer uns steuert, sieht so die Schlange (``Wiedergabestand/schlange``).
        let NowPlayingQueue: [Schlangeneintrag]?
        let PlaylistItemId: String?

        struct Schlangeneintrag: Encodable {
            let Id: String
            let PlaylistItemId: String
        }

        init(_ stand: Wiedergabestand, ereignis: String?) {
            ItemId = stand.lied.id
            MediaSourceId = stand.lied.quellID ?? stand.lied.id
            PlaySessionId = stand.sitzung
            PositionTicks = Int64(max(0, stand.position) * 10_000_000)
            IsPaused = stand.pausiert
            CanSeek = true
            PlayMethod = stand.art == .direkt ? "DirectPlay" : "Transcode"
            PlaybackOrder = stand.gemischt ? "Shuffle" : "Default"
            RepeatMode = switch stand.wiederholung {
            case .aus: "RepeatNone"
            case .alles: "RepeatAll"
            case .eines: "RepeatOne"
            }
            EventName = ereignis
            VolumeLevel = stand.lautstaerke
            IsMuted = stand.stumm
            // Dieselbe Obergrenze wie beim Übergeben: ein Rumpf mit 2000
            // Einträgen alle zehn Sekunden hilft niemandem.
            let (ids, ab) = Uebergabe.fenster(stand.schlange, ab: stand.index ?? 0)
            NowPlayingQueue = ids.isEmpty ? nil
                : ids.enumerated().map { Schlangeneintrag(Id: $1, PlaylistItemId: "playlistItem\($0)") }
            PlaylistItemId = ids.isEmpty || stand.index == nil ? nil : "playlistItem\(ab)"
        }
    }

    struct Endekoerper: Encodable {
        let ItemId: String
        let MediaSourceId: String?
        let PlaySessionId: String?
        let PositionTicks: Int64
        let Failed: Bool

        init(_ stand: Wiedergabestand) {
            ItemId = stand.lied.id
            MediaSourceId = stand.lied.quellID ?? stand.lied.id
            PlaySessionId = stand.sitzung
            PositionTicks = Int64(max(0, stand.position) * 10_000_000)
            Failed = false
        }
    }

    public func melde(_ meldung: Wiedergabemeldung) async {
        let pfad: String
        let rumpf: Data?
        switch meldung {
        case let .beginn(stand):
            pfad = "Sessions/Playing"
            rumpf = try? JSONEncoder().encode(Meldekoerper(stand, ereignis: nil))
        case let .fortschritt(stand):
            pfad = "Sessions/Playing/Progress"
            rumpf = try? JSONEncoder().encode(
                Meldekoerper(stand, ereignis: stand.pausiert ? "pause" : "timeupdate"))
        case let .ende(stand):
            pfad = "Sessions/Playing/Stopped"
            rumpf = try? JSONEncoder().encode(Endekoerper(stand))
        case .gehoert:
            // Jellyfin zählt selbst, wenn die Wiedergabe endet.
            return
        }
        guard let rumpf else { return }
        _ = try? await client.rohdaten(pfad, methode: "POST", rumpf: rumpf)
        await favoritNachMeldung(meldung)
    }

    /// Live zählt Jellyfin selbst; nachträglich wird das Lied mit dem
    /// Zeitpunkt, an dem es lief, als gespielt markiert.
    public func scrobbeln(_ lied: Lied, beginn: Date, nachtraeglich: Bool) async throws {
        guard nachtraeglich else { return }
        let zeit = ISO8601DateFormatter().string(from: beginn)
        _ = try await client.rohdaten("UserPlayedItems/\(lied.id)", methode: "POST",
                                      abfrage: [.init(name: "userId", value: sitzung.userID),
                                                .init(name: "datePlayed", value: zeit)])
    }

    // MARK: - Bilder

    public func bildadresse(_ bild: Bildbezug, kante: Int) -> URL? {
        bilder.bauen(itemID: bild.id, art: bild.hintergrund ? .hintergrund : .poster, marke: bild.marke,
                     mass: .fuellend(breit: kante, hoch: kante))
    }

    public func heldbildadresse(_ bild: Bildbezug, breite: Int) -> URL? {
        bilder.bauen(itemID: bild.id, art: bild.hintergrund ? .hintergrund : .poster, marke: bild.marke,
                     mass: .hoechstensBreit(breite), guete: 85)
    }

    public func profilbildadresse(kante: Int) -> URL? {
        bilder.benutzer(sitzung.userID, kante: kante)
    }

    public func abmelden() async {
        await client.abmelden()
    }

    /// Dieselbe Frage wie der Player beim Start (`sitzungGiltNoch`): ein
    /// Aufruf, den nur ein gültiges Merkmal besteht.
    public func anmeldungPruefen() async -> Anmeldestand {
        await client.sitzungGiltNoch() ? .gilt : .giltNicht
    }
}

/// **Hörbücher aus ihren Teilen.**
///
/// Jellyfin führt jede Datei als eigenes `AudioBook`. Ein Buch aus mehreren
/// Dateien liegt in einem Ordner; ein Ordner mit lauter einzelnen `.m4b`
/// enthält dagegen mehrere Bücher. Also: je Ordner nach dem Albumtag
/// gruppieren — ein Tag, ein Buch.
enum Hoerbuchgruppen {

    enum Schluessel: Equatable {
        case teil(String)
        case ordner(String, album: String?)

        init(_ id: String) {
            if id.hasPrefix("teil:") {
                self = .teil(String(id.dropFirst(5)))
            } else if id.hasPrefix("ordner:") {
                let rest = id.dropFirst(7)
                if let trenner = rest.firstIndex(of: "|") {
                    self = .ordner(String(rest[..<trenner]), album: String(rest[rest.index(after: trenner)...]))
                } else {
                    self = .ordner(String(rest), album: nil)
                }
            } else {
                self = .teil(id)
            }
        }
    }

    static func bilden(_ teile: [(JEintrag, Lied)]) -> [Hoerbuch] {
        var ordnerFolge: [String] = []
        var nachOrdner: [String: [(JEintrag, Lied)]] = [:]
        for teil in teile {
            let ordner = teil.0.elternID ?? "?"
            if nachOrdner[ordner] == nil { ordnerFolge.append(ordner) }
            nachOrdner[ordner, default: []].append(teil)
        }
        var buecher: [Hoerbuch] = []
        for ordner in ordnerFolge {
            let inhalt = nachOrdner[ordner] ?? []
            var albumFolge: [String] = []
            var nachAlbum: [String: [(JEintrag, Lied)]] = [:]
            for teil in inhalt {
                let album = teil.0.album ?? teil.0.name
                if nachAlbum[album] == nil { albumFolge.append(album) }
                nachAlbum[album, default: []].append(teil)
            }
            for album in albumFolge {
                let gruppe = nachAlbum[album] ?? []
                guard let erstes = gruppe.first else { continue }
                let id: String
                if gruppe.count == 1, albumFolge.count > 1 || ordner == "?" {
                    id = "teil:\(erstes.0.id)"
                } else if albumFolge.count == 1 {
                    id = "ordner:\(ordner)"
                } else {
                    id = "ordner:\(ordner)|\(album)"
                }
                let bild = gruppe.lazy.compactMap { t in t.0.bildmarken["Primary"].map { Bildbezug(id: t.0.id, marke: $0) } }.first
                    ?? (ordner != "?" ? Bildbezug(id: ordner) : nil)
                let dauer = gruppe.compactMap(\.1.dauer).reduce(0, +)
                let titel = gruppe.count == 1 && erstes.0.album == nil ? erstes.0.name : album
                buecher.append(Hoerbuch(id: id, titel: titel,
                                        autor: JellyfinQuelle.zeile(erstes.0.albumKuenstler,
                                                                    erstes.0.kuenstlerNamen, []),
                                        bild: bild, dauer: dauer > 0 ? dauer : nil,
                                        jahr: erstes.0.jahr, teilzahl: gruppe.count))
            }
        }
        return buecher
    }
}

/// Die gewählte Bibliothek, hinter einem Schloss — die Quelle ist `Sendable`.
private final class Gewaehlt: @unchecked Sendable {
    private let schloss = NSLock()
    private var _wert: String?
    var wert: String? {
        get { schloss.withLock { _wert } }
        set { schloss.withLock { _wert = newValue } }
    }
}
