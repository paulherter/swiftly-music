import Foundation
import JellyfinKit
import Testing
@testable import MusikKit
import SubsonicKit

// .serialized: die Jellyfin-Attrappe hat eine gemeinsame Zuordnung.
@Suite("Jellyfin als Quelle", .serialized)
struct JellyfinQuelleTests {

    @Test("Album mit Liedern: Format, Hülle, Favorit, kaputte Einträge fallen einzeln heraus")
    func album() async throws {
        let quelle = await Jellyfinstelle.quelle([
            "/Items/al1": "jf_album",
            "/Items?Audio&ParentId=al1": "jf_album_lieder",
        ])
        let detail = try await quelle.album("al1")
        #expect(detail.album.titel == "Nachtfahrt")
        #expect(detail.album.kuenstler == "Lina Brenner")
        #expect(detail.album.kuenstlerID == "ar1")
        #expect(detail.album.jahr == 2024)
        #expect(detail.album.genres == ["Synth-Pop"])
        #expect(detail.album.liedzahl == 10)
        #expect(detail.album.dauer == 2460)
        #expect(detail.album.favorit)
        #expect(detail.album.bild == Bildbezug(id: "al1", marke: "tagAl1"))

        // Der vierte Eintrag hat keine Kennung, der dritte eine kaputte Laufzeit.
        #expect(detail.lieder.map(\.id) == ["l1", "l2", "l3"])
        let erstes = detail.lieder[0]
        #expect(erstes.format == Tonformat(codec: "flac", behaelter: "flac", bitrate: 2400, bitTiefe: 24,
                                           abtastrate: 96000, kanaele: 2))
        #expect(erstes.bild == Bildbezug(id: "al1", marke: "tagAl1"))
        #expect(erstes.dauer == 192)
        #expect(erstes.gespielt == 3)
        #expect(Abspielregel.formatangabe(erstes.format, locale: Locale(identifier: "de_DE")) == "FLAC 24/96")
        // Die MP4-Liste wird zur Endung, nicht zu „mov".
        #expect(detail.lieder[1].format?.behaelter == "m4a")
        #expect(detail.lieder[1].kuenstler == "Lina Brenner, Gast")
        #expect(detail.lieder[1].hatLiedtext == true)
        #expect(detail.lieder[2].dauer == nil)
        #expect(!Abspielregel.kannDirekt(detail.lieder[2].format))

        // Jede Anfrage trägt den Benutzer.
        #expect(Jellyfinstelle.anfragen.allSatisfy { Jellyfinstelle.werte($0)["userId"] == "u1" })
    }

    @Test("Direkt: die Datei mit Endung, static und ApiKey")
    func abspielwegDirekt() throws {
        let quelle = JellyfinQuelle(
            client: JellyfinClient(baseURL: URL(string: "https://musik.example.de")!, deviceID: "g",
                                   deviceName: "iPhone", programm: "Swiftly Music"),
            sitzung: Session(accessToken: "tok", userID: "u1", userName: "n",
                             serverURL: URL(string: "https://musik.example.de")!),
            geraeteID: "g")
        let flac = Lied(id: "l1", titel: "", format: Tonformat(codec: "flac", behaelter: "flac"), quellID: "q1")
        let weg = try #require(quelle.abspielweg(flac, sitzung: "s-1"))
        #expect(weg.art == .direkt)
        #expect(weg.adresse.path == "/Audio/l1/stream.flac")
        let w = werte(weg.adresse)
        #expect(w["static"] == "true")
        #expect(w["ApiKey"] == "tok")
        #expect(w["api_key"] == nil)
        #expect(w["mediaSourceId"] == "q1")
        #expect(w["playSessionId"] == "s-1")
        #expect(w["deviceId"] == "g")
        #expect(weg.mime == "audio/flac")
        #expect(weg.sitzung == "s-1")

        let ogg = Lied(id: "l3", titel: "", format: Tonformat(codec: "vorbis", behaelter: "ogg"))
        let um = try #require(quelle.abspielweg(ogg, sitzung: "s-2"))
        #expect(um.art == .umgewandelt)
        #expect(um.adresse.path == "/Audio/l3/stream.mp3")
        #expect(werte(um.adresse)["audioCodec"] == "mp3")
        #expect(werte(um.adresse)["audioBitRate"] == "320000")
        #expect(werte(um.adresse)["static"] == "false")
        #expect(um.mime == "audio/mpeg")

        // Zum Laden ohne Wiedergabekennung.
        let laden = try #require(quelle.ladeweg(flac))
        #expect(werte(laden.adresse)["playSessionId"] == nil)

        // Mit Höchstrate wird auch FLAC umgewandelt, in der Rate der Grenze.
        let knapp = try #require(quelle.abspielweg(flac, sitzung: "s-3", hoechstens: 128))
        #expect(knapp.art == .umgewandelt)
        #expect(werte(knapp.adresse)["audioBitRate"] == "128000")
    }

    @Test("Liedtext: nach Zeit geordnet, 404 heißt keiner")
    func liedtext() async throws {
        let quelle = await Jellyfinstelle.quelle(["/Audio/l2/Lyrics": "jf_lyrics"])
        let text = try #require(try await quelle.liedtext(Lied(id: "l2", titel: "")))
        #expect(text.getaktet)
        #expect(text.zeilen.map(\.zeit) == [0, 4.2, 8, 9.05])
        #expect(text.zeilen[2].istPause)
        #expect(try await quelle.liedtext(Lied(id: "gibtsnicht", titel: "")) == nil)
    }

    /// Jellyfin 12: `Start` in Ticks (10⁷ je Sekunde) — ohne `Start` ist der
    /// Text ungetaktet, und steht an jeder Zeile dieselbe Zeit, ebenso.
    @Test("Liedtext ungetaktet: ohne Start, oder überall 0")
    func liedtextUngetaktet() async throws {
        let quelle = await Jellyfinstelle.quelle(["/Audio/u1/Lyrics": "jf_lyrics_ungetaktet",
                                                  "/Audio/u2/Lyrics": "jf_lyrics_nullzeiten"])
        let ohne = try #require(try await quelle.liedtext(Lied(id: "u1", titel: "")))
        #expect(!ohne.getaktet)
        #expect(ohne.zeilen.count == 4)
        #expect(ohne.aktuelleZeile(zu: 30) == nil)
        let null = try #require(try await quelle.liedtext(Lied(id: "u2", titel: "")))
        #expect(!null.getaktet)
        #expect(null.zeilen.map(\.text).first == "Die Stadt geht aus, Laterne für Laterne")
    }

    /// Jellyfin zählt am Lied — die Alben kommen aus den zuletzt gehörten
    /// Liedern, in deren Reihenfolge, jedes einmal.
    @Test("Zuletzt gehörte Alben aus den Liedern, Reihenfolge wie gehört")
    func zuletztGehoert() async throws {
        let quelle = await Jellyfinstelle.quelle([
            "/Items?Audio": "jf_zuletzt_lieder",
            "/Items?Ids": "jf_alben_ids",
        ])
        let alben = try await quelle.alben(Listenanfrage(sortierung: .zuletztGehoert, anzahl: 8)).eintraege
        #expect(alben.map(\.id) == ["alB", "alA", "alC"])
        #expect(alben[0].zuletztGespielt == Zeitangabe.lesen("2026-09-23T10:00:00Z"))
        let lieder = try #require(Jellyfinstelle.anfragen.first { Jellyfinstelle.werte($0)["IncludeItemTypes"] == "Audio" })
        #expect(Jellyfinstelle.werte(lieder)["SortBy"] == "DatePlayed")
        #expect(Jellyfinstelle.werte(lieder)["Filters"] == "IsPlayed")
    }

    /// Für „Zuletzt gehört" zählt ein Album erst, wenn mindestens die Hälfte
    /// seiner Lieder gespielt wurde — gezählt an denselben Liedern, ohne
    /// weitere Anfrage.
    @Test("Zuletzt gehört: nur Alben, von denen die Hälfte gespielt wurde")
    func zuletztGehoertHaelfte() async throws {
        let quelle = await Jellyfinstelle.quelle([
            "/Items?Audio": "jf_zuletzt_lieder",
            "/Items?Ids": "jf_alben_ids_liedzahl",
        ])
        // alB: 2 von 4, alA: 1 von 4, alC: 1 von 1.
        let alben = try await quelle.zuletztGehoert(anzahl: 8)
        #expect(alben.map(\.id) == ["alB", "alC"])
        #expect(Jellyfinstelle.anfragen.count == 2)
    }

    @Test("Hörbücher: ein Ordner mit Teilen ist ein Buch, ein Ordner mit Einzeldateien sind viele")
    func hoerbuecher() async throws {
        let quelle = await Jellyfinstelle.quelle([
            "/Items?AudioBook": "jf_hoerbuecher",
            "/Items?AudioBook&ParentId=ordnerSand": "jf_hoerbuch_sand",
        ])
        let buecher = try await quelle.hoerbuecher()
        #expect(buecher.map(\.titel) == ["Der Sandmann", "Effi Briest", "Der Schimmelreiter"])
        #expect(buecher[0].id == "ordner:ordnerSand")
        #expect(buecher[0].teilzahl == 2)
        #expect(buecher[0].dauer == 1200)
        #expect(buecher[0].autor == "E. T. A. Hoffmann")
        #expect(buecher[1].id == "teil:h3")
        #expect(buecher[2].bild == Bildbezug(id: "h4", marke: "t4"))
        // Ohne eigenes Bild: das Bild des Ordners.
        #expect(buecher[1].bild == Bildbezug(id: "ordnerViele"))

        let detail = try await quelle.hoerbuch("ordner:ordnerSand")
        #expect(detail.hoerbuch.id == "ordner:ordnerSand")
        #expect(detail.teile.map(\.id) == ["h1", "h2"])
        // Die gemerkte Stelle kommt mit.
        #expect(detail.teile[0].fortsetzen == 120)
        #expect(detail.teile[0].istHoerbuch)
    }

    @Test("Die Meldung trägt Jellyfins Feldnamen und die Art der Wiedergabe")
    func meldung() throws {
        let stand = Wiedergabestand(lied: Lied(id: "l1", titel: "", quellID: "q1"), position: 98.4,
                                    pausiert: true, art: .umgewandelt, sitzung: "s-1", gemischt: true)
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(JellyfinQuelle.Meldekoerper(stand, ereignis: "pause"))) as? [String: Any]
        #expect(json?["ItemId"] as? String == "l1")
        #expect(json?["MediaSourceId"] as? String == "q1")
        #expect(json?["PlaySessionId"] as? String == "s-1")
        #expect(json?["PositionTicks"] as? Int64 == 984_000_000)
        #expect(json?["IsPaused"] as? Bool == true)
        #expect(json?["CanSeek"] as? Bool == true)
        #expect(json?["PlayMethod"] as? String == "Transcode")
        #expect(json?["PlaybackOrder"] as? String == "Shuffle")
        let ende = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(JellyfinQuelle.Endekoerper(stand))) as? [String: Any]
        #expect(ende?["PositionTicks"] as? Int64 == 984_000_000)
        #expect(ende?["IsPaused"] == nil)
    }

    @Test("Der Behälter nach Endung, sonst aus Jellyfins Liste")
    func behaelter() {
        #expect(JellyfinQuelle.behaelter(pfad: "/m/a.FLAC", container: "flac") == "flac")
        #expect(JellyfinQuelle.behaelter(pfad: nil, container: "mov,mp4,m4a,3gp,3g2,mj2") == "m4a")
        #expect(JellyfinQuelle.behaelter(pfad: "/m/ohne-endung", container: "ogg") == "ogg")
        #expect(JellyfinQuelle.behaelter(pfad: nil, container: nil) == nil)
    }

    private func werte(_ url: URL) -> [String: String] {
        var d: [String: String] = [:]
        for w in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            d[w.name] = w.value ?? ""
        }
        return d
    }
}

