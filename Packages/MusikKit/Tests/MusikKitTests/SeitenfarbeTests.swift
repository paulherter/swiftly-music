import Foundation
import Testing
@testable import MusikKit

/// **Die Seite in der Farbe ihrer Hülle bleibt lesbar** — für jeden Ton, den
/// das verschwommene Bild haben kann: jeder Farbton und jede Sättigung, so
/// weit abgedunkelt wie in `Blattbilder` (die hellste Stelle auf
/// Leuchtdichte 0,09). Gemischt wird im sRGB-Raum wie beim Zeichnen.
@Suite("Seitenfarbe")
struct SeitenfarbeTests {

    private static let grund = Farbwert(rot: 0x10 / 255, gruen: 0x10 / 255, blau: 0x10 / 255)
    private static let schriftLeise = Farbwert(rot: 0.8, gruen: 0.8, blau: 0.8)
    private static let schriftSehrLeise = Farbwert(rot: 0.596, gruen: 0.596, blau: 0.596)

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func kodiert(_ l: Double) -> Double {
        l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
    }

    /// Jeder Ton, so hell, wie das Bild höchstens wird — linear abgedunkelt
    /// wie in `Blattbilder.verwischen`.
    private static var hellsteToene: [Farbwert] {
        var toene: [Farbwert] = []
        for h in stride(from: 0.0, to: 1, by: 1.0 / 180) {
            for s in stride(from: 0.0, through: 1, by: 0.05) {
                let f = Farbwert(farbton: h, saettigung: s, helligkeit: 1)
                let faktor = min(1, Seitenfarbe.hoechsteLeuchtdichte / Huellenton.leuchtdichte(f))
                toene.append(Farbwert(rot: kodiert(linear(f.rot) * faktor),
                                      gruen: kodiert(linear(f.gruen) * faktor),
                                      blau: kodiert(linear(f.blau) * faktor)))
            }
        }
        return toene
    }

    @Test("Unter dem Schleier: alle drei Schriftstufen wenigstens 4,5 : 1")
    func schriftAufDerSeite() {
        var engster = Double.infinity
        for ton in Self.hellsteToene {
            let seite = ton.ueberdeckt(von: Self.grund, deckung: Seitenfarbe.schleierText)
            engster = min(engster, Huellenton.kontrast(Self.schriftSehrLeise, seite))
            #expect(Huellenton.kontrast(.weiss, seite) >= Huellenton.mindestkontrast)
            #expect(Huellenton.kontrast(Self.schriftLeise, seite) >= Huellenton.mindestkontrast)
        }
        #expect(engster >= Huellenton.mindestkontrast)
    }

    @Test("Laufende und gedrückte Zeile: Weiß und schriftLeise halten")
    func schriftAufDerZeile() {
        for ton in Self.hellsteToene {
            let seite = ton.ueberdeckt(von: Self.grund, deckung: Seitenfarbe.schleierText)
            let laufend = seite.ueberdeckt(von: .weiss, deckung: Seitenfarbe.laufend)
            #expect(Huellenton.kontrast(.weiss, laufend) >= Huellenton.mindestkontrast)
            #expect(Huellenton.kontrast(Self.schriftLeise, laufend) >= Huellenton.mindestkontrast)
            // Gedrückt auf der laufenden Zeile — beides übereinander.
            let beides = laufend.ueberdeckt(von: .weiss, deckung: Seitenfarbe.gedrueckt)
            #expect(Huellenton.kontrast(.weiss, beides) >= Huellenton.mindestkontrast)
        }
    }

