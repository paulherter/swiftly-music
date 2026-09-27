import MusikKit
import SwiftUI
import UIKit

/// **Maße, Schrift und Bewegung von Swiftly Music.**
///
/// Die Farben kommen unverändert aus `Sources/Shared/Farben.swift` (`Stil`),
/// die übrigen Werte aus der Übergabe (`Notizen/SwiftlyMusic/UEBERGABE.md`
/// §1–7). Wo ein Wert aus Swiftly Player stammt, steht dessen Stelle in
/// `Sources/Shared/Stil.swift` daneben — dort ist er begründet. Nachgebaut
/// statt geteilt, weil `Stil.swift` nicht ohne `AppModel` übersetzt.
///
/// Ein eigener Name statt einer Erweiterung von `Stil`: kommt dort später
/// ein gleichnamiger Wert dazu, bricht dieses Ziel sonst an einer doppelten
/// Erklärung.
enum Musikstil {

    // MARK: Farbe

    /// **Die einzige neue Stufe:** gesungene Liedtextzeilen (Übergabe §1).
    static let gesungen = Color(red: 0x5C / 255, green: 0x5C / 255, blue: 0x5C / 255)   // #5C5C5C
    /// Die Spur unter jedem Fortschritt.
    static let spur = Color.white.opacity(0.30)
    /// Fläche unter dem Leistenglas und den Marken.
    static let schleier = Stil.grund.opacity(0.78)

