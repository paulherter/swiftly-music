import Foundation
import Testing
@testable import MusikKit

@Suite("Direkt oder umwandeln")
struct AbspielregelTests {

    private let de = Locale(identifier: "de_DE")
    private let en = Locale(identifier: "en_US")

    @Test("Was das iPhone kann, läuft direkt", arguments: [
        Tonformat(codec: "flac", behaelter: "flac"),
        Tonformat(codec: "mp3", behaelter: "mp3"),
        Tonformat(codec: "aac", behaelter: "m4a"),
        Tonformat(codec: "alac", behaelter: "m4a"),
        Tonformat(codec: "pcm_s24le", behaelter: "wav"),
        Tonformat(codec: nil, behaelter: "aiff"),
        Tonformat(codec: nil, behaelter: nil, mime: "audio/flac"),
    ])
    func direkt(_ f: Tonformat) {
        #expect(Abspielregel.kannDirekt(f))
    }

    @Test("Was es nicht kann, wird umgewandelt", arguments: [
        Tonformat(codec: "vorbis", behaelter: "ogg"),
        Tonformat(codec: "opus", behaelter: "opus"),
        Tonformat(codec: "opus", behaelter: "m4a"),
        Tonformat(codec: "wmav2", behaelter: "wma"),
        Tonformat(codec: "ape", behaelter: "ape"),
        Tonformat(codec: nil, behaelter: "dsf"),
        Tonformat(codec: nil, behaelter: nil, mime: "audio/ogg"),
    ])
    func umwandeln(_ f: Tonformat) {
        #expect(!Abspielregel.kannDirekt(f))
    }

    /// Ohne Angaben wird es direkt versucht — eine Umwandlung auf Verdacht
    /// wäre der schlechtere Irrtum.
    @Test("Ohne Angaben: direkt")
    func ohneAngaben() {
        #expect(Abspielregel.kannDirekt(nil))
        #expect(Abspielregel.kannDirekt(Tonformat()))
    }

    @Test("Plakette: verlustfrei mit Tiefe und Rate, verlustbehaftet mit Bitrate")
    func formatangabe() {
        #expect(Abspielregel.formatangabe(Tonformat(codec: "flac", behaelter: "flac", bitTiefe: 24, abtastrate: 96000), locale: de) == "FLAC 24/96")
        #expect(Abspielregel.formatangabe(Tonformat(codec: "flac", bitTiefe: 16, abtastrate: 44100), locale: de) == "FLAC 16/44,1")
        #expect(Abspielregel.formatangabe(Tonformat(codec: "flac", bitTiefe: 16, abtastrate: 44100), locale: en) == "FLAC 16/44.1")
        #expect(Abspielregel.formatangabe(Tonformat(codec: "alac", behaelter: "m4a", bitTiefe: 24, abtastrate: 48000), locale: de) == "ALAC 24/48")
        #expect(Abspielregel.formatangabe(Tonformat(codec: "mp3", bitrate: 320), locale: de) == "MP3 320")
        #expect(Abspielregel.formatangabe(Tonformat(codec: "aac", behaelter: "m4a", bitrate: 256), locale: de) == "AAC 256")
        #expect(Abspielregel.formatangabe(Tonformat(codec: "flac"), locale: de) == "FLAC")
        #expect(Abspielregel.formatangabe(Tonformat(codec: "pcm_s16le", behaelter: "wav", bitTiefe: 16, abtastrate: 44100), locale: en) == "WAV 16/44.1")
        #expect(Abspielregel.formatangabe(Tonformat(codec: nil, behaelter: "m4a", bitrate: 256), locale: de) == "AAC 256")
        #expect(Abspielregel.formatangabe(Tonformat(codec: "vorbis", behaelter: "ogg", bitrate: 192), locale: de) == "Vorbis 192")
        #expect(Abspielregel.formatangabe(nil) == nil)
    }