@Suite("Subsonic als Quelle")
struct SubsonicQuelleTests {

    @Test("Album: Format aus Endung, Favorit aus dem Stern")
    func album() async throws {
        let stelle = Subsonicstelle(["getAlbum": ["ss_getAlbum"]])
        let detail = try await stelle.quelle().album("4QZO6nBGty9odiq7pUok5n")
        #expect(detail.album.titel == "Love (All I Was Able To Say)")
        #expect(detail.lieder.count == 2)
        let l = detail.lieder[0]
        #expect(l.format?.codec == "mp3")
        #expect(l.format?.behaelter == "mp3")
        #expect(l.format?.mime == "audio/mpeg")
        #expect(l.dauer == 189)
        #expect(l.bild?.id.hasPrefix("mf-") == true)
    }

    @Test("Eine .m4a mit Bittiefe ist ALAC")
    func alac() {
        #expect(SubsonicQuelle.codec(endung: "m4a", bitTiefe: 24) == "alac")
        #expect(SubsonicQuelle.codec(endung: "m4a", bitTiefe: nil) == "aac")
        #expect(SubsonicQuelle.codec(endung: "ogg", bitTiefe: nil) == "vorbis")
    }

    @Test("Favoriten mit Veröffentlichungsart")
    func favoriten() async throws {
        let stelle = Subsonicstelle(["getStarred2": ["ss_getStarred2"]])
        let seite = try await stelle.quelle().lieder(Listenanfrage(sortierung: .name,
                                                                   filter: Serverfilter(nurFavoriten: true)))
        #expect(seite.eintraege.map(\.id) == ["l1"])
        #expect(seite.eintraege[0].favorit)
        #expect(Abspielregel.formatangabe(seite.eintraege[0].format, locale: Locale(identifier: "de_DE")) == "FLAC 24/96")
        #expect(SubsonicQuelle.albumart(["EP"], zusammenstellung: false) == .ep)
        #expect(SubsonicQuelle.albumart([], zusammenstellung: true) == .zusammenstellung)
    }