    /// **Dahinter Schwarz** (Übergabe §6): die Seite hinter dem
    /// Wiedergabeblatt verschwindet beim Aufziehen nicht in `Stil.grund`
    /// (#101010), sondern in diesem etwas dunkleren Ton — kein Wert aus dem
    /// Player, deshalb hier und nicht in `Sources/Shared/Farben.swift`.
    static let blattgrund = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255)   // #0A0A0A

    /// **Der Verlauf des Mini-Players** (``Huellenton/pillenverlauf(_:)``):
    /// radial um die Mitte der Hülle (9 + 20 Punkt vom linken Rand), bis
    /// kurz vor den rechten Rand. `rahmen` ist die Pille in der Fläche
    /// `groesse`, die gefüllt wird — im Mini-Player die Pille selbst, im
    /// wachsenden Blatt der ganze Schirm.
    static func pillenverlauf(_ glut: Huellenton.Glut?, rahmen: CGRect, in groesse: CGSize) -> AnyShapeStyle {
        guard let glut else { return AnyShapeStyle(Stil.flaeche) }
        let v = Huellenton.pillenverlauf(glut)
        let mitte = UnitPoint(x: (rahmen.minX + min(29, rahmen.width / 2)) / max(groesse.width, 1),
                              y: rahmen.midY / max(groesse.height, 1))
        return AnyShapeStyle(RadialGradient(colors: [farbe(v.hell), farbe(v.tief)], center: mitte,
                                            startRadius: 0, endRadius: max(rahmen.width * 0.95, 1)))
    }

    private static func farbe(_ f: Farbwert) -> Color {
        Color(red: f.rot, green: f.gruen, blue: f.blau)
    }

    /// Die zweite Zeile im Mini-Player: auf der Farbe Weiß zu 72 % (dafür
    /// ist der Kontrast gerechnet), auf `flaeche` wie überall `schriftSehrLeise`.
    static func pillenzweitzeile(_ glut: Huellenton.Glut?) -> Color {
        glut == nil ? Stil.schriftSehrLeise : Color.white.opacity(Huellenton.pillenzweitzeile)
    }

    // MARK: Raum (§3)

    static let rand: CGFloat = 18
    static let kachelAbstand: CGFloat = 12
    static let rasterZeile: CGFloat = 20
    static let reihenAbstand: CGFloat = 28
    static let reihentitelAbstand: CGFloat = 12
    /// Die Zeilenhöhe der Reihenüberschrift (20 Semibold) — fest, damit die
    /// Kacheln darunter auf Start und in der Bibliothek auf derselben Höhe
    /// stehen („rund 24" in `HomeView.reihenhoehe`).
    static let reihentitelHoehe: CGFloat = 24
    /// Nur noch die Vorgabe, solange die Breite nicht gemessen ist.
    static let kachel: CGFloat = 112

    /// **Eine Kachel ist ein Drittel der Breite** — in der Reihe wie im
    /// Raster. Die Reihe stand fest bei 112, das Raster teilte die Breite in
    /// drei (auf 393 Punkt 111): dieselbe Hülle sprang beim Wechsel zwischen
    /// Start und Bibliothek um einen Punkt in Größe und Lage. Jetzt rechnen
    /// beide mit derselben Kante, und das Raster hat feste Spalten.
    static func kachelkante(breite: CGFloat) -> CGFloat {
        guard breite > 0 else { return kachel }
        return max(96, (breite - 2 * rand - 2 * kachelAbstand) / 3)
    }

    /// **Eine Bildgröße für alle Kacheln** — Reihe, Raster, „Zuletzt gehört"
    /// und Mosaik. Jede Größe ist eine eigene Adresse; mit einer trifft der
    /// gemeinsame Speicher, wo dieselbe Hülle zum zweiten Mal steht.
    static let kachelbild: CGFloat = 120

    // MARK: Ecken (§3) — durchgehend `.continuous`

    static let eckeKachel: CGFloat = 10
    static let eckeKnopf: CGFloat = 10
    static let eckeKlein: CGFloat = 8
    static let eckeMini: CGFloat = 14
    static let eckeBlatt: CGFloat = 28
    static let eckeHuelleGross: CGFloat = 16
    /// Ein Eingabefeld — das Suchfeld (`Stil.eckeFeld`).
    static let eckeFeld: CGFloat = 12

    // MARK: Schrift (§2)

    static let seitentitel = Font.system(size: 28, weight: .bold)
    static let sperrungSeitentitel: CGFloat = 28 * -0.021
    static let blattTitel = Font.system(size: 22, weight: .semibold)
    static let sperrungBlattTitel: CGFloat = 22 * -0.014
    static let reihe = Font.system(size: 20, weight: .semibold)
    static let sperrungReihe: CGFloat = 20 * -0.012
    static let zeile = Font.system(size: 15, weight: .semibold)
    static let dauer = Font.system(size: 15)
    static let treffer = Font.system(size: 15, weight: .medium)
    /// Fließtext, also 15 — wie das Suchfeld im Player (vorher 17).
    static let suchfeld = Font.system(size: 15)
    static let kacheltitel = Font.system(size: 13, weight: .medium)
    /// 13 Medium wie `Wahlchip` im Player.
    static let kapsel = Font.system(size: 13, weight: .medium)
    static let plakette = Font.system(size: 13, weight: .medium)
    static let angabe = Font.system(size: 12)
    /// „Zuletzt gehört": vier Spalten, Titel 12 Medium, Art 11 (Übergabe §4).
    static let kleinkachelTitel = Font.system(size: 12, weight: .medium)
    static let kleinkachelArt = Font.system(size: 11)
    static let leiste = Font.system(size: 10, weight: .medium)

    /// **Zeilenhöhe 1,16 im Liedtext** (Übergabe §2): der Abstand, der zur
    /// natürlichen Zeilenhöhe der Systemschrift fehlt oder zu viel ist — bei
    /// 28 Bold liegt sie über 1,16, der Wert ist also negativ und rückt
    /// umbrochene Zeilen zusammen.
    static let liedtextZeilenabstand: CGFloat =
        28 * 1.16 - UIFont.systemFont(ofSize: 28, weight: .bold).lineHeight

    // MARK: Bewegung — wie `Stil.swift` :15–70 (BRAND.md §6)

    @MainActor static var bewegungReduziert: Bool { UIAccessibility.isReduceMotionEnabled }
    static let blendeReduziert: Animation = .linear(duration: 0.14)

    @MainActor static var einblenden: Animation {
        bewegungReduziert ? blendeReduziert : .smooth(duration: 0.28)
    }

    /// Kurze Blende für Schalter und den Wechsel Pause ↔ Abspielen
    /// (`Stil.umschalten`).
    @MainActor static var umschalten: Animation {
        bewegungReduziert ? .linear(duration: 0.1) : .easeOut(duration: 0.1)
    }

    @MainActor static var sprung: Animation {
        bewegungReduziert ? blendeReduziert : .snappy(duration: 0.22, extraBounce: 0)
    }

    /// **Ein neues Lied** — Hülle und Zeilen rücken wie ein Karussell
    /// (``Liedwechsel``): eine kritisch gedämpfte Feder, die den Schwung
    /// eines Wischs übernimmt (in Anteilen der Strecke je Sekunde) — kein
    /// Überschwingen, sonst schöbe sich das neue Lied über seinen Platz.
    @MainActor static func liedwechsel(schwung: CGFloat) -> Animation {
        bewegungReduziert ? blendeReduziert
            : .interpolatingSpring(duration: 0.42, bounce: 0, initialVelocity: min(max(Double(schwung), -10), 20))
    }

    @MainActor static var blattbewegung: Animation {
        bewegungReduziert ? blendeReduziert : .spring(response: 0.35, dampingFraction: 0.86)
    }

    /// Der Druck setzt sofort ein, nur das Loslassen läuft über 0,12 s.
    static func druckkurve(_ gedrueckt: Bool) -> Animation? {
        gedrueckt ? nil : .easeOut(duration: 0.12)
    }

    enum Ruckart { case leicht, mittel }

    /// Haptik nur dort, wo der Finger lange liegt (BRAND.md §6).
    @MainActor
    static func ruck(_ art: Ruckart) {
        guard !bewegungReduziert else { return }
        UIImpactFeedbackGenerator(style: art == .leicht ? .light : .medium).impactOccurred()
    }
}

