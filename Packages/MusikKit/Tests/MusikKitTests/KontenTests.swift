import Foundation
import JellyfinKit
import SubsonicKit
import Testing
@testable import MusikKit

private struct Probe: Kontoeintrag {
    let server: String
    let benutzer: String
    var merkmal = "a"
    var kontokennung: Kontokennung { Kontokennung(server: URL(string: server)!, benutzerID: benutzer) }
}

@Suite("Mehrere Konten")
struct KontenTests {

    private let anna = Probe(server: "https://musik.example", benutzer: "anna")
    private let ben = Probe(server: "https://musik.example", benutzer: "ben")
    private let cleo = Probe(server: "http://navidrome.local:4533", benutzer: "cleo")

    @Test("Das erste Konto gilt")
    func erstes() {
        let reihe = Kontenreihe.aufgenommen(anna, in: nil)
        #expect(reihe.konten == [anna])
        #expect(reihe.aktives == anna)
        #expect(reihe.andere.isEmpty)
    }

    @Test("Ein weiteres Konto kommt hinten dazu und gilt, auch auf einem anderen Server")
    func weiteres() {
        var reihe = Kontenreihe(anna)
        reihe.aufnehmen(ben)
        reihe.aufnehmen(cleo)
        #expect(reihe.konten == [anna, ben, cleo])
        #expect(reihe.aktives == cleo)
        #expect(reihe.andere == [anna, ben])
    }

    @Test("Dasselbe Konto noch einmal ersetzt die alte Anmeldung an ihrer Stelle")
    func nochmal() {
        var reihe = Kontenreihe(anna)
        reihe.aufnehmen(ben)
        let neuAnna = Probe(server: "https://MUSIK.example/", benutzer: "anna", merkmal: "b")
        reihe.aufnehmen(neuAnna)
        #expect(reihe.konten.count == 2)
        #expect(reihe.konten[0].merkmal == "b")
        #expect(reihe.aktives == neuAnna)
    }

    @Test("Wechseln nur zu einem Konto, das es gibt")
    func wechseln() {
        var reihe = Kontenreihe(anna)
        reihe.aufnehmen(ben)
        reihe.wechseln(zu: anna.kontokennung)
        #expect(reihe.aktives == anna)
        reihe.wechseln(zu: cleo.kontokennung)
        #expect(reihe.aktives == anna)
    }

    @Test("Wird das aktive entfernt, gilt das nächste, am Ende das davor")
    func entfernen() throws {
        var reihe = Kontenreihe(anna)
        reihe.aufnehmen(ben)
        reihe.aufnehmen(cleo)
        reihe.wechseln(zu: ben.kontokennung)
        let ohneBen = try #require(reihe.entfernt(ben.kontokennung))
        #expect(ohneBen.konten == [anna, cleo])
        #expect(ohneBen.aktives == cleo)
        let ohneCleo = try #require(ohneBen.entfernt(cleo.kontokennung))
        #expect(ohneCleo.aktives == anna)
    }

    @Test("Ein anderes als das aktive entfernen lässt das aktive stehen")
    func anderesEntfernen() throws {
        var reihe = Kontenreihe(anna)
        reihe.aufnehmen(ben)
        let rest = try #require(reihe.entfernt(anna.kontokennung))
        #expect(rest.aktives == ben)
    }

    @Test("Ohne das letzte Konto bleibt keine Reihe")
    func letztes() {
        #expect(Kontenreihe(anna).entfernt(anna.kontokennung) == nil)
    }

    @Test("Die Reihe übersteht die Ablage samt aktivem Konto")
    func ablage() throws {
        var reihe = Kontenreihe(anna)
        reihe.aufnehmen(ben)
        reihe.wechseln(zu: anna.kontokennung)
        let daten = try JSONEncoder().encode(reihe)
        let gelesen = try #require(Kontenreihe<Probe>.ausAblage(reihe: daten, einzelne: nil))
        #expect(gelesen == reihe)
        #expect(gelesen.aktives == anna)
    }

    @Test("Die Anmeldung von vorher wird das erste Konto")
    func alteAblage() throws {
        let alt = try JSONEncoder().encode(anna)
        let reihe = try #require(Kontenreihe<Probe>.ausAblage(reihe: nil, einzelne: alt))
        #expect(reihe.konten == [anna])
    }

    @Test("Eine kaputte Reihe fällt auf die alte Anmeldung zurück, ein kaputter Eintrag nur auf sich")
    func kaputt() throws {
        let alt = try JSONEncoder().encode(anna)
        let muell = Data("{\"konten\": 3}".utf8)
        #expect(Kontenreihe<Probe>.ausAblage(reihe: muell, einzelne: alt)?.konten == [anna])

        let halb = Data("""
        {"konten": [{"server": "https://musik.example", "benutzer": "ben", "merkmal": "a"}, {"falsch": 1}],
         "aktiv": "nichts"}
        """.utf8)
        let reihe = try #require(Kontenreihe<Probe>.ausAblage(reihe: halb, einzelne: nil))
        #expect(reihe.konten == [ben])
        #expect(reihe.aktives == ben)
        #expect(Kontenreihe<Probe>.ausAblage(reihe: nil, einzelne: nil) == nil)
    }
}

@Suite("Gilt die Anmeldung noch?")
struct AnmeldestandTests {

    @Test("Nur 401 und 403 lehnen ab", arguments: [
        (200, Anmeldestand.gilt), (204, .gilt), (401, .giltNicht), (403, .giltNicht),
        (404, .unbekannt), (500, .unbekannt), (503, .unbekannt),
    ])
    func status(_ fall: (Int, Anmeldestand)) {
        #expect(Anmeldestand.aus(status: fall.0) == fall.1)
    }

    @Test("Subsonic: falsches Passwort und ungültiger Schlüssel lehnen ab")
    func subsonic() {
        #expect(Anmeldestand.aus(fehler: SubsonicFehler.server(code: 40, text: nil)) == .giltNicht)
        #expect(Anmeldestand.aus(fehler: SubsonicFehler.server(code: 44, text: nil)) == .giltNicht)
        #expect(Anmeldestand.aus(fehler: SubsonicFehler.http(401)) == .giltNicht)
        #expect(Anmeldestand.aus(fehler: SubsonicFehler.server(code: 0, text: nil)) == .unbekannt)
        #expect(Anmeldestand.aus(fehler: SubsonicFehler.keinSubsonic) == .unbekannt)
    }

    @Test("Ein Netzfehler heißt „weiß nicht“, nie „abmelden“")
    func netz() {
        #expect(Anmeldestand.aus(fehler: URLError(.notConnectedToInternet)) == .unbekannt)
        #expect(Anmeldestand.aus(fehler: URLError(.timedOut)) == .unbekannt)
        #expect(Anmeldestand.aus(fehler: JellyfinError.netz(code: -1009)) == .unbekannt)
        #expect(Anmeldestand.aus(fehler: JellyfinError.http(status: 401, body: nil)) == .giltNicht)
    }
}