    @Test("Ohne Schleier trägt das Bild noch Weiß — oben hinter Pfeil und „Mehr“")
    func weissOhneSchleier() {
        for ton in Self.hellsteToene {
            #expect(Huellenton.kontrast(.weiss, ton.ueberdeckt(von: Self.grund, deckung: Seitenfarbe.schleierOben))
                    >= Huellenton.mindestkontrast)
        }
    }

    @Test("Ab dem Titel deckt der Schleier nie weniger, und am Ende ganz")
    func schleierverlauf() {
        for (textAb, hoehe) in [(150.0, 852.0), (190.0, 852.0), (150.0, 667.0), (150.0, 1366.0), (300.0, 400.0)] {
            var vorher = 0.0
            for y in stride(from: 0.0, through: hoehe * 1.5, by: 1) {
                let d = Seitenfarbe.schleier(bei: y, textAb: textAb, hoehe: hoehe)
                #expect(d >= vorher - 1e-9, "fällt bei \(y)")
                if y >= textAb { #expect(d >= Seitenfarbe.schleierText - 1e-9) }
                vorher = d
            }
            #expect(Seitenfarbe.schleier(bei: 0, textAb: textAb, hoehe: hoehe) == Seitenfarbe.schleierOben)
            #expect(Seitenfarbe.schleier(bei: max(hoehe, textAb + 1), textAb: textAb, hoehe: hoehe) >= 0.999)
        }
    }

    @Test("Die Glut der Lieblingssongs ist nicht heller als ein verschwommenes Bild")
    func lieblingsglut() {
        for ton in [Seitenfarbe.glut, Seitenfarbe.schein, Seitenfarbe.glutgrund] {
            #expect(Huellenton.leuchtdichte(ton) <= Seitenfarbe.hoechsteLeuchtdichte)
        }
    }

    /// **Keine Ebene über dem Hintergrund reißt beim Überziehen eine Kante
    /// auf** — nachgerechnet für 0, 80 und 200 Punkt Überzug am oberen Rand
    /// (25.09.). `versatz` ist beim Überziehen negativ (Betrag =
    /// Überzug); die Oberkante von Schleier (``Seitenfarbe/
    /// schleieroberkante(versatz:)``) und Bild (dieselbe Regel wie in
    /// `Seitenhintergrund.flaeche`: 0 statt `-versatz * mitlauf`, solange
    /// `versatz` nicht positiv ist) müssen beide bei `y <= 0` bleiben, sonst
    /// zeigt sich darunter der jeweils nächste Layer als harte Kante. Ruhende
    /// und normal nach oben gescrollte Lagen (`versatz >= 0`) bleiben dabei
    /// unverändert 1 : 1 mit dem Inhalt.
    @Test("Schleier und Bild reichen beim Überziehen immer bis y <= 0", arguments: [0.0, 80.0, 200.0])
    func keineKanteBeimUeberziehen(ueberzug: Double) {
        let versatz = CGFloat(-ueberzug)
        let schleieroberkante = Seitenfarbe.schleieroberkante(versatz: versatz)
        #expect(schleieroberkante <= 0)
        #expect(schleieroberkante == 0, "ruht nicht an der Bildoberkante, obwohl y 0 nie unterschritten werden darf")

        let bildoberkante: CGFloat = versatz > 0 ? -versatz * CGFloat(Seitenfarbe.mitlauf) : 0
        #expect(bildoberkante <= 0)
    }

    @Test("Schleier bleibt beim normalen Scrollen 1 : 1 mit dem Inhalt", arguments: [0.0, 40.0, 500.0])
    func schleierFolgtNormalemScrollen(versatz: Double) {
        #expect(Seitenfarbe.schleieroberkante(versatz: CGFloat(versatz)) == CGFloat(-versatz))
    }

    // MARK: Blasse und graue Cover

    /// `n` gleiche Bildpunkte (RGBA, 8 Bit) — ein Cover aus einer Farbe.
    private static func einfarbig(_ r: UInt8, _ g: UInt8, _ b: UInt8, anzahl: Int = 64) -> [UInt8] {
        var rgba = [UInt8]()
        rgba.reserveCapacity(anzahl * 4)
        for _ in 0 ..< anzahl { rgba.append(contentsOf: [r, g, b, 255]) }
        return rgba
    }

    @Test("Ein helles und ein graues Cover bekommen einen Ton, keinen toten Grauwert")
    func hellesUndGrauesCover() {
        // Fast weiß, und mittleres Grau — beide ohne kräftigen Farbton.
        for rgba in [Self.einfarbig(245, 245, 245), Self.einfarbig(120, 120, 120), Self.einfarbig(20, 20, 20)] {
            let ton = Seitenfarbe.seitenton(rgba: rgba)
            #expect(ton.deckung > 0)
            #expect(ton.farbe.hsb.saettigung > 0.05, "wirkt sonst tot statt ruhig")
            #expect(Huellenton.leuchtdichte(ton.farbe) <= Seitenfarbe.hoechsteLeuchtdichte + 1e-9)
        }
    }

    @Test("Ein kräftiges Cover bekommt seinen eigenen Ton, kaum Tönung")
    func kraeftigesCover() {
        // Sattes Rot: der lebendigste Ton trifft ungefähr den Farbton wieder.
        let rgba = Self.einfarbig(220, 30, 30)
        let ton = Seitenfarbe.seitenton(rgba: rgba)
        #expect(ton.deckung < 0.05)
        #expect(abs(ton.farbe.hsb.farbton - Farbwert(rot: 220 / 255, gruen: 30 / 255, blau: 30 / 255).hsb.farbton) < 0.05)
    }

    @Test("Die Tönung eines blassen Covers bleibt über jedem Ton lesbar")
    func toenungBleibtLesbar() {
        let ton = Seitenfarbe.seitenton(rgba: Self.einfarbig(245, 245, 245))
        for basis in Self.hellsteToene {
            let seite = basis.ueberdeckt(von: ton.farbe, deckung: ton.deckung)
                              .ueberdeckt(von: Self.grund, deckung: Seitenfarbe.schleierText)
            #expect(Huellenton.kontrast(.weiss, seite) >= Huellenton.mindestkontrast)
            #expect(Huellenton.kontrast(Self.schriftSehrLeise, seite) >= Huellenton.mindestkontrast)
        }
    }

    /// **Ein blasses Cover trägt deutlich Farbe** (25.09.: „sieht man
    /// jetzt echt ganz wenig" — vorher 0,4 höchstens, 0,22 Sättigung). Die
    /// Tönung ist jetzt die Mehrheit der Fläche, nicht nur ein Hauch.
    @Test("Die Tönung eines blassen Covers ist deutlich, nicht nur ein Hauch")
    func toenungIstDeutlich() {
        let ton = Seitenfarbe.seitenton(rgba: Self.einfarbig(245, 245, 245))
        #expect(ton.deckung >= 0.5)
        #expect(ton.farbe.hsb.saettigung >= 0.3)
    }

    /// **Weniger Abdunklung oben, auch über einem getönten, blassen Cover**
    /// (25.09.) — der Schleier ganz oben lässt Pfeil und „Mehr" auf
    /// dem getönten Hintergrund lesbar, mit derselben Rechnung wie
    /// ``weissOhneSchleier``, aber über der Tönung statt über dem nackten Bild.
    @Test("Oben, mit der Tönung eines blassen Covers, trägt Weiß noch 4,5 : 1")
    func weissObenMitToenung() {
        let ton = Seitenfarbe.seitenton(rgba: Self.einfarbig(245, 245, 245))
        for basis in Self.hellsteToene {
            let seite = basis.ueberdeckt(von: ton.farbe, deckung: ton.deckung)
                              .ueberdeckt(von: Self.grund, deckung: Seitenfarbe.schleierOben)
            #expect(Huellenton.kontrast(.weiss, seite) >= Huellenton.mindestkontrast)
        }
    }
}
