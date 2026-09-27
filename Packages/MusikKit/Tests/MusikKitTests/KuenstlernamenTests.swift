import Foundation
import Testing
@testable import MusikKit

@Suite("Mehrere Künstler")
struct KuenstlernamenTests {

    @Test("Ein roher Tag wird an Semikolon und Schrägstrich mit Leerzeichen zerlegt")
    func zerlegen() {
        #expect(Kuenstlernamen.zerlegen("Ikkimel;nocashfromparents;Florida Juicy")
                == ["Ikkimel", "nocashfromparents", "Florida Juicy"])
        #expect(Kuenstlernamen.zerlegen("A / B; C") == ["A", "B", "C"])
        #expect(Kuenstlernamen.zerlegen("AC/DC") == ["AC/DC"])
        #expect(Kuenstlernamen.zerlegen(" ; ") == [])
    }

    @Test("Die Liste zerlegt jeden Eintrag und streicht Doppelte")
    func liste() {
        #expect(Kuenstlernamen.liste(["A;B", "b", "C"]) == ["A", "B", "C"])
    }

    @Test("Die Zeile folgt der Sprache", arguments: [
        ("de_DE", ["A"], "A"),
        ("de_DE", ["A", "B"], "A und B"),
        ("de_DE", ["A", "B", "C"], "A, B und C"),
        ("en_US", ["A", "B"], "A and B"),
    ])
    func zeile(_ sprache: String, _ namen: [String], _ erwartet: String) {
        #expect(Kuenstlernamen.zeile(namen, sprache: Locale(identifier: sprache)) == erwartet)
    }

    @Test("Englisch mit drei Namen: Kommas und „and“")
    func zeileEnglisch() {
        let zeile = Kuenstlernamen.zeile(["A", "B", "C"], sprache: Locale(identifier: "en_US")) ?? ""
        #expect(zeile.hasPrefix("A, B"))
        #expect(zeile.hasSuffix("and C"))
    }

    @Test("Ohne Namen keine Zeile")
    func leer() {
        #expect(Kuenstlernamen.zeile([]) == nil)
    }

    @Test("Ein Lied ohne Liste zerlegt seine Zeile — auch ein altes, abgelegtes")
    func liedRueckfall() throws {
        let alt = Lied(id: "1", titel: "x", kuenstler: "Ikkimel;nocashfromparents")
        #expect(alt.kuenstlernamen == ["Ikkimel", "nocashfromparents"])
        let neu = Lied(id: "2", titel: "y", kuenstler: "egal", kuenstlerliste: ["A", "B"])
        #expect(neu.kuenstlernamen == ["A", "B"])
        let daten = try JSONEncoder().encode(neu)
        #expect(try JSONDecoder().decode(Lied.self, from: daten).kuenstlerliste == ["A", "B"])
    }

    @Test("Gleich heißt: dieselben Namen, egal in welcher Folge")
    func gleich() {
        #expect(Kuenstlernamen.gleich(["A", "B"], ["b", "a"]))
        #expect(!Kuenstlernamen.gleich(["A"], ["A", "B"]))
    }

    @Test("Jellyfin: die erste Liste mit Inhalt, zerlegt")
    func jellyfinNamen() {
        #expect(JellyfinQuelle.namen([], ["Ikkimel;Florida Juicy"], ["Albumkünstler"])
                == ["Ikkimel", "Florida Juicy"])
        #expect(JellyfinQuelle.namen([], [], ["Albumkünstler"]) == ["Albumkünstler"])
    }
}