// MARK: - Druck

/// **Jeder Knopf hat den Gedrückt-Zustand**: Maßstab 0,97, Deckkraft 0,85
/// (BRAND.md §5; `Stil.Druckknopf` in `Stil.swift`).
struct Druckknopf: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Musikstil.bewegungReduziert ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Musikstil.druckkurve(configuration.isPressed), value: configuration.isPressed)
    }
}

/// Eine Zeile, die beim Druck eine leise Fläche bekommt (`Stil.Druckzeile`).
struct Druckzeile: ButtonStyle {
    var ecke: CGFloat = Musikstil.eckeKnopf
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0),
                        in: RoundedRectangle(cornerRadius: ecke, style: .continuous))
            .animation(Musikstil.druckkurve(configuration.isPressed), value: configuration.isPressed)
    }
}

/// **Der Hauptknopf**: weiß, 48 hoch, Ecke 10, Schrift 17 Semibold in
/// `aufAkzent` — wie `HauptknopfStil` in `Stil.swift` (die Übergabe hatte 15).
/// Gedrückt 75 % Weiß und 0,97 — die gedrückte Fläche wäre sonst dieselbe.
struct HauptknopfStil: ButtonStyle {
    @Environment(\.isEnabled) private var freigegeben

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(freigegeben ? Stil.aufAkzent : Stil.schriftSehrLeise)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(freigegeben ? Color.white.opacity(configuration.isPressed ? 0.75 : 1) : Stil.flaeche,
                        in: RoundedRectangle(cornerRadius: Musikstil.eckeKnopf, style: .continuous))
            .scaleEffect(configuration.isPressed && !Musikstil.bewegungReduziert ? 0.97 : 1)
            .animation(Musikstil.druckkurve(configuration.isPressed), value: configuration.isPressed)
    }
}

/// **Der Nebenknopf**: `flaeche` ohne Rand, gedrückt `gedruecktFlaeche`
/// (`NebenknopfStil` in `Stil.swift`).
struct NebenknopfStil: ButtonStyle {
    var akzent = false
    @Environment(\.isEnabled) private var freigegeben

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(!freigegeben ? Stil.schriftSehrLeise : (akzent ? Stil.akzent : Stil.schrift))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(configuration.isPressed ? Stil.gedruecktFlaeche : Stil.flaeche,
                        in: RoundedRectangle(cornerRadius: Musikstil.eckeKnopf, style: .continuous))
            .scaleEffect(configuration.isPressed && !Musikstil.bewegungReduziert ? 0.97 : 1)
            .animation(Musikstil.druckkurve(configuration.isPressed), value: configuration.isPressed)
    }
}

/// **Der Symbolknopf**: 48 × 48, `flaeche`, Ecke 10 (Übergabe §3).
struct SymbolknopfStil: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 48, height: 48)
            .background(configuration.isPressed ? Stil.gedruecktFlaeche : Stil.flaeche,
                        in: RoundedRectangle(cornerRadius: Musikstil.eckeKnopf, style: .continuous))
            .scaleEffect(configuration.isPressed && !Musikstil.bewegungReduziert ? 0.97 : 1)
            .animation(Musikstil.druckkurve(configuration.isPressed), value: configuration.isPressed)
    }
}

// MARK: - Umgebung

extension EnvironmentValues {
    /// Die Kante einer Kachel, aus der Breite der Hauptansicht.
    @Entry var kachelkante: CGFloat = Musikstil.kachel
    /// Ob der Bereich, in dem eine Seite steht, gerade vorn ist.
    @Entry var bereichAktiv = true
}

/// **Der Inhalt eines Bereichs beim Wechsel — steht einfach da.**
///
/// Vorher zog er sich eine Spur heran (Maßstab 0,995 → 1 über 0,2 s, wie
/// `Stil.bereichsmass` im Player). **Das nahm der Scrollfläche den Platz
/// unter Pille und Leiste** (24.09.: beim Reiterwechsel war die Fläche
/// über und unter der Pille kurz dunkel, der Inhalt endete über ihr).
/// Gemessen, je Bild im Simulator: solange der Maßstab lief, endete die
/// Scrollfläche bei 790,8 statt 956, ihre Einrückung unten stand bei 0
/// statt 162 — bei jedem Wechsel rund 170 ms, auch als `visualEffect`.
/// Am ganzen Stapel fehlte dafür der sichere Bereich von UIKit. Ohne
/// Maßstab: in allen Wechseln 956 und 162. Die Seiten rufen den Baustein
/// weiter auf; er ändert nichts mehr.
struct Bereichsinhalt: ViewModifier {
    func body(content: Content) -> some View { content }
}

extension View {
    func bereichsinhalt() -> some View { modifier(Bereichsinhalt()) }
}
