import Foundation
import Testing
@testable import SubsonicKit

@Suite("Antworten lesen")
struct EndpunkteTests {

    @Test("getArtists: alle Abschnitte in einer Liste, Stern als Datum")
    func kuenstlerliste() async throws {
        let kuenstler = try await Attrappe().client().alleKuenstler()
        #expect(kuenstler.count == 3)
        #expect(kuenstler.map(\.name) == ["2 Mello", "Back On Earth", "Binaerpilot"])
        #expect(kuenstler[0].starred != nil)
        #expect(kuenstler[1].albumCount == 3)
        #expect(kuenstler[1].coverArt?.hasPrefix("ar-") == true)
    }

    /// Ältere Server schreiben Kennungen als Zahl, Zahlen als Text, und
    /// einen einzelnen Eintrag als Objekt statt als Liste.
    @Test("Kennungen als Zahl, Zahlen als Text, ein Eintrag ohne Liste")
    func nachsichtig() async throws {
        let attrappe = Attrappe(["getArtists": ["getArtists_zahlen"]])
        let kuenstler = try await attrappe.client().alleKuenstler()
        #expect(kuenstler.map(\.id) == ["123", "b1"])
        #expect(kuenstler[0].albumCount == 3)
        // Ohne Zone gilt UTC.
        #expect(kuenstler[0].starred == Zeitangabe.lesen("2013-11-02T12:30:00Z"))
    }

    @Test("getArtist: Künstler mit Alben")
    func kuenstler() async throws {
        let wert = try await Attrappe().client().kuenstler(id: "04HrSORpypcLGNUdQp37gn")
        #expect(wert.kuenstler.name == "Back On Earth")
        #expect(wert.alben.count == 2)
        #expect(wert.alben.allSatisfy { $0.artistId == "04HrSORpypcLGNUdQp37gn" })
    }

    @Test("getAlbumList2: Alben mit Zählung und Datum")
    func albumliste() async throws {
        let attrappe = Attrappe()
        let alben = try await attrappe.client().albumliste(.neueste, anzahl: 2)
        #expect(alben.count == 2)
        let erstes = try #require(alben.first)
        #expect(erstes.songCount == 11)
        #expect(erstes.duration == 2954)
        #expect(erstes.year == 2013)
        #expect(erstes.isCompilation == true)
        #expect(erstes.kuenstlerzeile == "Various Artists")
        #expect(erstes.created != nil)
        let w = attrappe.werte(0)
        #expect(w["type"] == "newest")
        #expect(w["size"] == "2")
        #expect(w["offset"] == "0")
    }

    @Test("getAlbumList2 nach Jahr trägt beide Grenzen")
    func albumlisteNachJahr() async throws {
        let attrappe = Attrappe(["getAlbumList2": ["getAlbumList2"]])
        _ = try await attrappe.client().albumliste(.nachJahr(von: 2030, bis: 0), anzahl: 900)
        let w = attrappe.werte(0)
        #expect(w["type"] == "byYear")
        #expect(w["fromYear"] == "2030")
        #expect(w["toYear"] == "0")
        // Mehr als 500 gibt die Schnittstelle nicht her.
        #expect(w["size"] == "500")
    }

    @Test("getAlbum: Lieder mit Format, Tiefe 0 heißt unbekannt")
    func album() async throws {
        let album = try await Attrappe().client().album(id: "4QZO6nBGty9odiq7pUok5n")
        #expect(album.lieder.count == 2)
        let lied = try #require(album.lieder.first)
        #expect(lied.title == "Love")
        #expect(lied.suffix == "mp3")
        #expect(lied.contentType == "audio/mpeg")
        #expect(lied.samplingRate == 44100)
        #expect(lied.bitDepth == nil)
        #expect(lied.bitRate == 188)
        #expect(lied.duration == 189)
        #expect(lied.track == 1)
        #expect(lied.albumId == "4QZO6nBGty9odiq7pUok5n")
    }

    @Test("getAlbum mit unbekannter Kennung meldet 70")
    func albumFehlt() async throws {
        let attrappe = Attrappe(["getAlbum": ["fehler70"]])
        do {
            _ = try await attrappe.client().album(id: "gibtsnicht")
            Issue.record("hätte werfen müssen")
        } catch let fehler as SubsonicFehler {
            #expect(fehler.istNichtGefunden)
        }
    }

