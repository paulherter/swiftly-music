import Foundation
import Testing
@testable import MusikKit

@Suite("Warteschlange")
struct WarteschlangeTests {

    private let fuenf = ["a", "b", "c", "d", "e"].map { lied($0) }

    private func ids(_ s: Warteschlange) -> [String] { s.eintraege.map(\.lied.id) }

    @Test("Füllen und bei einem Lied anfangen")
    func setzen() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 2, mischen: false)
        #expect(s.aktuell?.lied.id == "c")
        #expect(s.naechster?.lied.id == "d")
        #expect(s.vorheriger?.lied.id == "b")
        #expect(s.kommende.map(\.lied.id) == ["d", "e"])
        #expect(s.gespielt.map(\.lied.id) == ["a", "b"])
    }

    @Test("Gemischt steht das gewählte Lied vorn, der Rest in anderer Folge")
    func gemischtMitStart() {
        var g = FesterZufall(7)
        var s = Warteschlange()
        s.setzen(fuenf, ab: 3, mischen: true, generator: &g)
        #expect(s.aktuell?.lied.id == "d")
        #expect(s.position == 0)
        #expect(Set(ids(s)) == Set(["a", "b", "c", "d", "e"]))
        #expect(s.gemischt)
    }

    @Test("Am Ende bleibt die Stelle stehen, am Anfang auch")
    func raender() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 4, mischen: false)
        #expect(s.weiter() == nil)
        #expect(s.aktuell?.lied.id == "e")
        s.setzen(fuenf, ab: 0, mischen: false)
        #expect(s.zurueck() == nil)
        #expect(s.aktuell?.lied.id == "a")
        #expect(s.weiter()?.lied.id == "b")
    }

    @Test("Eine leere Liste ergibt eine leere Schlange")
    func leer() {
        var s = Warteschlange()
        s.setzen([], ab: 0, mischen: false)
        #expect(s.istLeer)
        #expect(s.aktuell == nil)
        #expect(s.weiter() == nil)
    }

    @Test("Als Nächstes steht direkt hinter dem laufenden, in der gegebenen Folge")
    func alsNaechstes() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 1, mischen: false)
        s.alsNaechstes([lied("x"), lied("y")])
        #expect(ids(s) == ["a", "b", "x", "y", "c", "d", "e"])
        #expect(s.naechster?.lied.id == "x")
    }

    /// Dasselbe Lied zweimal: jeder Eintrag hat seine eigene Kennung.
    @Test("Dasselbe Lied darf zweimal stehen")
    func doppelt() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 0, mischen: false)
        s.alsNaechstes([lied("a")])
        #expect(ids(s).prefix(2) == ["a", "a"])
        #expect(s.eintraege[0].id != s.eintraege[1].id)
    }

    @Test("Hinten an, auch in eine leere Schlange")
    func hintenAn() {
        var s = Warteschlange()
        s.hintenAn([lied("x")])
        #expect(s.aktuell?.lied.id == "x")
        s.hintenAn([lied("y")])
        #expect(ids(s) == ["x", "y"])
    }

    @Test("Entfernen verschiebt die Stelle, den laufenden nicht")
    func entfernen() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 2, mischen: false)
        s.entfernen(s.eintraege[0].id)
        #expect(s.aktuell?.lied.id == "c")
        #expect(s.position == 1)
        let laufend = s.aktuell!.id
        s.entfernen(laufend)
        #expect(s.aktuell?.id == laufend)
    }

    @Test("Verschieben unter den kommenden")
    func verschieben() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 0, mischen: false)
        let e = s.eintraege[4].id
        s.verschieben(e, nach: 0)
        #expect(ids(s) == ["a", "e", "b", "c", "d"])
        s.verschieben(e, nach: 99)
        #expect(ids(s) == ["a", "b", "c", "d", "e"])
        // Schon gespielte bleiben, wo sie sind.
        s.weiter(); s.weiter()
        s.verschieben(s.eintraege[0].id, nach: 0)
        #expect(ids(s) == ["a", "b", "c", "d", "e"])
    }

    /// Mischen aus: die ursprüngliche Folge, weiter hinter dem laufenden Lied.
    @Test("Mischen an und aus lässt das laufende Lied weiterlaufen")
    func mischen() {
        var g = FesterZufall(3)
        var s = Warteschlange()
        s.setzen(fuenf, ab: 1, mischen: false)
        s.alsNaechstes([lied("x")])
        s.mischen(true, generator: &g)
        #expect(s.aktuell?.lied.id == "b")
        #expect(s.gespielt.map(\.lied.id) == ["a"])
        #expect(Set(s.kommende.map(\.lied.id)) == Set(["x", "c", "d", "e"]))
        s.weiter()
        let jetzt = s.aktuell!.lied.id
        s.mischen(false, generator: &g)
        #expect(ids(s) == ["a", "b", "x", "c", "d", "e"])
        #expect(s.aktuell?.lied.id == jetzt)
    }

    @Test("Was kommt, lässt sich leeren")
    func leeren() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 1, mischen: false)
        s.kommendeLeeren()
        #expect(ids(s) == ["a", "b"])
        #expect(s.naechster == nil)
    }

    @Test("Ein geändertes Lied wird überall ersetzt, Kennungen bleiben")
    func aktualisieren() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 0, mischen: false)
        let kennung = s.eintraege[2].id
        var neu = lied("c")
        neu.favorit = true
        s.aktualisieren(neu)
        #expect(s.eintraege[2].lied.favorit)
        #expect(s.eintraege[2].id == kennung)
    }

    // MARK: Wiederholen

    @Test("Wiederholen schaltet aus → alles → ein Lied → aus")
    func wiederholenStufen() {
        var s = Warteschlange()
        #expect(s.wiederholung == .aus)
        s.wiederholungWeiterschalten()
        #expect(s.wiederholung == .alles)
        s.wiederholungWeiterschalten()
        #expect(s.wiederholung == .eines)
        s.wiederholungWeiterschalten()
        #expect(s.wiederholung == .aus)
    }

    @Test("Alles wiederholen: am Ende wieder vorn, am Anfang zurück ans Ende")
    func wiederholenAlles() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 4, mischen: false)
        #expect(s.naechster == nil)
        s.wiederholen(.alles)
        #expect(s.naechster?.lied.id == "a")
        #expect(!s.wiederholtLaufendes)
        #expect(s.weiter()?.lied.id == "a")
        #expect(s.position == 0)
        #expect(s.vorheriger?.lied.id == "e")
        #expect(s.zurueck()?.lied.id == "e")
    }

    @Test("Ein Lied wiederholen: das laufende beginnt von vorn, Weiter geht trotzdem weiter")
    func wiederholenEines() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 1, mischen: false)
        s.wiederholen(.eines)
        #expect(s.wiederholtLaufendes)
        #expect(s.naechster?.lied.id == "c")
        #expect(s.weiter()?.lied.id == "c")
        #expect(s.wiederholtLaufendes)
    }

    @Test("Ein einzelnes Lied mit „alles“ wiederholt sich selbst, ohne auf sich zu zeigen")
    func wiederholenEinzeln() {
        var s = Warteschlange()
        s.setzen([lied("a")], ab: 0, mischen: false)
        s.wiederholen(.alles)
        #expect(s.naechster == nil)
        #expect(s.vorheriger == nil)
        #expect(s.wiederholtLaufendes)
        s.wiederholen(.aus)
        #expect(!s.wiederholtLaufendes)
    }

    @Test("Wiederholen gilt über ein neues Füllen und das Mischen hinaus")
    func wiederholenBleibt() {
        var s = Warteschlange()
        s.wiederholen(.alles)
        s.setzen(fuenf, ab: 0, mischen: false)
        s.mischen(true)
        #expect(s.wiederholung == .alles)
        #expect(s.gemischt)
    }

    @Test("Eine leere Schlange wiederholt nichts")
    func wiederholenLeer() {
        var s = Warteschlange()
        s.wiederholen(.eines)
        #expect(!s.wiederholtLaufendes)
        #expect(s.naechster == nil)
        #expect(s.weiter() == nil)
    }
}