    @Test("Umgewandelt wird in MP3 mit 320")
    func umwandlung() {
        #expect(Abspielregel.formatangabe(Abspielregel.umwandlung(fuer: .jellyfin)) == "MP3 320")
        #expect(Abspielregel.formatangabe(Abspielregel.umwandlung(fuer: .subsonic)) == "MP3 320")
    }

    @Test("Ein Album: ein Format, mehrere, oder teils umgewandelt")
    func album() {
        let flac = Tonformat(codec: "flac", bitTiefe: 24, abtastrate: 96000)
        let mp3 = Tonformat(codec: "mp3", bitrate: 320)
        let ogg = Tonformat(codec: "vorbis", behaelter: "ogg")
        func l(_ f: Tonformat) -> Lied { Lied(id: UUID().uuidString, titel: "", format: f) }
        #expect(Abspielregel.albumangabe([l(flac), l(flac)], serverart: .jellyfin, locale: de) == .direkt("FLAC 24/96"))
        #expect(Abspielregel.albumangabe([l(flac), l(mp3)], serverart: .jellyfin, locale: de) == .direkt(nil))
        #expect(Abspielregel.albumangabe([l(ogg), l(ogg)], serverart: .subsonic, locale: de) == .umgewandelt("MP3 320"))
        #expect(Abspielregel.albumangabe([l(flac), l(ogg)], serverart: .subsonic, locale: de) == .gemischt)
        #expect(Abspielregel.albumangabe([], serverart: .subsonic) == nil)
    }
}

@Suite("Genauer Zeitzugriff für FLAC")
struct GenauerZugriffTests {

    private func weg(_ adresse: String, art: Abspielart = .direkt, format: Tonformat? = nil,
                     mime: String? = nil) -> Abspielweg {
        Abspielweg(adresse: URL(string: adresse)!, mime: mime, art: art, format: format)
    }

    @Test("FLAC vom Server: nur, wenn es mitten drin anfängt")
    func stream() {
        let w = weg("https://s/Audio/1/stream.flac?static=true", format: Tonformat(codec: "flac", behaelter: "flac"))
        #expect(Abspielregel.genauerZugriff(w, startMitten: true))
        #expect(!Abspielregel.genauerZugriff(w, startMitten: false))
    }

    @Test("FLAC auf dem Gerät: immer")
    func datei() {
        let w = weg("file:///ablage/1.flac")
        #expect(Abspielregel.genauerZugriff(w, startMitten: false))
    }

    @Test("Subsonic ohne Endung: am Format oder Medientyp erkannt")
    func ohneEndung() {
        #expect(Abspielregel.genauerZugriff(weg("https://s/rest/stream.view?id=1",
                                                format: Tonformat(codec: "flac", behaelter: "flac")), startMitten: true))
        #expect(Abspielregel.genauerZugriff(weg("https://s/rest/stream.view?id=1", mime: "audio/x-flac"),
                                            startMitten: true))
    }

    @Test("Nicht bei MP4, MP3, AAC oder umgewandelt")
    func sonstNie() {
        #expect(!Abspielregel.genauerZugriff(weg("https://s/Audio/1/stream.m4a",
                                                 format: Tonformat(codec: "flac", behaelter: "m4a")), startMitten: true))
        #expect(!Abspielregel.genauerZugriff(weg("https://s/Audio/1/stream.mp3"), startMitten: true))
        #expect(!Abspielregel.genauerZugriff(weg("file:///ablage/1.m4a"), startMitten: true))
        #expect(!Abspielregel.genauerZugriff(weg("https://s/Audio/1/stream.mp3", art: .umgewandelt,
                                                 format: Tonformat(codec: "flac", behaelter: "flac")), startMitten: true))
    }
}

@Suite("Wann ein Lied als gehört zählt")
struct ScrobbleTests {

