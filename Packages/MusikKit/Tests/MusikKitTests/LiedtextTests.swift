import Foundation
import Testing
@testable import MusikKit

@Suite("Liedtext")
struct LiedtextTests {

    @Test("LRC: Zeiten, Kopfzeilen und mehrere Marken vor einer Zeile")
    func lrc() {
        let text = """
        [ar:Lina Brenner]
        [ti:Nachtfahrt]
        [00:04.20]und du drehst das Radio lauter
        [00:00.00]Die Stadt geht aus, Laterne für Laterne
        [00:09.05][01:30.5]Halt nicht an, die Straße kennt den Weg
        [00:13.80]
        """
        let l = Liedtext.lrc(text)
        #expect(l.getaktet)
        #expect(l.zeilen.map(\.zeit) == [0, 4.2, 9.05, 13.8, 90.5])
        #expect(l.zeilen[0].text == "Die Stadt geht aus, Laterne für Laterne")
        #expect(l.zeilen[3].istPause)
        #expect(l.zeilen[4].text == "Halt nicht an, die Straße kennt den Weg")
    }

    /// Plus heißt früher — so steht es in der Beschreibung des Formats.
    @Test("LRC: [offset:+500] zieht alles eine halbe Sekunde vor")
    func versatz() {
        let l = Liedtext.lrc("[offset:+500]\n[00:10.00]a\n[00:00.20]b")
        #expect(l.zeilen.map(\.zeit) == [0, 9.5])
    }

    @Test("LRC: Wortmarken fallen weg, andere spitze Klammern bleiben")
    func wortmarken() {
        let l = Liedtext.lrc("[00:01.00]<00:01.00>Halt <00:01.50>nicht <a> an")
        #expect(l.zeilen.first?.text == "Halt nicht <a> an")
    }

    @Test("LRC: alte Schreibweise mm:ss:xx und Stunden")
    func schreibweisen() {
        #expect(Liedtext.zeitmarke("01:02:50") == 62.5)
        #expect(Liedtext.zeitmarke("1:02:03.5") == 3723.5)
        #expect(Liedtext.zeitmarke("00:12") == 12)
        #expect(Liedtext.zeitmarke("ar") == nil)
        #expect(Liedtext.zeitmarke("00:75.0") == nil)
    }

    @Test("Ohne Zeitmarken ist es ein ungetakteter Text, leere Ränder fallen weg")
    func ungetaktet() {
        let l = Liedtext.lrc("\nerste Zeile\n\nzweite Strophe\n\n")
        #expect(!l.getaktet)
        #expect(l.zeilen.map(\.text) == ["erste Zeile", "", "zweite Strophe"])
        #expect(l.aktuelleZeile(zu: 10) == nil)
        #expect(l.sprungziel(0) == nil)
    }

    @Test("Die aktuelle Zeile folgt der Zeit, mit kurzem Vorlauf")
    func aktuelleZeile() {
        let l = Liedtext(zeilen: [
            .init(zeit: 1, text: "a"), .init(zeit: 4.2, text: "b"),
            .init(zeit: 9.05, text: "c"), .init(zeit: 13.8, text: "d"),
        ])
        #expect(l.aktuelleZeile(zu: 0, vorlauf: 0) == nil)
        #expect(l.aktuelleZeile(zu: 1, vorlauf: 0) == 0)
        #expect(l.aktuelleZeile(zu: 4.1, vorlauf: 0) == 0)
        #expect(l.aktuelleZeile(zu: 4.1) == 1)
        #expect(l.aktuelleZeile(zu: 9.1, vorlauf: 0) == 2)
        #expect(l.aktuelleZeile(zu: 500, vorlauf: 0) == 3)
        #expect(l.sprungziel(2) == 9.05)
        #expect(l.sprungziel(9) == nil)
    }

    @Test("Zeilen ohne Zeit fallen aus einem getakteten Text heraus")
    func gemischt() {
        let l = Liedtext(zeilen: [.init(zeit: 2, text: "b"), .init(zeit: nil, text: "x"),
                                  .init(zeit: 1, text: "a")])
        #expect(l.zeilen.map(\.text) == ["a", "b"])
    }

    @Test("Alle Zeilen zur selben Zeit: ungetaktet, Reihenfolge bleibt")
    func gleicheZeiten() {
        let l = Liedtext(zeilen: [.init(zeit: 0, text: "eins"), .init(zeit: 0, text: "zwei"),
                                  .init(zeit: 0, text: "drei")])
        #expect(!l.getaktet)
        #expect(l.zeilen.map(\.text) == ["eins", "zwei", "drei"])
        #expect(l.aktuelleZeile(zu: 12) == nil)
        // Eine einzige getaktete Zeile bleibt getaktet.
        #expect(Liedtext(zeilen: [.init(zeit: 3, text: "nur")]).getaktet)
    }
}
