import Foundation

/// **Der Grund hinter der Hülle im Wiedergabeblatt** — die Hülle groß und
/// verschwommen, aber **immer deutlich dunkler als die Hülle selbst**.
///
/// Vorher wurde nur auf eine feste höchste Leuchtdichte (0,09) abgedunkelt.
/// Bei einer roten Hülle stand dann Rot auf fast demselben Rot, die Hülle
/// grenzte sich nicht ab (24.09.). Jetzt richtet sich die Grenze nach
/// der Hülle: der hellste Punkt des Grunds bleibt um ``abstand`` (WCAG-
/// Verhältnis) unter ihrer mittleren Leuchtdichte, und der Grund ist etwas
/// entsättigt. Eine sehr dunkle Hülle lässt sich nicht unterbieten — dort
/// hebt ein neutraler ``boden`` den Grund ein wenig an, damit Schwarz auf
/// Schwarz nicht verschwindet; die feine helle Kante an der Hülle tut den Rest.
///
/// Gerechnet wird linear, auf den kleinen, schon verschwommenen Bildpunkten
/// (RGBA, 8 Bit), einmal je Hülle.
public enum Blattgrund {
    /// Kein Punkt heller als das — Weiß hat darauf wenigstens 7,5 : 1.
    public static let hoechsteLeuchtdichte = 0.09
    /// So weit (Kontrastverhältnis) bleibt der Grund unter der Hülle.
    public static let abstand = 2.4
    /// Wie weit jeder Punkt zum eigenen Grau hin gezogen wird.
    public static let entsaettigung = 0.2
    /// Unter dieser mittleren Leuchtdichte der Hülle wird angehoben.
    public static let dunkelGrenze = 0.03
    /// Die Anhebung bei dunklen Hüllen, als Leuchtdichte.
    public static let boden = 0.025

    /// Die höchste Leuchtdichte, die der Grund bei dieser Hülle haben darf.
    public static func obergrenze(huelle: Double) -> Double {
        min(hoechsteLeuchtdichte, max(0.012, (huelle + 0.05) / abstand - 0.05))
    }

    /// Die mittlere Leuchtdichte von Bildpunkten (RGBA, 8 Bit).
    public static func mittlereLeuchtdichte(_ rgba: [UInt8]) -> Double {
        guard rgba.count >= 4 else { return 0 }
        var summe = 0.0
        var n = 0
        var i = 0
        while i + 3 < rgba.count {
            summe += leuchtdichte(rgba[i], rgba[i + 1], rgba[i + 2])
            n += 1
            i += 4
        }
        return summe / Double(max(n, 1))
    }

    /// **Macht aus den verschwommenen Punkten den Grund**: entsättigt,
    /// abgedunkelt unter die ``obergrenze(huelle:)``, bei dunklen Hüllen
    /// angehoben. Das Alpha wird 255.
    public static func anpassen(_ rgba: inout [UInt8], huelle: Double) {
        let dunkel = huelle < dunkelGrenze
        let grenze = dunkel ? max(obergrenze(huelle: huelle), boden * 2) : obergrenze(huelle: huelle)
        var hoechste = 0.0
        var i = 0
        while i + 3 < rgba.count {
            hoechste = max(hoechste, leuchtdichte(rgba[i], rgba[i + 1], rgba[i + 2]))
            i += 4
        }
        let faktor = min(1, grenze / max(hoechste, 0.0001))
        // Nur so weit anheben, dass die Grenze hält.
        let anhebung = dunkel ? boden : 0
        let rest = anhebung > 0 ? max(0, 1 - anhebung / max(grenze, 0.0001)) : 1
        i = 0
        while i + 3 < rgba.count {
            let r = linear(rgba[i]), g = linear(rgba[i + 1]), b = linear(rgba[i + 2])
            let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
            func umrechnen(_ c: Double) -> UInt8 {
                let grau = c + (l - c) * entsaettigung
                return zurueck(anhebung + grau * faktor * rest)
            }
            rgba[i] = umrechnen(r)
            rgba[i + 1] = umrechnen(g)
            rgba[i + 2] = umrechnen(b)
            rgba[i + 3] = 255
            i += 4
        }
    }

    // MARK: Linear

    static func linear(_ c: UInt8) -> Double {
        let v = Double(c) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func zurueck(_ l: Double) -> UInt8 {
        let l = max(0, min(1, l))
        let v = l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, (v * 255).rounded())))
    }

    static func leuchtdichte(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
        0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