    @Test("Die Hälfte oder vier Minuten, was zuerst kommt")
    func schwelle() {
        #expect(Scrobbleregel.schwelle(dauer: 300) == 150)
        #expect(Scrobbleregel.schwelle(dauer: 600) == 240)
        #expect(Scrobbleregel.schwelle(dauer: nil) == 240)
        #expect(Scrobbleregel.schwelle(dauer: 0) == 240)
        #expect(!Scrobbleregel.erreicht(gehoert: 149, dauer: 300))
        #expect(Scrobbleregel.erreicht(gehoert: 150, dauer: 300))
        #expect(Scrobbleregel.erreicht(gehoert: 240, dauer: 3600))
    }

    /// Wer ans Ende spult, hat das Lied nicht gehört.
    @Test("Gezählt wird die gehörte Zeit, kein Sprung und keine Pause")
    func hoerzeit() {
        var h = Hoerzeit()
        h.messen(0, laeuft: true)
        h.messen(0.5, laeuft: true)
        h.messen(1.0, laeuft: true)
        #expect(h.gehoert == 1.0)
        // Sprung nach vorn zählt nicht.
        h.messen(200, laeuft: true)
        #expect(h.gehoert == 1.0)
        h.messen(200.5, laeuft: true)
        #expect(h.gehoert == 1.5)
        // In der Pause zählt nichts.
        h.messen(201, laeuft: false)
        #expect(h.gehoert == 1.5)
        // Zurückspulen zählt auch nicht, danach geht es weiter.
        h.gesprungen(auf: 10)
        h.messen(10.5, laeuft: true)
        #expect(h.gehoert == 2.0)
    }
}

@Suite("Startseite")
struct StartregelnTests {