@Suite("Schlange über den Neustart")
struct SchlangenstandTests {

    private let fuenf = ["a", "b", "c", "d", "e"].map { lied($0, dauer: 200) }

    @Test("Abgelegt und gelesen: Folge, Stelle, Mischen und Wiederholen bleiben")
    func rundlauf() throws {
        var g = FesterZufall(3)
        var s = Warteschlange()
        s.setzen(fuenf, ab: 1, mischen: true, generator: &g)
        s.wiederholen(.alles)
        let stand = Schlangenstand(schlange: s, stelle: 42, herkunft: nil)
        let zurueck = try JSONDecoder().decode(Schlangenstand.self, from: JSONEncoder().encode(stand))
        #expect(zurueck == stand)
        #expect(zurueck.schlange.aktuell?.lied.id == "b")
        #expect(zurueck.schlange.gemischt)
        #expect(zurueck.schlange.wiederholung == .alles)
        #expect(zurueck.fortsetzen == 42)
        // Das Ausschalten des Mischens findet die alte Folge wieder.
        var ungemischt = zurueck.schlange
        ungemischt.mischen(false)
        #expect(ungemischt.eintraege.map(\.lied.id) == ["a", "b", "c", "d", "e"])
        #expect(ungemischt.aktuell?.lied.id == "b")
    }

    @Test("Kurz vor dem Ende geht es von vorn los, eine leere Schlange taugt nicht")
    func raender() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 0, mischen: false)
        #expect(Schlangenstand(schlange: s, stelle: 198, herkunft: nil).fortsetzen == 0)
        #expect(Schlangenstand(schlange: s, stelle: 0.5, herkunft: nil).fortsetzen == 0)
        #expect(!Schlangenstand(schlange: Warteschlange(), stelle: 0, herkunft: nil).taugt)
    }
}

@Suite("Ohne Netz")
struct OhneNetzTests {
    private let fuenf = ["a", "b", "c", "d", "e"].map { lied($0) }

    @Test("Weiter springt über, was nicht geladen ist")
    func ueberspringen() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 0, mischen: false)
        let geladen: Set = ["d"]
        #expect(s.weiterZuSpielbarem { geladen.contains($0.id) }?.lied.id == "d")
        #expect(s.position == 3)
    }

    @Test("Ohne Spielbares bleibt die Stelle; mit Wiederholung geht es über das Ende")
    func raender() {
        var s = Warteschlange()
        s.setzen(fuenf, ab: 2, mischen: false)
        #expect(s.weiterZuSpielbarem { $0.id == "a" } == nil)
        #expect(s.position == 2)
        s.wiederholen(.alles)
        #expect(s.weiterZuSpielbarem { $0.id == "a" }?.lied.id == "a")
        // Nie im Kreis zurück aufs laufende.
        #expect(s.weiterZuSpielbarem { $0.id == "a" } == nil)
        #expect(s.position == 0)
    }
}
