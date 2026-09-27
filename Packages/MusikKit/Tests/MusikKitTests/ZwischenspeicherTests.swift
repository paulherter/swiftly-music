import Testing
@testable import MusikKit

@Suite("Zwischenspeicher und Abfragewache")
struct ZwischenspeicherTests {

    @Test("Voll: der am längsten nicht gebrauchte Eintrag geht")
    func grenze() {
        var s = Zwischenspeicher<String, Int>(grenze: 2)
        s.merken(1, fuer: "a")
        s.merken(2, fuer: "b")
        #expect(s.wert("a") == 1)   // a ist jetzt frischer als b
        s.merken(3, fuer: "c")
        #expect(s.anzahl == 2)
        #expect(s.wert("b") == nil)
        #expect(s.wert("a") == 1)
        #expect(s.wert("c") == 3)
    }

    @Test("Überschreiben zählt nicht doppelt")
    func ueberschreiben() {
        var s = Zwischenspeicher<String, Int>(grenze: 2)
        s.merken(1, fuer: "a")
        s.merken(2, fuer: "a")
        s.merken(3, fuer: "b")
        #expect(s.anzahl == 2)
        #expect(s.wert("a") == 2)
    }

    @Test("Kein Liedtext wird gemerkt, nicht als fehlend gelesen")
    func nichtsGemerkt() {
        var s = Zwischenspeicher<String, Liedtext?>(grenze: 50)
        s.merken(nil, fuer: "lied")
        let gemerkt = s.wert("lied")
        #expect(gemerkt != nil)
        #expect(gemerkt! == nil)
        s.leeren()
        #expect(s.wert("lied") == nil)
    }

    @Test("Wache: ohne Antwort nach der Frist gestört, Antwort setzt zurück")
    func frist() {
        var w = Abfragewache()
        #expect(w.lage == .laedt)
        w.fehlgeschlagen()
        #expect(w.lage == .laedt)
        w.fristVorbei()
        #expect(w.lage == .gestoert)
        w.geantwortet()
        #expect(w.lage == .da)
        w.fristVorbei()
        #expect(w.lage == .da)
    }

    @Test("Wache: drei Fehlschläge in Folge, auch nach einer Antwort")
    func fehlschlaege() {
        var w = Abfragewache()
        w.geantwortet()
        w.fehlgeschlagen()
        w.fehlgeschlagen()
        #expect(w.lage == .da)
        w.fehlgeschlagen()
        #expect(w.lage == .gestoert)
        w.vonVorn()
        #expect(w.lage == .laedt)
        w.fehlgeschlagen()
        #expect(w.lage == .laedt)
    }
}