    private func tag(_ n: Double) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + n * 86_400) }

    @Test("Merken: vorn, ohne Doppelte, begrenzt")
    func merken() {
        var liste: [Sammlungsverweis] = []
        for i in 0 ..< 45 {
            liste = Zuletztgehoert.merken(Sammlungsverweis(art: .album, kennung: "\(i)", titel: "", zeit: tag(Double(i))), in: liste)
        }
        #expect(liste.count == Zuletztgehoert.gemerkt)
        #expect(liste.first?.kennung == "44")
        liste = Zuletztgehoert.merken(Sammlungsverweis(art: .album, kennung: "30", titel: "", zeit: tag(50)), in: liste)
        #expect(liste.first?.kennung == "30")
        #expect(liste.filter { $0.kennung == "30" }.count == 1)
    }

    @Test("Server nur, solange die eigene Liste leer ist")
    func serverNurBeiLeererListe() {
        let eigene = [
            Sammlungsverweis(art: .kuenstler, kennung: "k1", titel: "Lina", zeit: tag(5)),
            Sammlungsverweis(art: .album, kennung: "a1", titel: "Nachtfahrt", zeit: tag(1)),
        ]
        let server = [
            Sammlungsverweis(art: .album, kennung: "a2", titel: "Kupfer", zeit: tag(3)),
            Sammlungsverweis(art: .album, kennung: "a1", titel: "Nachtfahrt", bild: Bildbezug(id: "b"), zeit: tag(6)),
            Sammlungsverweis(art: .album, kennung: "a3", titel: "ohne Zeit"),
        ]
        // Mit eigenen Einträgen: nur die eigenen, der Server bringt nichts dazu.
        #expect(Zuletztgehoert.liste(eigene: eigene, server: server).map(\.id) == ["kuenstler:k1", "album:a1"])
        // Leer (gerade angemeldet): der Server, nach Zeit, ohne Zeit dahinter.
        let neu = Zuletztgehoert.liste(eigene: [], server: server)
        #expect(neu.map(\.id) == ["album:a1", "album:a2", "album:a3"])
        #expect(neu[0].bild?.id == "b")
        // Eigene Einträge, die nicht zählen, machen die Liste nicht voll.
        let nurHoerbuch = [Sammlungsverweis(art: .hoerbuch, kennung: "h", titel: "", zeit: tag(9))]
        #expect(Zuletztgehoert.liste(eigene: nurHoerbuch, server: server).count == 3)
    }

    @Test("Vom Server gehört: mindestens die Hälfte der Lieder")
    func albumHalbGehoert() {
        #expect(Zuletztgehoert.albumGehoert(gespielt: 6, liedzahl: 12))
        #expect(Zuletztgehoert.albumGehoert(gespielt: 7, liedzahl: 13))
        #expect(!Zuletztgehoert.albumGehoert(gespielt: 6, liedzahl: 13))
        #expect(!Zuletztgehoert.albumGehoert(gespielt: 1, liedzahl: 12))
        #expect(Zuletztgehoert.albumGehoert(gespielt: 1, liedzahl: 1))
        #expect(!Zuletztgehoert.albumGehoert(gespielt: 3, liedzahl: nil))
        #expect(!Zuletztgehoert.albumGehoert(gespielt: 0, liedzahl: 0))
    }

    @Test("Zuletzt gehört: nur Alben, Playlists, Künstler — keine Singles, EPs, Hörbücher")
    func nurSammlungen() {
        #expect(Zuletztgehoert.zaehlt(Sammlungsverweis(art: .album, kennung: "a", titel: "", albumart: .album)))
        #expect(Zuletztgehoert.zaehlt(Sammlungsverweis(art: .album, kennung: "a", titel: "", albumart: .live)))
        #expect(Zuletztgehoert.zaehlt(Sammlungsverweis(art: .playlist, kennung: "p", titel: "")))
        #expect(Zuletztgehoert.zaehlt(Sammlungsverweis(art: .kuenstler, kennung: "k", titel: "")))
        #expect(!Zuletztgehoert.zaehlt(Sammlungsverweis(art: .album, kennung: "s", titel: "", albumart: .single)))
        #expect(!Zuletztgehoert.zaehlt(Sammlungsverweis(art: .album, kennung: "e", titel: "", albumart: .ep)))
        #expect(!Zuletztgehoert.zaehlt(Sammlungsverweis(art: .hoerbuch, kennung: "h", titel: "")))
        // Ohne eigene Angabe zählt, was man sonst über das Album weiß.
        #expect(!Zuletztgehoert.zaehlt(Sammlungsverweis(art: .album, kennung: "x", titel: ""), art: .single))
        #expect(Zuletztgehoert.zaehlt(Sammlungsverweis(art: .album, kennung: "x", titel: "")))
        // Aus einem Album mit einem Lied wird eine Single, die nicht zählt.
        #expect(!Zuletztgehoert.zaehlt(Sammlungsverweis(Album(id: "1", titel: "Kupfer", liedzahl: 1))))
    }

    @Test("Zuletzt gehört: Single wird nicht gemerkt, alte Einträge fallen beim Laden heraus")
    func bereinigen() {
        let alt = [Sammlungsverweis(art: .album, kennung: "a", titel: "")]
        #expect(Zuletztgehoert.merken(Sammlungsverweis(art: .album, kennung: "s", titel: "", albumart: .single),
                                      in: alt).map(\.id) == ["album:a"])
        #expect(Zuletztgehoert.merken(Sammlungsverweis(art: .hoerbuch, kennung: "h", titel: ""),
                                      in: alt).map(\.id) == ["album:a"])
        let gespeichert = [
            Sammlungsverweis(art: .album, kennung: "a", titel: ""),
            Sammlungsverweis(art: .album, kennung: "s", titel: ""),
            Sammlungsverweis(art: .hoerbuch, kennung: "h", titel: ""),
            Sammlungsverweis(art: .album, kennung: "e", titel: "", albumart: .ep),
            Sammlungsverweis(art: .playlist, kennung: "p", titel: ""),
        ]
        let sauber = Zuletztgehoert.bereinigt(gespeichert) { $0.kennung == "s" ? .single : nil }
        #expect(sauber.map(\.id) == ["album:a", "playlist:p"])
    }

    @Test("Zuletzt gehört: Singles vom Server fallen heraus")
    func serverOhneSingles() {
        let liste = Zuletztgehoert.liste(eigene: [], server: [
            Sammlungsverweis(Album(id: "s", titel: "Lied - Single", zuletztGespielt: tag(4))),
            Sammlungsverweis(Album(id: "a", titel: "Kupfer", liedzahl: 11, zuletztGespielt: tag(3))),
            Sammlungsverweis(art: .album, kennung: "e", titel: "", zeit: tag(2)),
        ]) { $0.kennung == "e" ? .ep : nil }
        #expect(liste.map(\.id) == ["album:a"])
    }

    @Test("Künstler und Album mit gleicher Kennung sind zwei Sammlungen")
    func artenGetrennt() {
        let liste = Zuletztgehoert.liste(eigene: [
            Sammlungsverweis(art: .kuenstler, kennung: "x", titel: "", zeit: tag(1)),
            Sammlungsverweis(art: .album, kennung: "x", titel: "", zeit: tag(2)),
        ], server: [])
        #expect(liste.count == 2)
    }

    @Test("NEU: zwei Wochen und nie gehört")
    func neu() {
        let jetzt = tag(20)
        #expect(Neuheit.istNeu(hinzugefuegt: tag(19), gespielt: 0, jetzt: jetzt))
        #expect(Neuheit.istNeu(hinzugefuegt: tag(19), gespielt: nil, jetzt: jetzt))
        #expect(!Neuheit.istNeu(hinzugefuegt: tag(19), gespielt: 1, jetzt: jetzt))
        #expect(!Neuheit.istNeu(hinzugefuegt: tag(5), gespielt: 0, jetzt: jetzt))
        #expect(!Neuheit.istNeu(hinzugefuegt: nil, gespielt: 0, jetzt: jetzt))
    }

    @Test("Mixe: Künstler, Genre, Künstler — ohne Sammelalben, Mosaik mit vier Feldern")
    func mixe() {
        func a(_ id: String, _ k: String?, _ kid: String?, _ g: [String]) -> Album {
            Album(id: id, titel: id, kuenstler: k, kuenstlerID: kid, genres: g, bild: Bildbezug(id: "b\(id)"))
        }
        let alben = [
            a("1", "Lina Brenner", "k1", ["Synth-Pop"]),
            a("2", "Various Artists", "va", ["Jazz"]),
            a("3", "Maren Solvik", "k2", ["Jazz"]),
            a("4", "Lina Brenner", "k1", ["Synth-Pop"]),
            a("5", "Various Artists", "va", ["Jazz"]),
            a("6", "Maren Solvik", "k2", ["Jazz"]),
            a("7", "Oskar Wendt Trio", "k3", ["Jazz"]),
        ]
        let mixe = Mixvorschlaege.bilden(aus: alben)
        #expect(mixe.map(\.name) == ["Lina Brenner", "Jazz", "Maren Solvik"])
        #expect(mixe.allSatisfy { $0.huellen.count == 4 })
        #expect(mixe[0].huellen.map(\.id) == ["b1", "b4", "b1", "b4"])
        #expect(Mixvorschlaege.bilden(aus: []).isEmpty)
    }
}

