import Foundation

/// **Die Zahlen hinter den Seiten in der Farbe ihrer Hülle** — Album,
/// Playlist, Hörbuch, Künstler und die Lieblingssongs (24.09.: „die
/// ganze Seite so eine Farbe davon").
///
/// Hinter der Seite liegt die verschwommene Hülle aus dem Player
/// (`Blattbilder`: keine Stelle heller als ``hoechsteLeuchtdichte``). Darüber
/// ein Schleier aus `grund`, der mit dem Inhalt scrollt: oben dünn, wo nur
/// Pfeil und „Mehr" stehen, ab dem Titel ``schleierText``, und über etwa eine
/// Bildschirmhöhe in `grund` aus. Hier stehen die Zahlen, weil der Kontrast
/// gegen sie gerechnet und getestet wird (`SeitenfarbeTests`) — die Ansicht
/// liest sie nur.
public enum Seitenfarbe {

    /// Die hellste Stelle des verschwommenen Bilds (`Blattbilder` im
    /// Wiedergabeblatt). Die Ansicht prüft beim Start, dass es dabei bleibt.
    public static let hoechsteLeuchtdichte = 0.09

    /// Der Schleier über dem Bild, wo keine Schrift steht — oben hinter
    /// Pfeil und „Mehr" (weiße Zeichen, 7,5 : 1 schon ohne Schleier, hier
    /// noch 8 : 1 — reichlich Raum, den Rest der eigenen Farbe zu lassen).
    /// Vorher 0,12 (25.09.: „sieht man jetzt echt ganz wenig" bei
    /// blassen Covern) — nur noch halb so dicht.
    public static let schleierOben = 0.06

    /// **Der Schleier, wo Schrift steht**: ab dem Titel bis zum Ausklang.
    /// Gerechnet für die leiseste Stufe, `schriftSehrLeise` (Nummern,
    /// Angaben): im ungünstigsten Ton 4,65 : 1. Gebraucht wären 0,52 — vorher
    /// 0,60 (4,88 : 1), 25.09.: weniger Abdunklung, damit die Farbe der
    /// Seite deutlicher trägt.
    public static let schleierText = 0.55

    /// Über wie viele Punkte der Schleier vor dem Titel von oben auf
    /// ``schleierText`` steigt.
    public static let anstieg = 110.0

    /// Ab welchem Anteil der Seitenhöhe die Farbe in `grund` ausklingt; bei
    /// 1,0 ist sie ganz weg — eine Bildschirmhöhe unter dem oberen Rand.
    public static let ausklangAb = 0.5

    /// **Das Bild wandert langsamer als die Seite** — 70 % ihres Wegs.
    /// Der Schleier geht 1 : 1 mit, damit er immer unter der Schrift liegt,
    /// für die er gerechnet ist.
    public static let mitlauf = 0.7

    /// **Wie weit der Schleier verschoben steht** — 1 : 1 mit dem Inhalt nach
    /// oben (`-versatz`), aber beim Überziehen am oberen Rand (`versatz` <
    /// 0) nie nach unten über seine Ruhelage hinaus: sonst zieht sich seine
    /// Oberkante vom Bildrand weg und reißt dort eine harte, graue Kante auf
    /// (25.09.). Die Klammer hält die Oberkante immer bei `y <= 0` —
    /// unabhängig davon, wie weit `versatz` dem echten Überzug hinterherhinkt
    /// (er kommt aus dem Zustand, einen Bildaufbau spät).
    public static func schleieroberkante(versatz: CGFloat) -> CGFloat {
        min(-versatz, 0)
    }

    /// Weiß über der laufenden Zeile — durchscheinend statt `erhoeht`,
    /// damit die Farbe der Seite durchkommt.
    public static let laufend = 0.08
    /// Weiß über einer gedrückten Zeile.
    public static let gedrueckt = 0.08

    /// **Wie dicht der Schleier `y` Punkt unter dem oberen Rand der Seite
    /// deckt** (0 bis 1). `textAb`: wo die erste Schrift stehen kann;
    /// `hoehe`: die sichtbare Höhe der Seite.
    public static func schleier(bei y: Double, textAb: Double, hoehe: Double) -> Double {
        let ausklang = max(textAb, hoehe * ausklangAb)
        if y >= ausklang {
            let ende = max(hoehe, ausklang + 1)
            return schleierText + (1 - schleierText) * weich((y - ausklang) / (ende - ausklang))
        }
        if y >= textAb { return schleierText }
        let anfang = textAb - anstieg
        guard y > anfang else { return schleierOben }
        return schleierOben + (schleierText - schleierOben) * weich((y - anfang) / anstieg)
    }

    /// Weich an beiden Enden (smoothstep) — keine Kante, wo der Anstieg
    /// beginnt oder aufhört.
    static func weich(_ t: Double) -> Double {
        let u = min(max(t, 0), 1)
        return u * u * (3 - 2 * u)
    }

    // MARK: Lieblingssongs

    /// **Die Lieblingssongs haben keine Hülle, sondern die Farbe von Swiftly**:
    /// `akzent` (#50D5DA) in ein tiefes Blaugrün. Sonst steht der Akzent nur
    /// für Zustand (BRAND.md); hier ist er das Kennzeichen der eigenen
    /// Sammlung — dieselbe Kachel in der Bibliothek und im Kopf der Seite.
    public static let kachelHell = Farbwert(rot: 0x50 / 255, gruen: 0xD5 / 255, blau: 0xDA / 255)   // #50D5DA
    public static let kachelMitte = Farbwert(rot: 0x16 / 255, gruen: 0x7E / 255, blau: 0x8C / 255)  // #167E8C
    public static let kachelTief = Farbwert(rot: 0x07 / 255, gruen: 0x2F / 255, blau: 0x3A / 255)   // #072F3A

