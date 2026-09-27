import Foundation
import SubsonicKit

/// **Musik von einem Subsonic-Server** — Navidrome, Gonic, Airsonic und
/// alles, was OpenSubsonic spricht.
///
/// Subsonic kennt weniger als Jellyfin: keine Liste aller Lieder (dafür die
/// Suche mit leerem Begriff), keine Sortierung der Lieder, keine Hörbücher,
/// keine Wiedergabemeldung außer `scrobble`. Was fehlt, steht in
/// ``faehigkeiten``, damit die Oberfläche es gar nicht erst anbietet.
public final class SubsonicQuelle: Musikquelle {

    public let serverart: Serverart = .subsonic
    public let konto: Kontokennung
    public let benutzername: String
    public let faehigkeiten = Faehigkeiten(
        albumsortierungen: Albumsortierung.allCases,
        liedsortierungen: [.name, .zufall],
        kuenstlerFavoriten: true,
        playlistFavoriten: false)

    public let client: SubsonicClient
    private let merker = Merker()

    public var bibliothek: String? {
        get { client.musikordner }
        set { client.musikordner = newValue }
    }

    public func bibliotheken() async throws -> [Musikbibliothek] {
        try await client.musikordnerliste().map { Musikbibliothek(id: $0.id, name: $0.name) }
    }

    public init(client: SubsonicClient) {
        self.client = client
        konto = Kontokennung(server: client.zugang.server, benutzerID: client.zugang.benutzer)
        benutzername = client.zugang.benutzer
    }

    // MARK: - Umsetzen

    func albumAus(_ a: SubsonicAlbum) -> Album {
        var album = Album(id: a.id, titel: a.name, kuenstler: a.kuenstlerzeile,
              kuenstlerID: a.artistId ?? a.artists.first?.id, jahr: a.year, genres: a.alleGenres,
              liedzahl: a.songCount, dauer: a.duration.map(TimeInterval.init),
              bild: a.coverArt.map { Bildbezug(id: $0) }, favorit: a.starred != nil,
              gespielt: a.playCount, zuletztGespielt: a.played, hinzugefuegt: a.created,
              art: Self.albumart(a.releaseTypes, zusammenstellung: a.isCompilation),
              kuenstlerliste: Kuenstlernamen.liste(a.artists.isEmpty ? [a.artist].compactMap { $0 }
                                                                      : a.artists.map(\.name)))
        // Nennt der Server keine Art, entscheidet die Regel.
        album.art = Veroeffentlichung.art(album)
        return album
    }

    func liedAus(_ l: SubsonicLied) -> Lied {
        let endung = l.suffix?.lowercased()
        let format = Tonformat(codec: Self.codec(endung: endung, bitTiefe: l.bitDepth),
                               behaelter: endung, bitrate: l.bitRate, bitTiefe: l.bitDepth,
                               abtastrate: l.samplingRate, kanaele: l.channelCount, mime: l.contentType)
        return Lied(id: l.id, titel: l.title, kuenstler: l.kuenstlerzeile,
                    kuenstlerID: l.artistId ?? l.artists.first?.id, album: l.album, albumID: l.albumId,
                    nummer: l.track, cd: l.discNumber, dauer: l.duration.map(TimeInterval.init),
                    bild: l.coverArt.map { Bildbezug(id: $0) }, favorit: l.starred != nil,
                    gespielt: l.playCount, format: format, groesse: l.size.map(Int64.init),
                    istHoerbuch: l.type?.lowercased() == "audiobook", genre: l.genre, jahr: l.year,
                    kuenstlerliste: Kuenstlernamen.liste(l.artists.isEmpty ? [l.artist].compactMap { $0 }
                                                                            : l.artists.map(\.name)),
                    lautheit: Self.lautheit(l.replayGain))
    }

    static func lautheit(_ p: SubsonicPegel?) -> Lautheit? {
        guard let p else { return nil }
        let l = Lautheit(lied: p.trackGain, album: p.albumGain, liedspitze: p.trackPeak, albumspitze: p.albumPeak)
        return l.istLeer ? nil : l
    }