@Suite("Glut aus der Hülle")
struct HuellentonTests {

    private func bild(_ punkte: [(UInt8, UInt8, UInt8)]) -> [UInt8] {
        punkte.flatMap { [$0.0, $0.1, $0.2, 255] }
    }

    @Test("Eine rote Hülle glüht rot")
    func rot() throws {
        let glut = try #require(Huellenton.glut(rgba: bild(Array(repeating: (200, 30, 40), count: 64))))
        let (h, s, v) = glut.haupt.hsb
        #expect(h < 0.05 || h > 0.95)
        #expect(s >= 0.45 && s <= 0.78)
        #expect(abs(v - 0.78) < 0.01)
        #expect(glut.neben.hsb.helligkeit < glut.haupt.hsb.helligkeit)
    }

    /// Der Mittelwert wäre fast schwarz; gezählt wird aber der Farbton.
    @Test("Wenig Blau auf viel Schwarz glüht blau")
    func blauAufSchwarz() throws {
        let punkte = Array(repeating: (UInt8(5), UInt8(5), UInt8(5)), count: 90)
            + Array(repeating: (UInt8(40), UInt8(80), UInt8(220)), count: 10)
        let glut = try #require(Huellenton.glut(rgba: bild(punkte)))
        let h = glut.haupt.hsb.farbton
        #expect(h > 0.55 && h < 0.7)
    }