    @Test("getPlaylists und getPlaylist")
    func playlists() async throws {
        let client = Attrappe().client()
        let liste = try await client.playlists()
        #expect(liste.count == 2)
        #expect(liste[0].songCount == 11)
        #expect(liste[1].isPublic == true)
        let eine = try await client.playlist(id: "0NYKm1AySipSUAG3ysi6ap")
        #expect(eine.name == "Ashlizzlle")
        #expect(eine.lieder.count == 2)
    }

    @Test("search3: Künstler, Alben und Lieder getrennt")
    func suche() async throws {
        let attrappe = Attrappe()
        let treffer = try await attrappe.client().suche("back", kuenstler: 2, alben: 2, lieder: 2)
        #expect(treffer.kuenstler.count == 1)
        #expect(treffer.alben.count == 1)
        #expect(treffer.lieder.count == 2)
        let w = attrappe.werte(0)
        #expect(w["query"] == "back")
        #expect(w["artistCount"] == "2")
    }

    @Test("getRandomSongs, getSimilarSongs2 und eine leere getTopSongs")
    func liederlisten() async throws {
        let attrappe = Attrappe(["getTopSongs": ["getTopSongs_leer"]])
        let client = attrappe.client()
        #expect(try await client.zufallslieder(anzahl: 2).count == 2)
        #expect(try await client.aehnlicheLieder(kuenstlerID: "04HrSORpypcLGNUdQp37gn").count == 2)
        #expect(try await client.topLieder(kuenstler: "Back On Earth").isEmpty)
    }

    @Test("getStarred2: Künstler, Alben und Lieder mit Stern, Veröffentlichungsart")
    func favoriten() async throws {
        let f = try await Attrappe().client().favoriten()
        #expect(f.kuenstler.map(\.id) == ["ar1"])
        #expect(f.alben.map(\.id) == ["al1", "al2"])
        #expect(f.alben[1].releaseTypes == ["EP"])
        let lied = try #require(f.lieder.first)
        #expect(lied.bitDepth == 24)
        #expect(lied.samplingRate == 96000)
        #expect(lied.starred != nil)
    }

    @Test("Mit leerem Begriff blättert die Suche über die Versätze")
    func sucheSeitenweise() async throws {
        let attrappe = Attrappe(["search3": ["search3"]])
        _ = try await attrappe.client().suche("", kuenstler: 0, alben: 0, lieder: 100, liederAb: 200)
        let w = attrappe.werte(0)
        #expect(w["query"] == "")
        #expect(w["songOffset"] == "200")
        #expect(w["albumOffset"] == nil)
    }

    @Test("getLyricsBySongId: getaktet, mit Versatz und Sprache")
    func liedtexte() async throws {
        let texte = try await Attrappe().client().liedtexte(liedID: "x")
        #expect(texte.count == 2)
        let getaktet = try #require(texte.first { $0.synced })
        #expect(getaktet.offset == -100)
        #expect(getaktet.lang == "deu")
        #expect(getaktet.zeilen.map(\.start) == [0, 4200, 9050, 13800])
        #expect(getaktet.zeilen[2].value == "Halt nicht an, die Straße kennt den Weg")
        let ungetaktet = try #require(texte.first { !$0.synced })
        #expect(ungetaktet.zeilen.allSatisfy { $0.start == nil })
    }

    @Test("Leere Liedtexte sind keine Störung")
    func liedtexteLeer() async throws {
        let attrappe = Attrappe(["getLyricsBySongId": ["getLyricsBySongId_leer"],
                                 "getLyrics": ["getLyrics_leer"]])
        let client = attrappe.client()
        #expect(try await client.liedtexte(liedID: "x").isEmpty)
        #expect(try await client.liedtext(kuenstler: "a", titel: "b") == nil)
    }

    @Test("getLyrics: der Text mit Zeilenumbrüchen")
    func einfacherLiedtext() async throws {
        let text = try await Attrappe().client().liedtext(kuenstler: "Lina Brenner", titel: "Nachtfahrt")
        #expect(text?.value.split(separator: "\n", omittingEmptySubsequences: false).count == 4)
    }