    func kuenstlerAus(_ k: SubsonicKuenstler) -> Kuenstler {
        let bild = k.coverArt.map { Bildbezug(id: $0) }
        return Kuenstler(id: k.id, name: k.name, bild: bild, heldbild: bild, albumzahl: k.albumCount,
                         favorit: k.starred != nil)
    }

    func playlistAus(_ p: SubsonicPlaylist) -> Playlist {
        Playlist(id: p.id, name: p.name, liedzahl: p.songCount, dauer: p.duration.map(TimeInterval.init),
                 bild: p.coverArt.map { Bildbezug(id: $0) }, geaendert: p.changed ?? p.created, besitzer: p.owner)
    }

    static func albumart(_ typen: [String], zusammenstellung: Bool?) -> Albumart? {
        let klein = Set(typen.map { $0.lowercased() })
        if klein.contains("ep") { return .ep }
        if klein.contains("single") { return .single }
        if klein.contains("live") { return .live }
        if klein.contains("compilation") || zusammenstellung == true { return .zusammenstellung }
        if klein.contains("album") { return .album }
        return nil
    }

    /// Subsonic nennt keinen Codec, nur die Endung. Eine `.m4a` mit Bittiefe
    /// ist ALAC — Navidrome setzt die Tiefe nur bei verlustfreien Dateien.
    static func codec(endung: String?, bitTiefe: Int?) -> String? {
        switch endung {
        case "mp3": "mp3"
        case "flac": "flac"
        case "m4a", "m4b", "mp4": bitTiefe != nil ? "alac" : "aac"
        case "aac": "aac"
        case "alac": "alac"
        case "ogg", "oga": "vorbis"
        case "opus": "opus"
        case "wav", "aif", "aiff": "pcm"
        case "wma": "wmav2"
        case "ape": "ape"
        case "wv": "wavpack"
        case "dsf", "dff": "dsd"
        default: nil
        }
    }

    // MARK: - Bibliothek

    static func liste(_ s: Albumsortierung) -> SubsonicAlbumliste {
        switch s {
        case .neu: .neueste
        case .name: .nachName
        case .kuenstler: .nachKuenstler
        // Von „weit in der Zukunft" nach 0: absteigend, das neueste Jahr zuerst.
        case .jahr: .nachJahr(von: 9999, bis: 0)
        case .zuletztGehoert: .zuletztGespielt
        case .oftGehoert: .oftGespielt
        case .zufall: .zufall
        }
    }

    public func alben(_ anfrage: Listenanfrage<Albumsortierung>) async throws -> Seite<Album> {
        let liste: SubsonicAlbumliste = anfrage.filter.nurFavoriten ? .favoriten : Self.liste(anfrage.sortierung)
        guard anfrage.filter.nurUngehoert else {
            let alben = try await client.albumliste(liste, anzahl: anfrage.anzahl, ab: anfrage.ab)
            return Seite(eintraege: alben.map(albumAus), gesamt: nil,
                         weiterAb: Seite<Album>.weiter(ab: anfrage.ab, bekommen: alben.count,
                                                       verlangt: anfrage.anzahl, gesamt: nil))
        }
        // **„Ungehört" kennt Subsonic nicht** — also seitenweise holen und
        // selbst aussortieren, bis die Seite voll ist. `weiterAb` zählt dann
        // in der Liste des Servers weiter, nicht in der gefilterten.
        var gefunden: [Album] = []
        var ab = anfrage.ab
        let schritt = max(anfrage.anzahl, 100)
        while gefunden.count < anfrage.anzahl {
            let alben = try await client.albumliste(liste, anzahl: schritt, ab: ab)
            ab += alben.count
            gefunden += alben.filter { ($0.playCount ?? 0) == 0 && $0.played == nil }.map(albumAus)
            if alben.count < schritt {
                return Seite(eintraege: gefunden, gesamt: nil, weiterAb: nil)
            }
        }
        return Seite(eintraege: gefunden, gesamt: nil, weiterAb: ab)
    }

