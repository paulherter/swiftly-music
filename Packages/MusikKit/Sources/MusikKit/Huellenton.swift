import Foundation

/// Eine Farbe mit Anteilen von 0 bis 1.
public struct Farbwert: Hashable, Sendable {
    public let rot: Double
    public let gruen: Double
    public let blau: Double

    public init(rot: Double, gruen: Double, blau: Double) {
        self.rot = rot
        self.gruen = gruen
        self.blau = blau
    }

    /// Farbton, Sättigung und Helligkeit (HSB), je 0 bis 1.
    public var hsb: (farbton: Double, saettigung: Double, helligkeit: Double) {
        let hoch = max(rot, gruen, blau), tief = min(rot, gruen, blau), spanne = hoch - tief
        var farbton = 0.0
        if spanne > 0 {
            switch hoch {
            case rot: farbton = (gruen - blau) / spanne
            case gruen: farbton = 2 + (blau - rot) / spanne
            default: farbton = 4 + (rot - gruen) / spanne
            }
            farbton /= 6
            if farbton < 0 { farbton += 1 }
        }
        return (farbton, hoch > 0 ? spanne / hoch : 0, hoch)
    }

    public init(farbton h: Double, saettigung s: Double, helligkeit v: Double) {
        let h6 = (h - floor(h)) * 6
        let i = Int(h6) % 6
        let f = h6 - floor(h6)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: self.init(rot: v, gruen: t, blau: p)
        case 1: self.init(rot: q, gruen: v, blau: p)
        case 2: self.init(rot: p, gruen: v, blau: t)
        case 3: self.init(rot: p, gruen: q, blau: v)
        case 4: self.init(rot: t, gruen: p, blau: v)
        default: self.init(rot: v, gruen: p, blau: q)
        }
    }
}

/// **Die Farbe, die aus der Hülle leuchtet** — die Glut oben im
/// Wiedergabeblatt.
///
/// Nicht der Mittelwert: der wird bei bunten Hüllen braun. Gezählt wird, welcher
/// Farbton die Hülle trägt — jeder Bildpunkt nach Sättigung und Helligkeit
/// gewichtet, Schwarz und Weiß fallen fast heraus —, und daraus die mittlere
/// Farbe dieses Tons. Die zweite Farbe ist der nächststärkere Ton, dunkler;
/// fehlt einer, derselbe Ton, dunkler.
///
/// Danach geglättet: so hell und so satt, dass es leuchtet, aber nicht so
/// grell, dass die weiße Schrift darüber leidet. Eine graue Hülle ergibt ein
/// graues Leuchten.
public enum Huellenton {

    public struct Glut: Hashable, Sendable {
        public let haupt: Farbwert
        public let neben: Farbwert
    }

    static let faecher = 12

    /// - Parameter rgba: Bildpunkte als RGBA mit 8 Bit je Anteil, Zeile für
    ///   Zeile; das Alpha wird nur zum Aussortieren durchsichtiger Punkte
    ///   gelesen.
    public static func glut(rgba: [UInt8]) -> Glut? {
        guard rgba.count >= 4 else { return nil }
        var gewicht = [Double](repeating: 0, count: faecher + 1)   // letztes Fach: grau
        var summe = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: faecher + 1)

        var i = 0
        while i + 3 < rgba.count {
            defer { i += 4 }
            guard rgba[i + 3] > 32 else { continue }
            let f = Farbwert(rot: Double(rgba[i]) / 255, gruen: Double(rgba[i + 1]) / 255,
                             blau: Double(rgba[i + 2]) / 255)
            let (h, s, v) = f.hsb
            // Fast Schwarz trägt keine Farbe.
            guard v > 0.08 else { continue }
            let fach: Int
            let w: Double
            if s < 0.12 {
                fach = faecher
                w = 0.15 * v
            } else {
                fach = min(Int(h * Double(faecher)), faecher - 1)
                w = s * v
            }
            gewicht[fach] += w
            summe[fach].r += f.rot * w
            summe[fach].g += f.gruen * w
            summe[fach].b += f.blau * w
        }

        let reihenfolge = gewicht.indices.sorted { gewicht[$0] > gewicht[$1] }
        guard let erstes = reihenfolge.first, gewicht[erstes] > 0 else { return nil }

        func mittel(_ fach: Int) -> Farbwert {
            let g = gewicht[fach]
            return Farbwert(rot: summe[fach].r / g, gruen: summe[fach].g / g, blau: summe[fach].b / g)
        }

