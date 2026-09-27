import Foundation
import Testing
@testable import MusikKit

/// **Die drei Balken wechseln sich ab** — mit künstlichen Signalen, die wie
/// Musik gebaut sind: basslastig, höhenlastig, Sprache. Über 20 Sekunden
/// muss jeder Balken oben und unten gewesen sein, und keine Form (welcher
/// Balken der höchste, welcher der niedrigste ist) darf überwiegen.
@Suite("Pegel: Anzeige")
struct PegelanzeigeTests {

    private static let rate = 44_100.0
    private static let block = 1024

    /// Ein fester Zufall, damit jeder Lauf dasselbe hört.
    private struct Zufall {
        var z: UInt64 = 0x9E37_79B9_7F4A_7C15
        mutating func naechster() -> Float {
            z = z &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Double(z >> 11) / Double(1 << 53)) * 2 - 1
        }
    }

    /// Ein Schlag: Hüllkurve, die bei `t` beginnt und mit `abklingen` fällt.
    private static func schlag(_ t: Double, alle takt: Double, abklingen: Double, versatz: Double = 0) -> Float {
        let u = (t - versatz).truncatingRemainder(dividingBy: takt)
        return u < 0 ? 0 : Float(exp(-u / abklingen))
    }

    /// Ein Signal Probe für Probe, durch Analyse und Anzeige; zurück kommen
    /// die angezeigten Werte je Block nach zwei Sekunden Anlauf.
    private func anzeigen(sekunden: Double = 20, _ signal: (Double, inout Zufall) -> Float) -> [Pegelanalyse.Baender] {
        var analyse = Pegelanalyse(abtastrate: Self.rate)
        var anzeige = Pegelanzeige()
        var zufall = Zufall()
        var probe = [Float](repeating: 0, count: Self.block)
        var n = 0
        var werte: [Pegelanalyse.Baender] = []
        let dauer = Double(Self.block) / Self.rate
        for _ in 0 ..< Int(sekunden * Self.rate) / Self.block {
            for i in 0 ..< Self.block {
                probe[i] = signal(Double(n) / Self.rate, &zufall)
                n += 1
            }
            probe.withUnsafeBufferPointer { analyse.aufnehmen($0.baseAddress!, nil, anzahl: Self.block) }
            let b = anzeige.schritt(analyse.abschliessen(), dauer: dauer)
            if Double(n) / Self.rate > 2 { werte.append(b) }
        }
        return werte
    }

    private func pruefen(_ werte: [Pegelanalyse.Baender]) {
        for (name, band) in [("tief", \Pegelanalyse.Baender.tief), ("mittel", \.mittel), ("hoch", \.hoch)] {
            let reihe = werte.map { $0[keyPath: band] }
            // Ruhiger als früher (24.09.: „chilliger"), aber jeder
            // Balken kommt weit hoch und weit herunter.
            #expect((reihe.max() ?? 0) > 0.72, "\(name) kommt nie hoch: \(reihe.max() ?? 0)")
            #expect((reihe.min() ?? 1) < 0.35, "\(name) kommt nie herunter: \(reihe.min() ?? 1)")
            // Nicht nur einmal: wenigstens ein Zehntel der Zeit oben und unten.
            #expect(reihe.filter { $0 > 0.55 }.count > reihe.count / 10, "\(name) selten oben")
            #expect(reihe.filter { $0 < 0.45 }.count > reihe.count / 10, "\(name) selten unten")
            // **Ruhig**: je Block (23 ms) bewegt sich ein Balken um höchstens
            // 15 % seiner Höhe — vorher bis 55 %.
            let schritte = zip(reihe, reihe.dropFirst()).map { abs(Pegelanzeige.balken($1) - Pegelanzeige.balken($0)) }
            #expect((schritte.max() ?? 0) <= 0.15, "\(name) springt: \(schritte.max() ?? 0)")
        }
        // Welcher Balken der höchste ist: keiner in mehr als gut der Hälfte der
        // Zeit. Die ruhigeren Balken halten ihre Lage etwas länger (vorher
        // höchstens 50 %).
        var hoechster = [0, 0, 0]
        for b in werte {
            let w = [b.tief, b.mittel, b.hoch]
            hoechster[w.firstIndex(of: w.max()!)!] += 1
        }
        for (i, z) in hoechster.enumerated() {
            #expect(Double(z) / Double(werte.count) < 0.56, "Balken \(i) fast immer der höchste: \(hoechster)")
        }
    }

    @Test("Basslastig: Bass laut, Höhen leise — alle drei wechseln sich ab")
    func basslastig() {
        pruefen(anzeigen { t, zufall in
            let bass = 0.8 * Self.schlag(t, alle: 0.5, abklingen: 0.12) * Float(sin(2 * .pi * 55 * t))
            let akkord = 0.12 * (0.6 + 0.4 * Float(sin(2 * .pi * 0.3 * t)))
                * Float(sin(2 * .pi * 440 * t) + sin(2 * .pi * 660 * t))
            let becken = 0.05 * Self.schlag(t, alle: 0.25, abklingen: 0.04, versatz: 0.125) * zufall.naechster()
            return bass + akkord + becken
        })
    }

    @Test("Höhenlastig: Becken laut, wenig Bass — alle drei wechseln sich ab")
    func hoehenlastig() {
        pruefen(anzeigen { t, zufall in
            let becken = 0.5 * Self.schlag(t, alle: 0.2, abklingen: 0.06) * zufall.naechster()
            let bass = 0.1 * Self.schlag(t, alle: 0.8, abklingen: 0.2, versatz: 0.4) * Float(sin(2 * .pi * 70 * t))
            let stimme = 0.15 * Self.schlag(t, alle: 0.6, abklingen: 0.25, versatz: 0.1)
                * Float(sin(2 * .pi * 880 * t))
            return becken + bass + stimme
        })
    }

    @Test("Sprache: Silben um 4 Hz mit Pausen — alle drei wechseln sich ab")
    func sprache() {
        pruefen(anzeigen { t, zufall in
            let silbe = Float(max(0, sin(2 * .pi * 4 * t))) * (sin(2 * .pi * 0.25 * t) > -0.3 ? 1 : 0)
            let grund = 140 + 30 * sin(2 * .pi * 0.7 * t)
            let stimme = Float(sin(2 * .pi * grund * t) + 0.6 * sin(2 * .pi * grund * 3 * t)
                + 0.4 * sin(2 * .pi * 1_800 * t))
            let zisch = Self.schlag(t, alle: 1.1, abklingen: 0.08, versatz: 0.3) * zufall.naechster()
            return 0.3 * silbe * stimme + 0.2 * zisch
        })
    }

    @Test("Ausschlag der Balken: 30 bis 85 % des Felds")
    func ausschlag() {
        #expect(Pegelanzeige.balken(0) == Pegelanzeige.balkenUnten)
        #expect(Pegelanzeige.balken(1) == Pegelanzeige.balkenOben)
        #expect(Pegelanzeige.balken(2) == Pegelanzeige.balkenOben)
        #expect(Pegelanzeige.balkenOben <= 0.85 && Pegelanzeige.balkenUnten >= 0.3)
    }

    @Test("Ein Schlag aus der Stille hebt den Balken, statt ihn hochzureißen")
    func anstieg() {
        var anzeige = Pegelanzeige()
        for _ in 0 ..< 60 { _ = anzeige.schritt(.still, dauer: 1.0 / 30) }
        var t = 0.0
        var halb: Double?
        for _ in 0 ..< 30 {
            t += 1.0 / 30
            let b = anzeige.schritt(Pegelanalyse.Baender(tief: 1, mittel: 1, hoch: 1), dauer: 1.0 / 30)
            if halb == nil, b.tief >= 0.5 { halb = t }
        }
        // Frühestens nach zwei Bildern bei der Hälfte, spätestens nach 0,2 s.
        #expect((halb ?? 1) >= 2.0 / 30 && (halb ?? 1) <= 0.2, "halb nach \(halb ?? -1) s")
    }

    @Test("Stille bleibt unten, ein gleichbleibender Ton wird kein voller Ausschlag")
    func ruhig() {
        let stille = anzeigen(sekunden: 5) { _, _ in 0 }
        #expect(stille.allSatisfy { $0.tief == 0 && $0.mittel == 0 && $0.hoch == 0 })
        // Ein Ton, der sich nicht ändert, bewegt nichts — nach ein paar
        // Sekunden steht der Balken unten, statt voll stehen zu bleiben.
        let ton = anzeigen(sekunden: 10) { t, _ in 0.5 * Float(sin(2 * .pi * 440 * t)) }
        #expect((ton.last?.mittel ?? 1) < 0.2)
    }
}