    public func kuenstlerliste(_ anfrage: Listenanfrage<Kuenstlersortierung>) async throws -> Seite<Kuenstler> {
        var alle = try await alleKuenstler()
        if anfrage.filter.nurFavoriten { alle = alle.filter { $0.starred != nil } }
        let teil = Array(alle.dropFirst(anfrage.ab).prefix(anfrage.anzahl))
        let naechste = anfrage.ab + teil.count
        return Seite(eintraege: teil.map(kuenstlerAus), gesamt: alle.count,
                     weiterAb: naechste < alle.count ? naechste : nil)
    }

    /// `getArtists` liefert alle auf einmal — für das Blättern gemerkt,
    /// damit nicht jede Seite die ganze Liste neu holt.
    private func alleKuenstler() async throws -> [SubsonicKuenstler] {
        if let da = merker.kuenstler(), da.zeit.timeIntervalSinceNow > -60 { return da.liste }
        let liste = try await client.alleKuenstler()
        merker.setzeKuenstler(liste)
        return liste
    }

    private func allePlaylists() async throws -> [SubsonicPlaylist] {
        if let da = merker.playlists(), da.zeit.timeIntervalSinceNow > -60 { return da.liste }
        let liste = try await client.playlists()
        merker.setzePlaylists(liste)
        return liste
    }

    public func playlists() async throws -> [Playlist] {
        let liste = try await client.playlists()
        merker.setzePlaylists(liste)
        return liste.map(playlistAus)
    }

    public func lieder(_ anfrage: Listenanfrage<Liedsortierung>) async throws -> Seite<Lied> {
        if anfrage.filter.nurFavoriten {
            let alle = try await client.favoriten().lieder
                .filter { !anfrage.filter.nurUngehoert || ($0.playCount ?? 0) == 0 }
            let teil = Array(alle.dropFirst(anfrage.ab).prefix(anfrage.anzahl))
            let naechste = anfrage.ab + teil.count
            return Seite(eintraege: teil.map(liedAus), gesamt: alle.count,
                         weiterAb: naechste < alle.count ? naechste : nil)
        }
        if anfrage.sortierung == .zufall {
            let lieder = try await client.zufallslieder(anzahl: anfrage.anzahl)
            return Seite(eintraege: lieder.map(liedAus), gesamt: nil, weiterAb: nil)
        }
        // Alle Lieder: die Suche mit leerem Begriff, seitenweise.
        var gefunden: [Lied] = []
        var ab = anfrage.ab
        let schritt = anfrage.filter.nurUngehoert ? max(anfrage.anzahl, 200) : anfrage.anzahl
        repeat {
            let lieder = try await client.suche("", kuenstler: 0, alben: 0, lieder: schritt, liederAb: ab).lieder
            ab += lieder.count
            gefunden += lieder.filter { !anfrage.filter.nurUngehoert || ($0.playCount ?? 0) == 0 }.map(liedAus)
            if lieder.count < schritt { return Seite(eintraege: gefunden, gesamt: nil, weiterAb: nil) }
        } while gefunden.count < anfrage.anzahl
        return Seite(eintraege: gefunden, gesamt: nil, weiterAb: ab)
    }

    public func hoerbuecher() async throws -> [Hoerbuch] { [] }
    public func hatHoerbuecher() async -> Bool { false }
    public func hoerbuch(_ id: String) async throws -> Hoerbuchdetail {
        throw SubsonicFehler.server(code: 70, text: nil)
    }

    // MARK: - Seiten

    public func album(_ id: String) async throws -> Albumdetail {
        let a = try await client.album(id: id)
        var album = albumAus(a)
        let lieder = a.lieder.map(liedAus)
        if album.liedzahl == nil { album.liedzahl = lieder.count }
        return Albumdetail(album: album, lieder: lieder)
    }

    public func kuenstler(_ id: String) async throws -> Kuenstlerdetail {
        let k = try await client.kuenstler(id: id)
        let alben = k.alben.map(albumAus).sorted { ($0.jahr ?? 0) > ($1.jahr ?? 0) }
        var kuenstler = kuenstlerAus(k.kuenstler)
        kuenstler.albumzahl = alben.count
        let lieder = k.alben.compactMap(\.songCount)
        return Kuenstlerdetail(kuenstler: kuenstler, alben: alben,
                               liedzahl: lieder.isEmpty ? nil : lieder.reduce(0, +),
                               genres: Haeufigkeit.ordnen(alben.flatMap(\.genres)))
    }

