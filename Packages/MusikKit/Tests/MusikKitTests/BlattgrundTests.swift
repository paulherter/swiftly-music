import Foundation
import Testing
@testable import MusikKit

/// **Die Hülle grenzt sich vom Grund ab** — auch wenn sie einfarbig ist und
/// der Grund aus ihr selbst gerechnet wird.
@Suite("Blattgrund")
struct BlattgrundTests {

    /// Eine einfarbige Hülle als Bildpunkte, so wie sie verschwommen ankommt.
    private func flaeche(_ r: UInt8, _ g: UInt8, _ b: UInt8, n: Int = 96 * 96) -> [UInt8] {
        var p = [UInt8](repeating: 255, count: n * 4)
        for i in 0 ..< n {
            p[i * 4] = r
            p[i * 4 + 1] = g
            p[i * 4 + 2] = b
        }
        return p
    }

    private func grund(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> (huelle: Double, hellster: Double, kontrast: Double) {
        let huelle = Blattgrund.mittlereLeuchtdichte(flaeche(r, g, b))
        var punkte = flaeche(r, g, b)
        Blattgrund.anpassen(&punkte, huelle: huelle)
        var hellster = 0.0
        var dunkelster = 1.0
        for i in stride(from: 0, to: punkte.count, by: 4) {
            let l = Blattgrund.leuchtdichte(punkte[i], punkte[i + 1], punkte[i + 2])
            hellster = max(hellster, l)
            dunkelster = min(dunkelster, l)
        }
        // Gegen die Hülle zählt der Punkt, der ihr am nächsten kommt.
        let naechster = huelle >= hellster ? hellster : dunkelster
        let kontrast = (max(huelle, naechster) + 0.05) / (min(huelle, naechster) + 0.05)
        return (huelle, hellster, kontrast)
    }

    @Test("Rote Hülle: der Grund ist deutlich dunkler, nicht dasselbe Rot")
    func rot() {
        let r = grund(255, 0, 0)
        #expect(r.kontrast >= 2.4, "Kontrast \(r.kontrast)")
        // Vorher (nur Grenze 0,09): 1,88 — kaum zu unterscheiden.
        #expect(r.hellster < 0.07)
    }

    @Test("Weiße Hülle: weit über dem Grund")
    func weiss() {
        let w = grund(255, 255, 255)
        #expect(w.kontrast >= 7)
        #expect(w.hellster <= Blattgrund.hoechsteLeuchtdichte + 0.001)
    }

    @Test("Schwarze Hülle: der Grund wird ein wenig angehoben")
    func schwarz() {
        let s = grund(0, 0, 0)
        #expect(s.kontrast >= 1.4, "Kontrast \(s.kontrast)")
        // Aber nicht grau: Weiß hat darauf weiter 7 : 1.
        #expect(s.hellster < 0.1)
    }

    @Test("Weiß bleibt überall lesbar: kein Punkt über der höchsten Leuchtdichte", arguments: [
        (UInt8(255), UInt8(230), UInt8(40)), (40, 200, 90), (30, 120, 255), (128, 128, 128), (255, 0, 0),
    ])
    func lesbar(_ farbe: (UInt8, UInt8, UInt8)) {
        let g = grund(farbe.0, farbe.1, farbe.2)
        #expect(g.hellster <= Blattgrund.hoechsteLeuchtdichte + 0.001)
        #expect((1.05 / (g.hellster + 0.05)) >= 7)
    }

    @Test("Entsättigt: der Ton bleibt, aber gedämpft")
    func entsaettigt() {
        var punkte = flaeche(255, 0, 0, n: 1)
        Blattgrund.anpassen(&punkte, huelle: 0.2126)
        #expect(punkte[0] > punkte[1] && punkte[0] > punkte[2])
        #expect(punkte[1] > 0, "etwas Grau darin")
    }
}