    @Test("OpenSubsonic-Erweiterungen")
    func erweiterungen() async throws {
        let liste = try await Attrappe().client().erweiterungen()
        #expect(liste.contains { $0.name == "songLyrics" && $0.versions.contains(1) })
    }

    @Test("Ein Server ohne OpenSubsonic hat keine Erweiterungen")
    func keineErweiterungen() async throws {
        let attrappe = Attrappe(["getOpenSubsonicExtensions": ["fehler70"]])
        #expect(try await attrappe.client().erweiterungen().isEmpty)
    }

    @Test("Stern und Scrobble schicken das Richtige")
    func sternUndScrobble() async throws {
        let attrappe = Attrappe(["star": ["ping"], "unstar": ["ping"], "scrobble": ["ping"]])
        let client = attrappe.client()
        try await client.stern(.album("al1"), an: true)
        try await client.stern(.lied("l1"), an: false)
        try await client.scrobble(id: "l1", zeit: Date(timeIntervalSince1970: 1_700_000_000),
                                  abgeschlossen: true)
        #expect(attrappe.anfragen[0].url?.lastPathComponent == "star.view")
        #expect(attrappe.werte(0)["albumId"] == "al1")
        #expect(attrappe.anfragen[1].url?.lastPathComponent == "unstar.view")
        #expect(attrappe.werte(1)["id"] == "l1")
        #expect(attrappe.werte(2)["submission"] == "true")
        #expect(attrappe.werte(2)["time"] == "1700000000000")
    }

    @Test("Abspieladressen: roh oder umgewandelt mit geschätzter Länge")
    func stromadressen() throws {
        let client = Attrappe().client()
        let roh = try #require(client.streamAdresse(id: "l1", format: "raw"))
        let rohWerte = werte(roh)
        #expect(rohWerte["format"] == "raw")
        #expect(rohWerte["f"] == nil)
        #expect(roh.lastPathComponent == "stream.view")
        let mp3 = try #require(client.streamAdresse(id: "l1", format: "mp3", hoechstBitrate: 320,
                                                    laengeSchaetzen: true))
        let mp3Werte = werte(mp3)
        #expect(mp3Werte["maxBitRate"] == "320")
        #expect(mp3Werte["estimateContentLength"] == "true")
        #expect(client.downloadAdresse(id: "l1")?.lastPathComponent == "download.view")
        #expect(werte(try #require(client.avatarAdresse()))["username"] == "demo")
    }

    /// Dieselbe Hülle heißt innerhalb einer Sitzung immer gleich — sonst
    /// träfe kein Bildspeicher.
    @Test("Hüllenadressen sind innerhalb einer Sitzung stabil")
    func stabileAdressen() {
        let client = Attrappe().client()
        #expect(client.coverAdresse(id: "a", groesse: 300) == client.coverAdresse(id: "a", groesse: 300))
    }

    private func werte(_ url: URL) -> [String: String] {
        var ergebnis: [String: String] = [:]
        for w in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            ergebnis[w.name] = w.value ?? ""
        }
        return ergebnis
    }
}

@Suite("Zeitangaben")
struct ZeitangabeTests {

    private func utc(_ j: Int, _ mo: Int, _ t: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = TimeZone(secondsFromGMT: 0)!
        return k.date(from: DateComponents(year: j, month: mo, day: t, hour: h, minute: mi, second: s))!
    }

    @Test("Nanosekunden wie bei Navidrome")
    func nanosekunden() throws {
        let d = try #require(Zeitangabe.lesen("2026-09-23T09:53:46.606867295Z"))
        #expect(abs(d.timeIntervalSince(utc(2026, 9, 23, 9, 53, 46)) - 0.606867295) < 0.000_01)
    }