    /// **Die eigene Zählung, Album für Album.** Subsonic hat keine Liste
    /// „meistgehört je Künstler"; `getTopSongs` fragt Last.fm und weiß nichts
    /// von den eigenen Wiedergaben. Also die Alben des Künstlers holen — die
    /// meistgehörten zuerst, höchstens zwölf — und ihre Lieder nach
    /// `playCount` ordnen.
    public func oftGehoert(von kuenstler: Kuenstler, anzahl: Int) async throws -> [Lied] {
        let alben = try await client.kuenstler(id: kuenstler.id).alben
            .sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
            .prefix(12)
        let lieder = await withTaskGroup(of: [SubsonicLied].self) { gruppe in
            for album in alben where (album.playCount ?? 1) > 0 {
                gruppe.addTask { [client] in (try? await client.album(id: album.id).lieder) ?? [] }
            }
            var alle: [SubsonicLied] = []
            for await teil in gruppe { alle += teil }
            return alle
        }
        return lieder
            .filter { ($0.playCount ?? 0) > 0 }
            .filter { $0.artistId == nil || $0.artistId == kuenstler.id
                || $0.artists.contains { $0.id == kuenstler.id } }
            .sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
            .prefix(anzahl)
            .map(liedAus)
    }

    /// Die Alben vom neuesten an, jedes mit seinen Liedern — ein Abruf je
    /// Album, nebenläufig, die Folge danach wiederhergestellt.
    public func alleLieder(von kuenstler: Kuenstler) async throws -> [Lied] {
        let alben = try await client.kuenstler(id: kuenstler.id).alben
            .sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        let teile = await withTaskGroup(of: (Int, [SubsonicLied]).self) { gruppe in
            for (i, album) in alben.enumerated() {
                gruppe.addTask { [client] in (i, (try? await client.album(id: album.id).lieder) ?? []) }
            }
            var ergebnis: [(Int, [SubsonicLied])] = []
            for await teil in gruppe { ergebnis.append(teil) }
            return ergebnis
        }
        return teile.sorted { $0.0 < $1.0 }.flatMap(\.1).map(liedAus)
    }

    public func playlist(_ id: String) async throws -> Playlistdetail {
        let p = try await client.playlist(id: id)
        var playlist = playlistAus(p)
        let lieder = p.lieder.map(liedAus)
        playlist.liedzahl = lieder.count
        return Playlistdetail(playlist: playlist, lieder: lieder)
    }

    // MARK: - Playlists

    public func lieblingssongs() async throws -> [Lied] {
        try await client.favoriten().lieder.map(liedAus)
    }

    public func playlistAnlegen(name: String, lieder: [Lied]) async throws -> Playlist {
        if let neu = try await client.playlistAnlegen(name: name, liedIDs: lieder.map(\.id)) {
            _ = try? await playlists()
            return playlistAus(neu)
        }
        // Ältere Server sagen nur „ok" — dann in der Liste nachsehen, die
        // neueste mit diesem Namen.
        let liste = try await client.playlists()
        merker.setzePlaylists(liste)
        guard let neu = liste.filter({ $0.name == name })
            .max(by: { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }) else {
            throw SubsonicFehler.server(code: 70, text: nil)
        }
        return playlistAus(neu)
    }

    public func playlistUmbenennen(_ id: String, name: String) async throws {
        try await client.playlistUmbenennen(id: id, name: name)
        _ = try? await playlists()
    }

    public func playlistLoeschen(_ id: String) async throws {
        try await client.playlistLoeschen(id: id)
        _ = try? await playlists()
    }

    public func playlistErgaenzen(_ id: String, lieder: [Lied]) async throws {
        for teil in Playlistfolge.buendel(lieder.map(\.id)) {
            try await client.playlistErgaenzen(id: id, liedIDs: teil)
        }
        _ = try? await playlists()
    }

