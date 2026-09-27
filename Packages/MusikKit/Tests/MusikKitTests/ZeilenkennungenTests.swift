import Testing
@testable import MusikKit

@Suite("Kapselwechsel: ziehen oder überblenden")
struct ZeilenkennungenTests {

    @Test("Nahe Plätze auf dem Schirm behalten die Kennung — die Zeile zieht")
    func nahZieht() {
        var k = Zeilenkennungen()
        k.wechsel(von: ["a", "b", "c", "d"], nach: ["b", "d"], sichtbar: 10)
        #expect(k.kennung("b") == "b")
        #expect(k.kennung("d") == "d")
    }

    @Test("Weiter als ein halber Schirm: neue Kennung, die Zeile blendet")
    func weitBlendet() {
        var k = Zeilenkennungen()
        let alt = (0 ..< 20).map { "x\($0)" }
        k.wechsel(von: alt, nach: ["x9", "x1"], sichtbar: 12)
        #expect(k.kennung("x9") != "x9")   // 9 → 0: mehr als 6 Plätze
        #expect(k.kennung("x1") == "x1")   // 1 → 1
    }

    @Test("Von draußen herein oder nach draußen: blendet; beide draußen: bleibt")
    func draussen() {
        var k = Zeilenkennungen()
        let alt = (0 ..< 40).map { "x\($0)" }
        // x30 kommt von unten auf Platz 0, x2 geht auf Platz 25, x35 bleibt draußen.
        var neu = ["x30"] + (0 ..< 24).map { "n\($0)" } + ["x2"]
        neu += (0 ..< 10).map { "m\($0)" } + ["x35"]
        k.wechsel(von: alt, nach: neu, sichtbar: 12)
        #expect(k.kennung("x30") != "x30")
        #expect(k.kennung("x2") != "x2")
        #expect(k.kennung("x35") == "x35")
        #expect(k.kennung("n3") == "n3")
    }

    @Test("Angeheftete Zeilen zählen mit")
    func angeheftet() {
        var k = Zeilenkennungen()
        // Ohne die zwei angehefteten stünde a auf 5 → 0 (zu weit bei 8);
        // mit ihnen oben in beiden Listen 7 → 2, also auch zu weit — und
        // nur oben in der alten: 7 → 0.
        k.wechsel(von: ["q", "r", "s", "t", "u", "a"], nach: ["a"], vorAlt: 2, vorNeu: 0, sichtbar: 8)
        #expect(k.kennung("a") != "a")
        var m = Zeilenkennungen()
        m.wechsel(von: ["q", "a"], nach: ["a"], vorAlt: 2, vorNeu: 0, sichtbar: 8)
        #expect(m.kennung("a") == "a")     // 3 → 0
    }

    @Test("Gescrollt (sichtbar 0): nichts zieht, alles blendet")
    func gescrollt() {
        var k = Zeilenkennungen()
        k.wechsel(von: ["a", "b"], nach: ["a", "b"], sichtbar: 0)
        #expect(k.kennung("a") != "a")
        #expect(k.kennung("b") != "b")
    }

    @Test("Die Kennung bleibt bis zum nächsten Wechsel, und zieht dann weiter mit ihr")
    func bleibt() {
        var k = Zeilenkennungen()
        let alt = (0 ..< 20).map { "x\($0)" }
        k.wechsel(von: alt, nach: ["x15"], sichtbar: 12)
        let einmal = k.kennung("x15")
        #expect(einmal != "x15")
        #expect(k.kennung("x15") == einmal)
        k.wechsel(von: ["x15"], nach: ["y", "x15"], sichtbar: 12)
        #expect(k.kennung("x15") == einmal)
        // Wer nicht mehr in der Liste steht, fällt heraus.
        k.wechsel(von: ["y", "x15"], nach: ["y"], sichtbar: 12)
        #expect(k.kennung("x15") == "x15")
    }

    @Test("Schnelles Hin und Her: jede Runde eine eigene Kennung für Weitgereiste")
    func hinUndHer() {
        var k = Zeilenkennungen()
        let gemischt = (0 ..< 30).map { "x\($0)" }
        let fach = ["x20", "x25"]
        k.wechsel(von: gemischt, nach: fach, sichtbar: 12)
        let hin = k.kennung("x20")
        k.wechsel(von: fach, nach: gemischt, sichtbar: 12)
        let zurueck = k.kennung("x20")
        #expect(hin != "x20")
        #expect(zurueck != hin)
    }
}