    @Test("Eine graue Hülle glüht grau, eine schwarze gar nicht")
    func grau() throws {
        let glut = try #require(Huellenton.glut(rgba: bild(Array(repeating: (128, 128, 128), count: 16))))
        #expect(glut.haupt.hsb.saettigung < 0.12)
        #expect(Huellenton.glut(rgba: bild(Array(repeating: (0, 0, 0), count: 16))) == nil)
        #expect(Huellenton.glut(rgba: []) == nil)
    }

    @Test("HSB hin und zurück")
    func hsb() {
        let f = Farbwert(rot: 0.76, gruen: 0.25, blau: 0.48)
        let (h, s, v) = f.hsb
        let z = Farbwert(farbton: h, saettigung: s, helligkeit: v)
        #expect(abs(z.rot - f.rot) < 0.0001 && abs(z.gruen - f.gruen) < 0.0001 && abs(z.blau - f.blau) < 0.0001)
    }
}

@Suite("Ablage")
struct AblageTests {

    private func datei(_ l: Lied) -> Ablageverzeichnis.Datei {
        .init(lied: l, pfad: "\(l.id).flac", groesse: 1000, art: .direkt, mime: "audio/flac",
              geladen: Date(timeIntervalSince1970: 1))
    }

    @Test("Vormerken, eintragen, Stand")
    func stand() {
        var v = Ablageverzeichnis()
        let album = Sammlungsverweis(art: .album, kennung: "al1", titel: "Nachtfahrt")
        v.vormerken(album, lieder: [lied("a"), lied("b")])
        #expect(v.stand(album.id) == .teilweise(fertig: 0, von: 2))
        #expect(v.warteschlange.map(\.id) == ["a", "b"])
        v.eintragen(datei(lied("a")))
        #expect(v.stand(album.id) == .teilweise(fertig: 1, von: 2))
        v.eintragen(datei(lied("b")))
        #expect(v.stand(album.id) == .ganz)
        #expect(v.istGeladen("a"))
        #expect(v.belegt == 2000)
        #expect(v.stand("album:gibtsnicht") == .nicht)
    }

    /// Ein Lied in Album und Playlist: die Datei bleibt, bis keine es braucht.
    @Test("Entfernen lässt geteilte Dateien liegen")
    func geteilt() {
        var v = Ablageverzeichnis()
        let album = Sammlungsverweis(art: .album, kennung: "al1", titel: "")
        let liste = Sammlungsverweis(art: .playlist, kennung: "p1", titel: "")
        v.vormerken(album, lieder: [lied("a"), lied("b")], jetzt: Date(timeIntervalSince1970: 1))
        v.vormerken(liste, lieder: [lied("b"), lied("c")], jetzt: Date(timeIntervalSince1970: 2))
        #expect(v.warteschlange.map(\.id) == ["a", "b", "c"])
        for id in ["a", "b", "c"] { v.eintragen(datei(lied(id))) }
        let frei = v.entfernen(album.id)
        #expect(frei.map(\.lied.id) == ["a"])
        #expect(v.istGeladen("b"))
        #expect(v.stand(liste.id) == .ganz)
        #expect(v.entfernen("album:weg").isEmpty)
    }