    @Test("Liedtext getaktet, mit Versatz — der Server kennt songLyrics")
    func liedtext() async throws {
        let stelle = Subsonicstelle([
            "getOpenSubsonicExtensions": ["ss_getOpenSubsonicExtensions"],
            "getLyricsBySongId": ["ss_getLyricsBySongId"],
        ])
        let text = try #require(try await stelle.quelle().liedtext(
            Lied(id: "x", titel: "Nachtfahrt", kuenstler: "Lina Brenner")))
        #expect(text.getaktet)
        // offset −100 heißt: 0,1 s später.
        #expect(text.zeilen.map(\.zeit) == [0.1, 4.3, 9.15, 13.9])
        // Die aktuelle Zeile folgt der Zeit: bei 5 s die zweite.
        #expect(text.aktuelleZeile(zu: 5) == 1)
    }

    @Test("Liedtext ungetaktet über songLyrics: synced false")
    func liedtextUngetaktet() async throws {
        let stelle = Subsonicstelle([
            "getOpenSubsonicExtensions": ["ss_getOpenSubsonicExtensions"],
            "getLyricsBySongId": ["ss_getLyricsBySongId_ungetaktet"],
        ])
        let text = try #require(try await stelle.quelle().liedtext(
            Lied(id: "x", titel: "Nachtfahrt", kuenstler: "Lina Brenner")))
        #expect(!text.getaktet)
        #expect(text.zeilen.count == 3)
    }

    /// Ohne Last.fm liefert Navidrome keine ähnlichen Lieder; dann mischt der
    /// Mix die Lieder des Künstlers.
    @Test("Sofortmix: ähnliche Lieder, sonst Zufall aus dem Künstler")
    func sofortmix() async throws {
        let mitAehnlichen = Subsonicstelle(["getSimilarSongs2": ["ss_getSimilarSongs2"]])
        let a = try await mitAehnlichen.quelle().sofortmix(.kuenstler(id: "04HrSORpypcLGNUdQp37gn", name: "x"),
                                                            anzahl: 50)
        #expect(a.count == 2)

        let ohne = Subsonicstelle([
            "getSimilarSongs2": ["ss_getSimilarSongs2_leer"],
            "getArtist": ["ss_getArtist"],
            "getAlbum": ["ss_getAlbum", "ss_getAlbum"],
        ])
        let b = try await ohne.quelle().sofortmix(.kuenstler(id: "04HrSORpypcLGNUdQp37gn", name: "x"),
                                                   anzahl: 50)
        // Zwei Alben mit denselben zwei Liedern: ohne Doppelte.
        #expect(Set(b.map(\.id)).count == b.count)
        #expect(b.count == 2)
        #expect(ohne.endpunkte.contains("getArtist"))
    }

    @Test("Alle Lieder eines Künstlers: Album für Album, das neueste zuerst")
    func alleLieder() async throws {
        let stelle = Subsonicstelle([
            "getArtist": ["ss_getArtist"],
            "getAlbum": ["ss_getAlbum", "ss_getAlbum"],
        ])
        let lieder = try await stelle.quelle().alleLieder(von: Kuenstler(id: "04HrSORpypcLGNUdQp37gn", name: "x"))
        // Zwei Alben, je zwei Lieder aus der Datei.
        #expect(lieder.count == 4)
        #expect(lieder.map(\.nummer) == [1, 2, 1, 2])
    }

    @Test("Abspielweg: roh oder MP3, mit Medientyp")
    func abspielweg() throws {
        let quelle = Subsonicstelle([:]).quelle()
        let mp3 = Lied(id: "a", titel: "", format: Tonformat(codec: "mp3", behaelter: "mp3", mime: "audio/mpeg"))
        let direkt = try #require(quelle.abspielweg(mp3, sitzung: "s"))
        #expect(direkt.art == .direkt)
        #expect(direkt.adresse.absoluteString.contains("format=raw"))
        #expect(direkt.mime == "audio/mpeg")
        #expect(direkt.sitzung == nil)
        let ogg = Lied(id: "b", titel: "", format: Tonformat(codec: "vorbis", behaelter: "ogg"))
        let um = try #require(quelle.abspielweg(ogg, sitzung: "s"))
        #expect(um.art == .umgewandelt)
        #expect(um.adresse.absoluteString.contains("format=mp3"))
        #expect(um.adresse.absoluteString.contains("maxBitRate=320"))
        #expect(quelle.ladeweg(mp3)?.adresse.lastPathComponent == "download.view")
    }

    @Test("Ungehört sortiert selbst aus und zählt beim Server weiter")
    func ungehoert() async throws {
        let stelle = Subsonicstelle(["getAlbumList2": ["ss_getAlbumList2"]])
        let seite = try await stelle.quelle().alben(Listenanfrage(sortierung: .name,
                                                                  filter: Serverfilter(nurUngehoert: true),
                                                                  anzahl: 10))
        // Beide Alben im Beispiel wurden schon gehört.
        #expect(seite.eintraege.isEmpty)
        #expect(seite.weiterAb == nil)
    }
}