    /// **Der Hintergrund der Seite** statt der verschwommenen Hülle: eine
    /// Glut im Blaugrün des Akzents, ein zweiter, bläulicher Schein, der
    /// Grund dazwischen tief. Alle drei unter ``hoechsteLeuchtdichte``,
    /// damit derselbe Schleier dieselbe Lesbarkeit liefert.
    public static let glut = Farbwert(rot: 0x1A / 255, gruen: 0x5A / 255, blau: 0x5E / 255)         // #1A5A5E
    public static let schein = Farbwert(rot: 0x12 / 255, gruen: 0x3E / 255, blau: 0x5A / 255)       // #123E5A
    public static let glutgrund = Farbwert(rot: 0x06 / 255, gruen: 0x28 / 255, blau: 0x2C / 255)    // #06282C

    // MARK: Der lebendigste Ton eines Covers

    /// **Ein Ton statt eines Bilds** — für den Schleier der Detailleiste und
    /// eine leichte Tönung über blassen Covern.
    public struct Seitenton: Hashable, Sendable {
        public let farbe: Farbwert
        /// Wie stark er über dem Bild liegt — 0 bei einem kräftigen Cover.
        public let deckung: Double
    }

    /// Unter dieser Sättigung im kräftigsten Fach gilt ein Cover als blass.
    public static let grauSchwelle = 0.12
    /// **Ein ruhiger, nicht toter Ton** für Cover ohne kräftigen Farbton
    /// (24.09.: „leicht getönt statt grau" statt totem Grau) — ein
    /// sanftes, leicht dunkles Blaugrau mit Tiefe. Kräftiger als zuerst
    /// (0,22): bei blassen Covern trug die Farbe zu wenig (25.09.).
    public static let ruhigerFarbton = 0.58
    public static let ruhigeSaettigung = 0.32
    /// Wie stark die Tönung höchstens über einem wirklich blassen Cover
    /// liegt — vorher 0,4, 25.09.: „sieht man jetzt echt ganz wenig",
    /// die Tönung darf ein blasses Cover deutlich tragen.
    public static let toenungHoechstdeckung = 0.6

    /// **Der lebendigste Ton eines Covers** — jeder Bildpunkt nach Sättigung
    /// gewichtet, in eines von zwölf Fächern nach Farbton (wie
    /// `Huellenton.glut`, das für den Player nach Sättigung × Helligkeit
    /// gewichtet — hier nach Sättigung × Anteil, nicht angetastet). Bevorzugt
    /// den kräftigsten Ton statt des Durchschnitts, der ein blasses Cover
    /// sonst trist wirken ließ (24.09.).
    public static func lebendigsterTon(rgba: [UInt8]) -> Farbwert? {
        let faecher = 12
        var gewicht = [Double](repeating: 0, count: faecher)
        var summe = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: faecher)
        var i = 0
        while i + 3 < rgba.count {
            defer { i += 4 }
            guard rgba[i + 3] > 32 else { continue }
            let f = Farbwert(rot: Double(rgba[i]) / 255, gruen: Double(rgba[i + 1]) / 255,
                             blau: Double(rgba[i + 2]) / 255)
            let (h, s, v) = f.hsb
            guard v > 0.08, s >= 0.05 else { continue }
            let fach = min(Int(h * Double(faecher)), faecher - 1)
            gewicht[fach] += s
            summe[fach].r += f.rot * s
            summe[fach].g += f.gruen * s
            summe[fach].b += f.blau * s
        }
        guard let staerkstes = gewicht.indices.max(by: { gewicht[$0] < gewicht[$1] }), gewicht[staerkstes] > 0
        else { return nil }
        let g = gewicht[staerkstes]
        return Farbwert(rot: summe[staerkstes].r / g, gruen: summe[staerkstes].g / g, blau: summe[staerkstes].b / g)
    }

    /// **Die Seitenfarbe aus einem Cover**: der lebendigste Ton, behutsam
    /// gesättigter; ohne kräftigen Ton der ``ruhigerFarbton``. Auf
    /// ``hoechsteLeuchtdichte`` gebracht wie das verschwommene Bild — linear,
    /// wie in `SeitenfarbeTests` —, damit er darüber gemischt dieselbe
    /// Lesbarkeit hält. Die Deckung wächst, je blasser das Cover war.
    public static func seitenton(rgba: [UInt8]) -> Seitenton {
        let roh = lebendigsterTon(rgba: rgba)
        let rohSaettigung = roh?.hsb.saettigung ?? 0
        let (h, s): (Double, Double) = {
            guard let roh, rohSaettigung >= grauSchwelle else { return (ruhigerFarbton, ruhigeSaettigung) }
            return (roh.hsb.farbton, min(1, rohSaettigung * 1.25))
        }()
        let voll = Farbwert(farbton: h, saettigung: s, helligkeit: 1)
        let faktor = min(1, hoechsteLeuchtdichte / max(Huellenton.leuchtdichte(voll), 0.0001))
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func kodiert(_ l: Double) -> Double { l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055 }
        let farbe = Farbwert(rot: kodiert(linear(voll.rot) * faktor),
                             gruen: kodiert(linear(voll.gruen) * faktor),
                             blau: kodiert(linear(voll.blau) * faktor))
        let schwelle = grauSchwelle * 2
        let deckung = rohSaettigung >= schwelle ? 0 : toenungHoechstdeckung * (1 - rohSaettigung / schwelle)
        return Seitenton(farbe: farbe, deckung: deckung)
    }
}
