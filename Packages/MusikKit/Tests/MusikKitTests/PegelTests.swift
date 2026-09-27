import Foundation
import Testing
@testable import MusikKit

/// **Pegel und Farbe**: die drei Bänder aus echter Musik und die Fläche
/// des Mini-Players aus der Hülle.
@Suite("Pegel und Farbe")
struct PegelTests {

    /// Ein Sinus in Blöcken zu 1024 Proben, so wie der Tap sie liefert.
    private func analysieren(frequenz: Double, pegel: Float = 0.5, sekunden: Double = 1,
                             rate: Double = 44_100, stereo: Bool = false) -> Pegelanalyse.Baender {
        var a = Pegelanalyse(abtastrate: rate)
        let block = 1024
        let bloecke = Int(sekunden * rate) / block
        var probe = [Float](repeating: 0, count: block * (stereo ? 2 : 1))
        var n = 0
        for _ in 0 ..< bloecke {
            for i in 0 ..< block {
                let x = pegel * Float(sin(2 * Double.pi * frequenz * Double(n) / rate))
                if stereo { probe[2 * i] = x; probe[2 * i + 1] = x } else { probe[i] = x }
                n += 1
            }
            probe.withUnsafeBufferPointer { p in
                let basis = p.baseAddress!
                if stereo {
                    a.aufnehmen(basis, basis + 1, anzahl: block, schritt: 2)
                } else {
                    a.aufnehmen(basis, nil, anzahl: block)
                }
            }
            a.abschliessen()
        }
        return a.geglaettet
    }

    @Test("Ein tiefer Ton bewegt den tiefen Balken am meisten")
    func tief() {
        let b = analysieren(frequenz: 60)
        #expect(b.tief > 0.8)
        #expect(b.mittel < 0.5)
        #expect(b.hoch < 0.2)
    }

    @Test("Ein hoher Ton bewegt den hohen Balken am meisten")
    func hoch() {
        let b = analysieren(frequenz: 8_000)
        #expect(b.hoch > 0.8)
        #expect(b.tief < 0.2)
    }

    @Test("Verschränktes Stereo rechnet wie Mono")
    func stereo() {
        let mono = analysieren(frequenz: 1_000)
        let zwei = analysieren(frequenz: 1_000, stereo: true)
        #expect(abs(mono.mittel - zwei.mittel) < 0.01)
    }

    @Test("Stille ergibt null, auch nach Musik — langsam, nicht schlagartig")
    func stille() {
        var a = Pegelanalyse(abtastrate: 44_100)
        var laut = [Float](repeating: 0, count: 1024)
        for i in laut.indices { laut[i] = 0.5 * Float(sin(2 * Double.pi * 60 * Double(i) / 44_100)) }
        let leise = [Float](repeating: 0, count: 1024)
        for _ in 0 ..< 20 { laut.withUnsafeBufferPointer { a.aufnehmen($0.baseAddress!, nil, anzahl: 1024) }; a.abschliessen() }
        let voll = a.geglaettet.tief
        leise.withUnsafeBufferPointer { a.aufnehmen($0.baseAddress!, nil, anzahl: 1024) }
        let nachEinem = a.abschliessen().tief
        #expect(nachEinem < voll)
        #expect(nachEinem > 0.3)                     // fällt wie ein Zeiger, nicht auf einmal
        for _ in 0 ..< 60 { leise.withUnsafeBufferPointer { a.aufnehmen($0.baseAddress!, nil, anzahl: 1024) }; a.abschliessen() }
        #expect(a.geglaettet.tief < 0.01)
        #expect(analysieren(frequenz: 440, pegel: 0).mittel == 0)
    }

    @Test("Leise Musik bewegt die Balken so weit wie laute")
    func leise() {
        let laut = analysieren(frequenz: 60, pegel: 0.8)
        let leise = analysieren(frequenz: 60, pegel: 0.05)
        #expect(abs(laut.tief - leise.tief) < 0.05)
    }

    @Test("Packen und Entpacken verlieren höchstens 1/65535")
    func packen() throws {
        let b = Pegelanalyse.Baender(tief: 0.25, mittel: 1, hoch: 0)
        let zurueck = try #require(Pegelanalyse.entpacken(Pegelanalyse.packen(b)))
        #expect(abs(zurueck.tief - 0.25) < 0.0001)
        #expect(zurueck.mittel == 1)
        #expect(zurueck.hoch == 0)
        #expect(Pegelanalyse.entpacken(0) == nil)
        #expect(Pegelanalyse.entpacken(Pegelanalyse.packen(.still)) == .still)
    }