    @Test("Eine fehlende Datei kommt wieder in die Warteschlange")
    func vergessen() {
        var v = Ablageverzeichnis()
        let album = Sammlungsverweis(art: .album, kennung: "al1", titel: "")
        v.vormerken(album, lieder: [lied("a"), lied("b")])
        v.eintragen(datei(lied("a")))
        v.eintragen(datei(lied("b")))
        v.vergessen(liedID: "a")
        #expect(v.stand(album.id) == .teilweise(fertig: 1, von: 2))
        #expect(v.warteschlange.map(\.id) == ["a"])
    }

    @Test("Verwaiste Dateien und alles leeren")
    func aufraeumen() {
        var v = Ablageverzeichnis()
        v.eintragen(datei(lied("x")))
        #expect(v.verwaisteEntfernen().map(\.lied.id) == ["x"])
        v.vormerken(Sammlungsverweis(art: .album, kennung: "a", titel: ""), lieder: [lied("y")])
        v.eintragen(datei(lied("y")))
        #expect(v.leeren().count == 1)
        #expect(v.sammlungen.isEmpty)
    }

    /// Wörtliches JSON statt Hin und Zurück — sonst prüft der Test nur,
    /// dass unser Kodierer zu unserem Dekodierer passt (`Fallen/ablage.md`).
    @Test("Eine alte Ablage ohne neue Felder bleibt lesbar")
    func alteAblage() throws {
        let json = #"""
        {"dateien":{"a":{"lied":{"id":"a","titel":"Auffahrt"},"pfad":"a.flac"}},
         "sammlungen":{"album:al1":{"verweis":{"art":"album","kennung":"al1","titel":"Nachtfahrt"},
                                    "lieder":[{"id":"a","titel":"Auffahrt"}]}}}
        """#
        let v = try JSONDecoder().decode(Ablageverzeichnis.self, from: Data(json.utf8))
        #expect(v.istGeladen("a"))
        #expect(v.datei(fuer: "a")?.art == .direkt)
        #expect(v.datei(fuer: "a")?.lied.favorit == false)
        #expect(v.stand("album:al1") == .ganz)
        let wieder = try JSONDecoder().decode(Ablageverzeichnis.self, from: JSONEncoder().encode(v))
        #expect(wieder == v)
    }
}

@Suite("Zeiten und Seiten")
struct ZeitformatTests {

    @Test("Vorgelesen ohne Doppelpunkt, in Minuten und Sekunden")
    func gesprochen() {
        let de = Locale(identifier: "de_DE")
        #expect(!Zeitformat.gesprochen(225, locale: de).contains(":"))
        #expect(Zeitformat.gesprochen(225, locale: de).contains("3"))
        #expect(Zeitformat.gesprochen(225, locale: de).contains("45"))
        #expect(!Zeitformat.gesprochen(4000, locale: de).contains(":"))
        #expect(!Zeitformat.gesprochen(.nan, locale: de).isEmpty)
    }

    @Test("Dauer, Rest und Minuten")
    func zeiten() {
        #expect(Zeitformat.dauer(247) == "4:07")
        #expect(Zeitformat.dauer(98.9) == "1:38")
        #expect(Zeitformat.dauer(3725) == "1:02:05")
        #expect(Zeitformat.dauer(-3) == "0:00")
        #expect(Zeitformat.dauer(.nan) == "0:00")
        #expect(Zeitformat.rest(148.6) == "\u{2212}2:29")
        #expect(Zeitformat.minuten(2460) == 41)
        #expect(Zeitformat.minuten(20) == 1)
        #expect(Zeitformat.minuten(0) == 0)
    }

    @Test("Wo die nächste Seite anfängt")
    func seite() {
        #expect(Seite<Int>.weiter(ab: 0, bekommen: 100, verlangt: 100, gesamt: nil) == 100)
        #expect(Seite<Int>.weiter(ab: 0, bekommen: 40, verlangt: 100, gesamt: nil) == nil)
        #expect(Seite<Int>.weiter(ab: 100, bekommen: 100, verlangt: 100, gesamt: 200) == nil)
        #expect(Seite<Int>.weiter(ab: 100, bekommen: 50, verlangt: 100, gesamt: 400) == 150)
        #expect(Seite<Int>.weiter(ab: 0, bekommen: 0, verlangt: 100, gesamt: 10) == nil)
    }

    @Test("Die Ablage eines Kontos heißt je Server und Benutzer anders")
    func kontoname() {
        let a = Kontokennung(server: URL(string: "https://a.example")!, benutzerID: "1")
        let b = Kontokennung(server: URL(string: "https://a.example")!, benutzerID: "2")
        #expect(a.ablagename != b.ablagename)
        #expect(a.ablagename == Kontokennung(server: URL(string: "https://a.example")!, benutzerID: "1").ablagename)
    }
}

@Suite("Höchstrate je Netz")
struct HoechstrateTests {

    private let flac = Tonformat(codec: "flac", behaelter: "flac")
    private let mp3hoch = Tonformat(codec: "mp3", behaelter: "mp3", bitrate: 320)
    private let aacniedrig = Tonformat(codec: "aac", behaelter: "m4a", bitrate: 128)
    private let ogg = Tonformat(codec: "vorbis", behaelter: "ogg", bitrate: 160)

    @Test("Ohne Grenze: direkt, was das Gerät spielt; der Rest in 320")
    func ohneGrenze() {
        #expect(Abspielregel.umwandlung(fuer: flac, hoechstens: nil) == nil)
        #expect(Abspielregel.umwandlung(fuer: mp3hoch, hoechstens: nil) == nil)
        #expect(Abspielregel.umwandlung(fuer: ogg, hoechstens: nil)?.bitrate == 320)
    }

    @Test("Mit Grenze: verlustfrei und zu hohe Raten werden umgewandelt, niedrige bleiben")
    func mitGrenze() {
        #expect(Abspielregel.umwandlung(fuer: flac, hoechstens: 192) == Umwandlung(codec: "mp3", bitrate: 192))
        #expect(Abspielregel.umwandlung(fuer: mp3hoch, hoechstens: 192)?.bitrate == 192)
        #expect(Abspielregel.umwandlung(fuer: aacniedrig, hoechstens: 192) == nil)
        #expect(Abspielregel.umwandlung(fuer: ogg, hoechstens: 128)?.bitrate == 128)
        // Unbekannte Rate: lieber umwandeln als das Datenvolumen verraten.
        #expect(Abspielregel.umwandlung(fuer: nil, hoechstens: 128)?.bitrate == 128)
    }

    @Test("Jellyfin und Subsonic tragen die Grenze in die Adresse")
    func adressen() throws {
        let ss = Subsonicstelle([:]).quelle()
        let lied = Lied(id: "a", titel: "", format: flac)
        let weg = try #require(ss.abspielweg(lied, sitzung: "s", hoechstens: 192))
        #expect(weg.art == .umgewandelt)
        #expect(weg.adresse.absoluteString.contains("maxBitRate=192"))
        #expect(weg.umwandlung?.bitrate == 192)
        #expect(ss.abspielweg(lied, sitzung: "s")?.art == .direkt)
        // Geladen wird immer das Original.
        #expect(ss.ladeweg(lied)?.art == .direkt)
    }
}

@Suite("Laden je Netz")
struct LadeerlaubnisTests {
    @Test("Im WLAN immer, über Mobilfunk nur ohne „Nur über WLAN“, ohne Netz nie")
    func erlaubnis() {
        #expect(Ladeerlaubnis.darf(.wlan, nurWLAN: true))
        #expect(Ladeerlaubnis.darf(.mobil, nurWLAN: false))
        #expect(!Ladeerlaubnis.darf(.mobil, nurWLAN: true))
        #expect(!Ladeerlaubnis.darf(.keine, nurWLAN: false))
    }
}