    @Test("Millisekunden, keine Nachkommastellen, Zonenversatz")
    func formen() {
        #expect(Zeitangabe.lesen("2024-01-02T03:04:05.123Z")?.timeIntervalSince(utc(2024, 1, 2, 3, 4, 5)) ?? 9 < 0.124)
        #expect(Zeitangabe.lesen("2024-01-02T03:04:05Z") == utc(2024, 1, 2, 3, 4, 5))
        #expect(Zeitangabe.lesen("2024-01-02T05:04:05+02:00") == utc(2024, 1, 2, 3, 4, 5))
        #expect(Zeitangabe.lesen("2024-01-02T01:04:05-0200") == utc(2024, 1, 2, 3, 4, 5))
        #expect(Zeitangabe.lesen("2024-01-02 03:04:05") == utc(2024, 1, 2, 3, 4, 5))
    }

    @Test("Unsinn ergibt nichts")
    func unsinn() {
        #expect(Zeitangabe.lesen("") == nil)
        #expect(Zeitangabe.lesen("gestern") == nil)
        #expect(Zeitangabe.lesen("2024-1-2T03:04:05Z") == nil)
        #expect(Zeitangabe.lesen("2024-01-02T03:04:05Q") == nil)
    }
}

@Suite("Musikordner")
struct MusikordnerTests {
    @Test("getMusicFolders: Kennung als Zahl, Name")
    func liste() async throws {
        let ordner = try await Attrappe().client().musikordnerliste()
        #expect(ordner.map(\.id) == ["1", "2"])
        #expect(ordner.map(\.name) == ["Musik", "Hörspiele"])
    }

    @Test("Gewählt: Listen tragen musicFolderId, einzelne Seiten nicht")
    func filter() async throws {
        let attrappe = Attrappe()
        let client = attrappe.client()
        client.musikordner = "2"
        _ = try await client.albumliste(.neueste)
        _ = try await client.album(id: "x")
        #expect(attrappe.werte(0)["musicFolderId"] == "2")
        #expect(attrappe.werte(1)["musicFolderId"] == nil)
        client.musikordner = nil
        _ = try await client.albumliste(.neueste)
        #expect(attrappe.werte(2)["musicFolderId"] == nil)
    }
}

@Suite("Playlists anlegen")
struct PlaylistAnlegenTests {
    @Test("createPlaylist mit Name und Liedern; ältere Server ohne Rückgabe")
    func anlegen() async throws {
        let attrappe = Attrappe(["createPlaylist": ["ping"]])
        let neu = try await attrappe.client().playlistAnlegen(name: "Sommer", liedIDs: ["a", "b"])
        #expect(neu == nil)
        let url = try #require(attrappe.anfragen.first?.url?.absoluteString)
        #expect(url.contains("createPlaylist"))
        #expect(url.contains("name=Sommer"))
        #expect(url.contains("songId=a&songId=b"))
    }

    @Test("updatePlaylist hängt mit songIdToAdd an")
    func ergaenzen() async throws {
        let attrappe = Attrappe(["updatePlaylist": ["ping"]])
        try await attrappe.client().playlistErgaenzen(id: "p1", liedIDs: ["x", "y"])
        let url = try #require(attrappe.anfragen.first?.url?.absoluteString)
        #expect(url.contains("playlistId=p1"))
        #expect(url.contains("songIdToAdd=x&songIdToAdd=y"))
    }
}

@Suite("Playlists bearbeiten")
struct PlaylistBearbeitenTests {
    @Test("Entfernen nach Stelle, umbenennen, neu schreiben, löschen")
    func bearbeiten() async throws {
        let attrappe = Attrappe(["updatePlaylist": ["ping"], "createPlaylist": ["ping"], "deletePlaylist": ["ping"]])
        let client = attrappe.client()
        try await client.playlistEntfernen(id: "p", stellen: [0, 3])
        try await client.playlistUmbenennen(id: "p", name: "Neu")
        try await client.playlistNeuSchreiben(id: "p", liedIDs: ["b", "a"])
        try await client.playlistLoeschen(id: "p")
        let urls = attrappe.anfragen.compactMap { $0.url?.absoluteString }
        #expect(urls[0].contains("songIndexToRemove=0&songIndexToRemove=3"))
        #expect(urls[1].contains("name=Neu"))
        #expect(urls[2].contains("createPlaylist") && urls[2].contains("playlistId=p&songId=b&songId=a"))
        #expect(urls[3].contains("deletePlaylist") && urls[3].contains("id=p"))
    }
}