        let haupt = glaetten(mittel(erstes), neben: false)
        // Der zweite Ton zählt, wenn er wenigstens ein Fünftel des ersten trägt
        // und kein Grau ist.
        let zweites = reihenfolge.dropFirst().first {
            $0 != faecher && gewicht[$0] >= gewicht[erstes] * 0.2
        }
        let neben = zweites.map { glaetten(mittel($0), neben: true) }
            ?? glaetten(mittel(erstes), neben: true)
        return Glut(haupt: haupt, neben: neben)
    }

    /// Hell und satt genug zum Leuchten, nicht so sehr, dass es blendet.
    static func glaetten(_ farbe: Farbwert, neben: Bool) -> Farbwert {
        let (h, s, _) = farbe.hsb
        let grau = s < 0.12
        let saettigung = grau ? s : min(max(s, 0.45), 0.78)
        let helligkeit = neben ? 0.40 : 0.78
        return Farbwert(farbton: h, saettigung: saettigung, helligkeit: grau ? helligkeit * 0.8 : helligkeit)
    }

    // MARK: Die Farbe des Mini-Players

    /// Wie stark die zweite Zeile im Mini-Player auf der Farbe deckt (Weiß).
    public static let pillenzweitzeile = 0.72
    /// WCAG AA für Text unter 18 pt.
    public static let mindestkontrast = 4.5
    /// **Wie weit der Verlauf des Mini-Players deckt** — darunter liegt das
    /// Glas: Unschärfe und ``glasabdunklung`` (24.09.: bei 88 % merkte
    /// man kaum, dass da etwas ist). Die Hälfte des Verlaufs, und was hinter
    /// der Pille liegt, scheint als Unschärfe durch.
    public static let pillendeckung = 0.5
    /// **Wie weit das Glas unter dem Verlauf abdunkelt** (Schwarz). Der
    /// Kontrast kommt daher, nicht aus der Deckkraft: gerechnet wird, als
    /// stünde hinter dem Glas Weiß.
    public static let glasabdunklung = 0.55

    /// Was schlimmstenfalls durch den Verlauf scheint: Weiß hinter dem Glas.
    public static var hinterGlas: Farbwert {
        let v = 1 - glasabdunklung
        return Farbwert(rot: v, gruen: v, blau: v)
    }

    /// Die Fläche, wie sie über dem Glas steht, wenn dahinter Weiß liegt.
    public static func ueberGlas(_ f: Farbwert) -> Farbwert {
        f.ueberdeckt(von: hinterGlas, deckung: 1 - pillendeckung)
    }

    /// **Die Fläche des Mini-Players in der Farbe der Hülle** (wie Spotify):
    /// derselbe Ton wie die Glut, gedämpft und so weit abgedunkelt, dass
    /// weiße Schrift **und** die zweite Zeile (Weiß zu 72 %) wenigstens
    /// 4,5 : 1 gegen die Fläche haben. Gerechnet, nicht geschätzt: in
    /// Schritten von 2 % Helligkeit nach unten, bis beides hält.
    public static func pillenfarbe(_ glut: Glut) -> Farbwert {
        lesbar(glut.haupt, hoechstens: 0.52)
    }

    /// **Der Verlauf des Mini-Players** (24.09.: einfarbig wirkt es
    /// „wack"): wie die Glut im Blatt aus zwei Tönen der Hülle — an der
    /// Hülle die Pillenfarbe, zum rechten Rand der Nebenton, tiefer. Beide
    /// Enden halten 4,5 : 1 für Weiß und die zweite Zeile, und damit jeder
    /// Punkt dazwischen: gemischt wird im sRGB-Raum, und die Leuchtdichte
    /// einer Mischung liegt nie über der des helleren Endes.
    public struct Pillenverlauf: Hashable, Sendable {
        public let hell: Farbwert
        public let tief: Farbwert
    }

    public static func pillenverlauf(_ glut: Glut) -> Pillenverlauf {
        let hell = pillenfarbe(glut)
        // Nie heller als das helle Ende — sonst kippte der Verlauf. Gemessen
        // an der Leuchtdichte: Gelb ist bei gleicher Helligkeit viel heller
        // als Blau.
        // **Sichtbar verlaufen** (24.09.: „fast einfarbig"): das tiefe
        // Ende höchstens halb so hell wie das helle — vorher 80 %.
        return Pillenverlauf(hell: hell, tief: lesbar(glut.neben, hoechstens: 0.26,
                                                      leuchtdichte: leuchtdichte(hell) * 0.5))
    }

    /// Derselbe Ton, gedämpft und in Schritten von 2 % Helligkeit
    /// abgedunkelt, bis weiße Schrift **und** die zweite Zeile (Weiß zu
    /// 72 %) wenigstens 4,5 : 1 haben — auf der Farbe, wie sie zu
    /// ``pillendeckung`` über dem Glas steht, hinter dem Weiß liegt
    /// (``ueberGlas(_:)``). Gerechnet, nicht geschätzt.
    static func lesbar(_ farbe: Farbwert, hoechstens: Double, leuchtdichte grenze: Double = 1) -> Farbwert {
        let (h, s, v) = farbe.hsb
        let saettigung = min(s, 0.72)
        var helligkeit = min(v, hoechstens)
        while helligkeit > 0 {
            let f = Farbwert(farbton: h, saettigung: saettigung, helligkeit: helligkeit)
            let grund = ueberGlas(f)
            if kontrast(.weiss, grund) >= mindestkontrast,
               kontrast(grund.ueberdeckt(von: .weiss, deckung: pillenzweitzeile), grund) >= mindestkontrast,
               leuchtdichte(f) <= grenze {
                return f
            }
            helligkeit -= 0.02
        }
        return Farbwert(rot: 0, gruen: 0, blau: 0)
    }

    /// Relative Leuchtdichte nach WCAG 2.1.
    public static func leuchtdichte(_ f: Farbwert) -> Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(f.rot) + 0.7152 * linear(f.gruen) + 0.0722 * linear(f.blau)
    }

    /// Kontrastverhältnis nach WCAG 2.1, 1 bis 21.
    public static func kontrast(_ a: Farbwert, _ b: Farbwert) -> Double {
        let la = leuchtdichte(a), lb = leuchtdichte(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

public extension Farbwert {
    static let weiss = Farbwert(rot: 1, gruen: 1, blau: 1)

    /// Diese Farbe, zu `deckung` von `oben` überdeckt.
    func ueberdeckt(von oben: Farbwert, deckung: Double) -> Farbwert {
        Farbwert(rot: rot + (oben.rot - rot) * deckung,
                 gruen: gruen + (oben.gruen - gruen) * deckung,
                 blau: blau + (oben.blau - blau) * deckung)
    }
}