    /// **Absteigend**: die Stellen gelten für die Liste vor dem Aufruf; ein
    /// Server, der der Reihe nach entfernt, träfe aufsteigend die falschen
    /// (gonic sortiert deshalb selbst absteigend — darauf verlassen wir uns
    /// nicht).
    public func playlistEntfernen(_ id: String, stellen: [Int], vorher: Playlistdetail) async throws {
        try await client.playlistEntfernen(id: id, stellen: stellen.sorted(by: >))
        _ = try? await playlists()
    }

    /// Subsonic kennt kein Verschieben: die ganze Folge wird neu geschrieben.
    public func playlistVerschieben(_ id: String, von: Int, nach: Int, vorher: Playlistdetail) async throws {
        let neu = Playlistfolge.verschoben(vorher.lieder, von: von, nach: nach)
        try await client.playlistNeuSchreiben(id: id, liedIDs: neu.map(\.id))
    }

    // MARK: - Start

    public func zuletztHinzugefuegt(anzahl: Int) async throws -> [Album] {
        try await client.albumliste(.neueste, anzahl: anzahl).map(albumAus)
    }

    public func zuletztGehoert(anzahl: Int) async throws -> [Album] {
        try await client.albumliste(.zuletztGespielt, anzahl: anzahl).map(albumAus)
    }

    public func oftGehoerteAlben(anzahl: Int) async throws -> [Album] {
        try await client.albumliste(.oftGespielt, anzahl: anzahl).map(albumAus)
    }

    /// **Sofortmix: ähnliche Lieder, sonst Zufall aus Künstler oder Genre.**
    ///
    /// `getSimilarSongs2` braucht bei Navidrome eine Anbindung an Last.fm;
    /// ohne kommt eine leere Liste. Dann mischt der Mix die Lieder des
    /// Künstlers, und fehlt der, Zufall aus dem Genre.
    public func sofortmix(_ ziel: Mixziel, anzahl: Int) async throws -> [Lied] {
        var ergebnis: [SubsonicLied] = []
        var vorn: SubsonicLied?
        switch ziel {
        case let .genre(name):
            ergebnis = try await client.zufallslieder(anzahl: anzahl, genre: name)
        case let .kuenstler(id, _):
            ergebnis = try await aehnlichOderKuenstler(id, anzahl: anzahl)
        case let .album(a):
            if let id = a.kuenstlerID {
                ergebnis = try await aehnlichOderKuenstler(id, anzahl: anzahl)
            }
            if ergebnis.isEmpty, let genre = a.genres.first {
                ergebnis = try await client.zufallslieder(anzahl: anzahl, genre: genre)
            }
        case let .lied(l):
            vorn = try? await client.album(id: l.albumID ?? "").lieder.first { $0.id == l.id }
            if let id = l.kuenstlerID {
                ergebnis = try await aehnlichOderKuenstler(id, anzahl: anzahl)
            }
            if ergebnis.isEmpty, let genre = l.genre {
                ergebnis = try await client.zufallslieder(anzahl: anzahl, genre: genre)
            }
        case let .playlist(p):
            let lieder = try await client.playlist(id: p.id).lieder
            let haeufigster = Haeufigkeit.ordnen(lieder.compactMap(\.artistId)).first
            if let haeufigster {
                ergebnis = (try? await client.aehnlicheLieder(kuenstlerID: haeufigster, anzahl: anzahl)) ?? []
            }
            if ergebnis.isEmpty { ergebnis = lieder.shuffled() }
        }
        // Doppelte heraus, das Ausgangslied vorn.
        var gesehen = Set<String>()
        var liste: [SubsonicLied] = []
        for lied in ([vorn].compactMap { $0 } + ergebnis) where !gesehen.contains(lied.id) {
            gesehen.insert(lied.id)
            liste.append(lied)
        }
        return liste.prefix(anzahl).map(liedAus)
    }