    // MARK: Farbe des Mini-Players

    @Test("Mini-Player: weiße Schrift und zweite Zeile halten 4,5 : 1", arguments: [
        Farbwert(rot: 1, gruen: 0.9, blau: 0.2),     // Gelb, das Schwierigste
        Farbwert(rot: 0.2, gruen: 1, blau: 0.4),     // Grün
        Farbwert(rot: 0.3, gruen: 0.8, blau: 1),     // Hellblau
        Farbwert(rot: 0.9, gruen: 0.1, blau: 0.1),   // Rot
        Farbwert(rot: 0.62, gruen: 0.62, blau: 0.62), // Grau
        Farbwert(rot: 0.1, gruen: 0.05, blau: 0.4),  // schon dunkel
    ])
    func pillenfarbe(haupt: Farbwert) {
        let f = Huellenton.pillenfarbe(Huellenton.Glut(haupt: haupt, neben: haupt))
        #expect(Huellenton.kontrast(.weiss, f) >= 4.5)
        let zweite = f.ueberdeckt(von: .weiss, deckung: Huellenton.pillenzweitzeile)
        #expect(Huellenton.kontrast(zweite, f) >= 4.5)
        // Der Ton bleibt, wo er farbig war.
        if haupt.hsb.saettigung > 0.3 {
            #expect(abs(f.hsb.farbton - haupt.hsb.farbton) < 0.02)
            #expect(f.hsb.helligkeit > 0.15)
        }
    }

    @Test("Mini-Player-Verlauf: jeder Punkt hält 4,5 : 1, auch durchscheinend vor Weiß hinter dem Glas", arguments: [
        (Farbwert(rot: 1, gruen: 0.9, blau: 0.2), Farbwert(rot: 0.2, gruen: 1, blau: 0.4)),
        (Farbwert(rot: 0.3, gruen: 0.8, blau: 1), Farbwert(rot: 0.9, gruen: 0.1, blau: 0.1)),
        (Farbwert(rot: 0.62, gruen: 0.62, blau: 0.62), Farbwert(rot: 1, gruen: 1, blau: 1)),
        (Farbwert(rot: 0.1, gruen: 0.05, blau: 0.4), Farbwert(rot: 1, gruen: 0.9, blau: 0.2)),
    ])
    func pillenverlauf(_ paar: (Farbwert, Farbwert)) {
        let v = Huellenton.pillenverlauf(Huellenton.Glut(haupt: paar.0, neben: paar.1))
        for i in 0...10 {
            let t = Double(i) / 10
            let f = Farbwert(rot: v.hell.rot + (v.tief.rot - v.hell.rot) * t,
                             gruen: v.hell.gruen + (v.tief.gruen - v.hell.gruen) * t,
                             blau: v.hell.blau + (v.tief.blau - v.hell.blau) * t)
            // Die Fläche deckt nur zu `pillendeckung`; darunter das Glas, dahinter
            // schlimmstenfalls Weiß.
            let g = Huellenton.ueberGlas(f)
            #expect(Huellenton.kontrast(.weiss, g) >= 4.5)
            #expect(Huellenton.kontrast(g.ueberdeckt(von: .weiss, deckung: Huellenton.pillenzweitzeile), g) >= 4.5)
        }
        // Tief ist sichtbar tiefer — höchstens halb so hell.
        #expect(Huellenton.leuchtdichte(v.tief) <= Huellenton.leuchtdichte(v.hell) * 0.5 + 0.0001)
    }

    /// 24.09.: „Man merkt kaum, dass da überhaupt irgendwas ist." Was
    /// hinter der Pille liegt, soll als Unschärfe erkennbar bleiben: von einem
    /// Unterschied dahinter (Schwarz gegen Weiß) kommt wenigstens ein Fünftel
    /// durch — vorher 12 %.
    @Test("Mini-Player: das Glas scheint deutlich durch")
    func durchscheinend() {
        let durch = (1 - Huellenton.pillendeckung) * (1 - Huellenton.glasabdunklung)
        #expect(durch >= 0.2, "nur \(durch)")
        #expect(Huellenton.pillendeckung <= 0.6)
    }

    @Test("Kontrast nach WCAG: Weiß auf Schwarz 21, Weiß auf Weiß 1")
    func kontrast() {
        #expect(abs(Huellenton.kontrast(.weiss, Farbwert(rot: 0, gruen: 0, blau: 0)) - 21) < 0.01)
        #expect(abs(Huellenton.kontrast(.weiss, .weiss) - 1) < 0.0001)
    }
}