    private func aehnlichOderKuenstler(_ id: String, anzahl: Int) async throws -> [SubsonicLied] {
        let aehnlich = (try? await client.aehnlicheLieder(kuenstlerID: id, anzahl: anzahl)) ?? []
        if !aehnlich.isEmpty { return aehnlich }
        let alben = try await client.kuenstler(id: id).alben.prefix(10)
        let lieder = await withTaskGroup(of: [SubsonicLied].self) { gruppe in
            for album in alben {
                gruppe.addTask { [client] in (try? await client.album(id: album.id).lieder) ?? [] }
            }
            var alle: [SubsonicLied] = []
            for await teil in gruppe { alle += teil }
            return alle
        }
        return Array(lieder.shuffled().prefix(anzahl))
    }

    // MARK: - Suche

    public func suche(_ begriff: String) async throws -> Suchergebnis {
        async let treffer = client.suche(begriff, kuenstler: 6, alben: 12, lieder: 25)
        // Playlists sucht `search3` nicht mit — sie kommen aus der eigenen Liste.
        let playlists = ((try? await allePlaylists()) ?? [])
            .filter { $0.name.range(of: begriff, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .prefix(8)
        let t = try await treffer
        return Suchergebnis(lieder: t.lieder.map(liedAus), alben: t.alben.map(albumAus),
                            kuenstler: t.kuenstler.map(kuenstlerAus), playlists: playlists.map(playlistAus))
    }

    // MARK: - Liedtext und Favorit

    /// **Getaktet, wenn der Server es kann** (OpenSubsonic `songLyrics`),
    /// sonst der alte Weg über Künstler und Titel. Der kann trotzdem getaktet
    /// sein: manche Server geben dort den Inhalt einer `.lrc` zurück.
    public func liedtext(_ lied: Lied) async throws -> Liedtext? {
        if await erweiterungen().contains("songLyrics") {
            let texte = (try? await client.liedtexte(liedID: lied.id)) ?? []
            if let text = texte.first(where: \.synced) ?? texte.first {
                let versatz = TimeInterval(text.offset) / 1000
                let zeilen = text.zeilen.map { z in
                    Liedtext.Zeile(zeit: text.synced ? z.start.map { max(0, TimeInterval($0) / 1000 - versatz) } : nil,
                                   text: z.value)
                }
                let ergebnis = Liedtext(zeilen: zeilen)
                if !ergebnis.istLeer { return ergebnis }
            }
        }
        guard let kuenstler = lied.kuenstler, !kuenstler.isEmpty,
              let alt = try await client.liedtext(kuenstler: kuenstler, titel: lied.titel)
        else { return nil }
        let ergebnis = Liedtext.lrc(alt.value)
        return ergebnis.istLeer ? nil : ergebnis
    }

    private func erweiterungen() async -> Set<String> {
        if let da = merker.erweiterungen() { return da }
        let namen = Set(((try? await client.erweiterungen()) ?? []).map(\.name))
        merker.setzeErweiterungen(namen)
        return namen
    }

    public func favorit(_ ziel: Favoritziel, an: Bool) async throws {
        switch ziel {
        case let .lied(id): try await client.stern(.lied(id), an: an)
        case let .album(id): try await client.stern(.album(id), an: an)
        case let .kuenstler(id): try await client.stern(.kuenstler(id), an: an)
        case .playlist: return
        }
        merker.kuenstlerVergessen()
    }

    // MARK: - Wiedergabe

    public func abspielweg(_ lied: Lied, sitzung: String, hoechstens: Int?) -> Abspielweg? {
        guard let ziel = Abspielregel.umwandlung(fuer: lied.format, hoechstens: hoechstens) else {
            guard let url = client.streamAdresse(id: lied.id, format: "raw") else { return nil }
            return Abspielweg(adresse: url, mime: mime(lied), art: .direkt, format: lied.format)
        }
        return umgewandelt(lied, ziel: ziel)
    }

    public func ladeweg(_ lied: Lied) -> Abspielweg? {
        if Abspielregel.kannDirekt(lied.format) {
            guard let url = client.downloadAdresse(id: lied.id) else { return nil }
            return Abspielweg(adresse: url, mime: mime(lied), art: .direkt, format: lied.format)
        }
        return umgewandelt(lied)
    }

    /// **Nur mit Token.** Im Rückfall auf `p=enc:` stünde das Passwort,
    /// bloß hex-kodiert, in der Adresse — und die zeigt die Sonos-App jedem.
    public func sonosweg(_ lied: Lied) -> Abspielweg? {
        guard sonosMoeglich else { return nil }
        guard let ziel = Sonosregel.umwandlung(fuer: lied.format) else {
            guard let url = client.streamAdresse(id: lied.id, format: "raw") else { return nil }
            return Abspielweg(adresse: url, mime: mime(lied), art: .direkt, format: lied.format)
        }
        return umgewandelt(lied, ziel: ziel)
    }

    public var sonosMoeglich: Bool { client.weise == .token }

    private func umgewandelt(_ lied: Lied, ziel: Umwandlung = Abspielregel.umwandlung(fuer: .subsonic)) -> Abspielweg? {
        guard let url = client.streamAdresse(id: lied.id, format: ziel.codec, hoechstBitrate: ziel.bitrate,
                                             laengeSchaetzen: true) else { return nil }
        return Abspielweg(adresse: url, mime: "audio/mpeg", art: .umgewandelt, format: lied.format,
                          umwandlung: ziel)
    }

    private func mime(_ lied: Lied) -> String? {
        if let m = lied.format?.mime, m.hasPrefix("audio/") { return m }
        return Abspielregel.mime(fuer: lied.format?.behaelter)
    }

    public func melde(_ meldung: Wiedergabemeldung) async {
        switch meldung {
        case let .beginn(stand):
            try? await client.scrobble(id: stand.lied.id, abgeschlossen: false)
        case let .gehoert(lied, beginn):
            try? await client.scrobble(id: lied.id, zeit: beginn, abgeschlossen: true)
        case .fortschritt, .ende:
            return
        }
    }

    public func scrobbeln(_ lied: Lied, beginn: Date, nachtraeglich: Bool) async throws {
        try await client.scrobble(id: lied.id, zeit: beginn, abgeschlossen: true)
    }

    // MARK: - Bilder

    public func bildadresse(_ bild: Bildbezug, kante: Int) -> URL? {
        client.coverAdresse(id: bild.id, groesse: kante)
    }

    public func heldbildadresse(_ bild: Bildbezug, breite: Int) -> URL? {
        client.coverAdresse(id: bild.id, groesse: breite)
    }

    public func profilbildadresse(kante: Int) -> URL? {
        client.avatarAdresse()
    }

    public func abmelden() async {}

    /// `ping` mit dem gespeicherten Zugang — Subsonic hat kein Merkmal, das
    /// verfällt, aber ein Passwort, das sich ändert.
    public func anmeldungPruefen() async -> Anmeldestand {
        do {
            try await client.ping()
            return .gilt
        } catch {
            return Anmeldestand.aus(fehler: error)
        }
    }
}

/// Was sich die Quelle kurz merkt, hinter einem Schloss.
private final class Merker: @unchecked Sendable {
    private let schloss = NSLock()
    private var _kuenstler: (zeit: Date, liste: [SubsonicKuenstler])?
    private var _playlists: (zeit: Date, liste: [SubsonicPlaylist])?
    private var _erweiterungen: Set<String>?

    func kuenstler() -> (zeit: Date, liste: [SubsonicKuenstler])? {
        schloss.lock(); defer { schloss.unlock() }
        return _kuenstler
    }

    func setzeKuenstler(_ liste: [SubsonicKuenstler]) {
        schloss.lock(); defer { schloss.unlock() }
        _kuenstler = (Date(), liste)
    }

    func kuenstlerVergessen() {
        schloss.lock(); defer { schloss.unlock() }
        _kuenstler = nil
    }

    func playlists() -> (zeit: Date, liste: [SubsonicPlaylist])? {
        schloss.lock(); defer { schloss.unlock() }
        return _playlists
    }

    func setzePlaylists(_ liste: [SubsonicPlaylist]) {
        schloss.lock(); defer { schloss.unlock() }
        _playlists = (Date(), liste)
    }

    func erweiterungen() -> Set<String>? {
        schloss.lock(); defer { schloss.unlock() }
        return _erweiterungen
    }

    func setzeErweiterungen(_ namen: Set<String>) {
        schloss.lock(); defer { schloss.unlock() }
        _erweiterungen = namen
    }
}
