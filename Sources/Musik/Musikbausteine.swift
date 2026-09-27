import MusikKit
import SwiftUI
import UIKit

// **Die kleinen Bausteine aus dem Entwurf.** Maße aus der Übergabe
// (`Notizen/SwiftlyMusic/UEBERGABE.md`), Bauart nach Swiftlys Vorlagen in
// `Sources/Shared/Stil.swift` und `Bausteine.swift`.

// MARK: - Pegel

/// **Der Pegel: drei Balken, die sagen „läuft gerade"** (Übergabe §7).
///
/// Feld 14 × 14 (in der Laufmarke 12 × 12), Abstand 2, Ecke 1, `akzent`,
/// am Boden verankert. **Alle drei gleich hoch angelegt** — vorher 60 · 100
/// · 45 %, und der mittlere stand fast immer oben, der rechte fast immer
/// unten (24.09.: „sieht immer aus wie ein Mittelfinger").
///
/// **Zur echten Musik**: läuft das Lied hier und hat es einen Tap
/// (``Pegeltap``), folgen die drei Balken tief, mittel und hoch
/// (``Pegelquelle``, ``Pegelanzeige``), ruhig und jeder zwischen 30 und
/// 85 % des Felds (``Pegelanzeige/balken(_:)``; 24.09.: vorher 18 bis
/// 100 %, „too much"). Wo es
/// keinen Tap gibt — umgewandelt, Connect, AirPlay — pendeln sie: je 1,3
/// Sekunden, weich an beiden Enden, versetzt.
///
/// **Pause**: die Balken klingen in einer halben Sekunde ab, bis alle drei
/// gleich niedrig stehen (25 %); beim Weiterspielen laufen sie ebenso weich
/// wieder an. Bei „Bewegung reduzieren" stehen sie sofort niedrig, beim
/// Spielen gleich hoch auf halber Höhe.
struct Pegel: View {
    var laeuft: Bool
    var feld: CGFloat = 14

    private static let versatz: [Double] = [0.2, 0.6, 0.9]
    /// Die Höhe in der Pause, für alle drei.
    nonisolated static let ruhe: CGFloat = 0.25
    /// So lange klingt es ab oder läuft an.
    static let uebergang: TimeInterval = 0.5

    /// Wann zuletzt zwischen Spielen und Pause gewechselt wurde.
    @State private var wechsel = Date.distantPast
    /// Nach der Pause läuft die Zeit noch, bis die Balken unten sind.
    @State private var ausklang = false
    /// Was zuletzt zu sehen war — von dort aus klingt es ab oder läuft an.
    @State private var stand = Pegelstand()

    var body: some View {
        Group {
            if Musikstil.bewegungReduziert {
                balken { _ in laeuft ? 0.5 : Self.ruhe }
            } else {
                TimelineView(.animation(minimumInterval: nil, paused: !laeuft && !ausklang)) { ctx in
                    let t = ctx.date
                    balken { wert($0, t) }
                }
            }
        }
        .frame(width: feld, height: feld, alignment: .bottom)
        // Wer läuft und sichtbar ist, meldet sich an — nur dann rechnet der
        // Tap, und nur dann tickt die Quelle.
        .task(id: laeuft) {
            guard laeuft else { return }
            Pegelquelle.geteilt.anmelden()
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3_600)) }
            Pegelquelle.geteilt.abmelden()
        }
        .onChange(of: laeuft) { _, neu in
            stand.von = stand.zuletzt
            wechsel = Date()
            guard !neu else { return }
            ausklang = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.uebergang + 0.1))
                if !laeuft { ausklang = false }
            }
        }
        .accessibilityHidden(true)
    }

    private func balken(_ mass: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0 ..< 3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Stil.akzent)
                    .frame(height: feld)
                    .scaleEffect(x: 1, y: mass(i), anchor: .bottom)
            }
        }
    }

    /// Vom zuletzt gezeigten Stand weich zum Ziel: beim Spielen die Musik
    /// oder das Pendeln, in der Pause die Ruhe.
    private func wert(_ i: Int, _ t: Date) -> CGFloat {
        let x = min(max(t.timeIntervalSince(wechsel) / Self.uebergang, 0), 1)
        let k = CGFloat(x * x * (3 - 2 * x))
        let ziel = laeuft ? lebendig(i, t) : Self.ruhe
        let v = stand.von[i] + (ziel - stand.von[i]) * k
        stand.zuletzt[i] = v
        return v
    }

    private func lebendig(_ i: Int, _ t: Date) -> CGFloat {
        if let echt = Pegelquelle.geteilt.baender {
            let wert = i == 0 ? echt.tief : (i == 1 ? echt.mittel : echt.hoch)
            return CGFloat(Pegelanzeige.balken(wert))
        }
        // Hin und zurück in je 1,3 Sekunden, weich an beiden Enden, im
        // selben ruhigen Ausschlag wie zur Musik.
        let phase = (t.timeIntervalSinceReferenceDate / 1.3 + Self.versatz[i]).truncatingRemainder(dividingBy: 2)
        let x = phase < 1 ? phase : 2 - phase
        let weich = x * x * (3 - 2 * x)
        return CGFloat(Pegelanzeige.balken(Float(weich)))
    }
}

/// Was ein Pegel zuletzt zeigte — nicht beobachtet: es ändert sich in jedem
/// Bild, und neu gezeichnet wird ohnehin im Takt der Zeitleiste.
private final class Pegelstand {
    var von: [CGFloat] = [Pegel.ruhe, Pegel.ruhe, Pegel.ruhe]
    var zuletzt: [CGFloat] = [Pegel.ruhe, Pegel.ruhe, Pegel.ruhe]
}

/// **Eine Quelle für alle Pegel.** Liest die Bänder, die der Tap atomar
/// ablegt (``Pegelleitung``), höchstens 30-mal je Sekunde und gibt sie an
/// die Oberfläche — aber nur, solange ein Pegel läuft und zu sehen ist,
/// die App vorn ist und echte Werte kommen können (``echt``, vom Spieler).
/// Sonst tickt nichts, und der Tap rechnet nicht.
///
/// Zwischen zwei Blöcken des Taps (bis zu 0,1 s) gleitet die Anzeige auf den
/// neuen Wert zu, statt zu springen.
@MainActor
@Observable
final class Pegelquelle {
    static let geteilt = Pegelquelle()

    /// Was die Balken zeigen; `nil` heißt: das Muster.
    private(set) var baender: Pegelanalyse.Baender?
    /// Läuft hier ein Lied mit Tap, nicht über AirPlay, nicht auf einem
    /// anderen Gerät? Setzt der ``Spieler``.
    var echt = false {
        didSet { if echt != oldValue { abgleichen() } }
    }

    /// Macht aus den Bändern, was die Balken zeigen (``Pegelanzeige``).
    @ObservationIgnored private var anzeige = Pegelanzeige()
    @ObservationIgnored private var zuschauer = 0
    @ObservationIgnored private var vorn = true
    @ObservationIgnored private var takt: Task<Void, Never>?

    /// 30 Hz.
    static let abstand: Duration = .milliseconds(33)

    private init() {
        let zentrale = NotificationCenter.default
        zentrale.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                             queue: .main) { _ in
            MainActor.assumeIsolated { Pegelquelle.geteilt.vornSetzen(false) }
        }
        zentrale.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil,
                             queue: .main) { _ in
            MainActor.assumeIsolated { Pegelquelle.geteilt.vornSetzen(true) }
        }
    }

    func anmelden() {
        zuschauer += 1
        abgleichen()
    }

    func abmelden() {
        zuschauer = max(zuschauer - 1, 0)
        abgleichen()
    }

    private func vornSetzen(_ neu: Bool) {
        vorn = neu
        abgleichen()
    }

    private func abgleichen() {
        let laufen = echt && zuschauer > 0 && vorn && !Musikstil.bewegungReduziert
        Pegelleitung.gefragt.store(laufen, ordering: .relaxed)
        if laufen {
            guard takt == nil else { return }
            takt = Task { [weak self] in
                while !Task.isCancelled {
                    self?.schritt()
                    try? await Task.sleep(for: Self.abstand)
                }
            }
        } else {
            takt?.cancel()
            takt = nil
            if baender != nil { baender = nil }
            Pegelleitung.wert.store(0, ordering: .relaxed)
        }
    }

    private func schritt() {
        guard let roh = Pegelanalyse.entpacken(Pegelleitung.wert.load(ordering: .relaxed)) else { return }
        let ziel = anzeige.schritt(roh, dauer: 0.033)
        let alt = baender ?? ziel
        func gleiten(_ a: Float, _ b: Float) -> Float { a + (b - a) * 0.5 }
        let neu = Pegelanalyse.Baender(tief: gleiten(alt.tief, ziel.tief),
                                       mittel: gleiten(alt.mittel, ziel.mittel),
                                       hoch: gleiten(alt.hoch, ziel.hoch))
        // Unter einem Hundertstel ändert sich kein Bildpunkt.
        if let b = baender, abs(b.tief - neu.tief) + abs(b.mittel - neu.mittel) + abs(b.hoch - neu.hoch) < 0.01 {
            return
        }
        baender = neu
    }
}

/// Die Laufmarke unten rechts auf einer Kachel: 24 × 24, 5 vom Rand, Ecke 7.
struct Laufmarke: View {
    var laeuft: Bool

    var body: some View {
        Pegel(laeuft: laeuft, feld: 12)
            .frame(width: 24, height: 24)
            .background(Musikstil.schleier, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(5)
    }
}

/// „NEU" oben rechts: 18 hoch, 6 vom Rand, Grund 78 % mit Rand, Ecke 9.
struct NeuMarke: View {
    var body: some View {
        Text("NEU")
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(Stil.schrift)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Musikstil.schleier, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Stil.rand, lineWidth: 1)
            }
            .padding(6)
    }
}

// MARK: - Plakette

/// **Die Plakette**: 26 hoch (im Blatt 22), Ecke 8, Innenabstand 9.
/// „Direct Play" in Akzent auf 15 % Akzent, sonst `schriftLeise` auf weiß 7 %.
struct Plakette: View {
    let text: String
    var akzent = false
    var haken = false
    var hoehe: CGFloat = 26
    var grad: CGFloat = 13

    var body: some View {
        HStack(spacing: 6) {
            if haken { Symbolbild(zeichen: .haken, groesse: 13) }
            Text(verbatim: text)
                .font(.system(size: grad, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(akzent ? Stil.akzent : Stil.schriftLeise)
        .padding(.horizontal, 9)
        .frame(height: hoehe)
        .background(akzent ? Stil.akzent.opacity(0.15) : Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: Musikstil.eckeKlein, style: .continuous))
    }
}

// MARK: - Titel

/// Reihenüberschrift: 20 Semibold, −0,012 em.
struct Reihentitel: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(Musikstil.reihe)
            .tracking(Musikstil.sperrungReihe)
            .foregroundStyle(Stil.schrift)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: Musikstil.reihentitelHoehe,
                   maxHeight: Musikstil.reihentitelHoehe, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// **Der Gruppentitel wie im Player** (`Gruppentitel` in `Stil.swift`):
/// Normalschreibung im Grad einer Reihenüberschrift, 20 Semibold in
/// `schriftLeise`, 10 darunter. Vorher 11 Punkt in Versalien, gesperrt — das
/// Muster, das der Player am 21.09. abgelegt hat: schlechter zu lesen,
/// VoiceOver buchstabiert Versalien je nach Wort, und die Überschrift war
/// leiser als die Zeilen, die sie überschreibt.
struct Gruppentitel: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(Musikstil.reihe)
            .tracking(Musikstil.sperrungReihe)
            .foregroundStyle(Stil.schriftLeise)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
    }
}

/// **Eine Gruppe in den Einstellungen**: Titel und Karte, wie
/// `Einstellungsgruppe` im Player — 26 über dem Titel, 2 unter ihm (dazu
/// die 10 des Titels), die Karte in `gruppenflaeche` mit Ecke 14. Keine
/// Umrandung; getrennt wird durch Leerraum und den Titel.
struct Einstellungsgruppe<Inhalt: View>: View {
    let titel: String
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Gruppentitel(text: titel)
                .padding(.horizontal, Musikstil.rand)
                .padding(.top, 26)
                .padding(.bottom, 2)
            Einstellungskarte { inhalt() }
        }
    }
}

/// **Gruppen sind Karten** in `gruppenflaeche`, Ecke 14 (`Karte` im Player).
struct Einstellungskarte<Inhalt: View>: View {
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        VStack(spacing: 0) { inhalt() }
            .background(Stil.gruppenflaeche, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, Musikstil.rand)
    }
}

// MARK: - Kapsel

/// **Die Kapsel** zum Filtern: 30 hoch, Innenabstand 13, 13 Semibold.
/// Gewählt: Fläche `akzent` 15 % und Schrift `akzent` — kein
/// Gewichtswechsel (BRAND.md §5, „Gewählt ändert kein Maß").
///
/// **Im Wiedergabeblatt aus Glas** (`glas`; 24.09.: der Zufall-Knopf
/// stand in „Als Nächstes" als feste Fläche und wirkte fremd): Weiß wie die
/// laufende Zeile daneben (``Zeilenflaeche``) statt `flaeche`.
struct Kapsel: View {
    let text: LocalizedStringKey
    let an: Bool
    var glas = false
    let aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            Text(text)
                .font(Musikstil.kapsel)
                .foregroundStyle(an ? Stil.akzent : Stil.schriftLeise)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .frame(height: 30)
                // **Die gewählte in Akzent** (24.09.: „man sieht nicht,
                // welche aktiv ist"): Fläche `akzent` 15 %, Schrift `akzent` —
                // wie die Plakette „Direct Play". `erhoeht` gegen `flaeche` war zu
                // wenig Unterschied. Das Gewicht bleibt, sonst rücken die
                // Nachbarn (`Wahlchip`).
                .background(an ? Stil.akzent.opacity(0.15)
                                : (glas ? Color.white.opacity(Seitenfarbe.laufend) : Stil.flaeche),
                            in: Capsule())
                .animation(Musikstil.umschalten, value: an)
                .contentShape(Capsule())
        }
        .buttonStyle(Druckknopf())
        .accessibilityAddTraits(an ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Aktionsreihe

/// **Ein Feld der Aktionsreihe**: Zeichen 21, darunter 6 Abstand und die
/// Beschriftung in 12 `schriftLeise`. Ein aktiver Zustand färbt das Zeichen
/// in Akzent (E2); „gewählt" (Liedtext im Blatt) ist ein Chip: Zeichen auf
/// Weiß wie die laufende Zeile — durchscheinend über dem unscharfen Grund
/// des Blatts, nicht die feste Fläche `erhoeht` (24.09.) —,
/// Beschriftung weiß.
struct Aktionsinhalt: View {
    let zeichen: Zeichen
    let titel: Text
    var aktiv = false
    var gewaehlt = false

    var body: some View {
        VStack(spacing: 6) {
            Symbolbild(zeichen: zeichen, groesse: 21)
                .foregroundStyle(aktiv ? Stil.akzent : Stil.schrift)
                .padding(.horizontal, gewaehlt ? 10 : 0)
                .padding(.vertical, gewaehlt ? 3 : 0)
                // Rund wie Pille, Kapseln und die Knöpfe daneben (24.09.:
                // die Knöpfe waren „weniger rund als alles andere").
                .background {
                    if gewaehlt {
                        Capsule().fill(Color.white.opacity(Seitenfarbe.laufend))
                    }
                }
                // Der Chip darf das Feld nicht höher machen als seine Nachbarn.
                .frame(height: 21)
            titel
                .font(Musikstil.angabe)
                .foregroundStyle(gewaehlt ? Stil.schrift : Stil.schriftLeise)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct Aktion: View {
    let zeichen: Zeichen
    let titel: Text
    var aktiv = false
    var gewaehlt = false
    let tun: () -> Void

    var body: some View {
        Button(action: tun) {
            Aktionsinhalt(zeichen: zeichen, titel: titel, aktiv: aktiv, gewaehlt: gewaehlt)
        }
        .buttonStyle(Druckknopf())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titel)
        .accessibilityAddTraits(aktiv || gewaehlt ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Fortschritt

/// **Die Stelle je Bild, nur solange sie läuft** (``Spieler/anzeigestelle()``,
/// ``Stellenuhr``): eine Zeitleiste im Takt des Bildschirms, die steht, wenn
/// die Wiedergabe steht — und die iOS ohnehin anhält, wenn die App nicht
/// vorn oder der Schirm gesperrt ist. `takt` begrenzt, wie oft neu
/// gezeichnet wird (für Ziffern reicht eine Viertelsekunde); `sichtbar`
/// hält sie an, solange die Ansicht verborgen im Baum steht (das Blatt zu,
/// die Pille unter dem offenen Blatt).
struct Laufanzeige<Inhalt: View>: View {
    let spieler: Spieler
    var takt: Double?
    var sichtbar: Bool
    @ViewBuilder let inhalt: (TimeInterval) -> Inhalt

    init(spieler: Spieler, takt: Double? = nil, sichtbar: Bool = true,
         @ViewBuilder inhalt: @escaping (TimeInterval) -> Inhalt) {
        self.spieler = spieler
        self.takt = takt
        self.sichtbar = sichtbar
        self.inhalt = inhalt
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: takt, paused: !spieler.uhrLaeuft || !sichtbar)) { _ in
            inhalt(spieler.anzeigestelle())
        }
    }
}

/// **Spur weiß 30 %, gespielter Teil weiß** (24.09.: statt `akzent`
/// — im Blatt wie in der Pille). In der Pille rechteckig und bündig unten,
/// im Blatt mit runden Enden (`rund`).
struct Fortschrittsspur: View {
    let anteil: Double
    var hoehe: CGFloat = 4
    var rund = false

    var body: some View {
        GeometryReader { g in
            let breite = g.size.width * min(max(anteil.isFinite ? anteil : 0, 0), 1)
            ZStack(alignment: .leading) {
                if rund {
                    Capsule().fill(Musikstil.spur)
                    // Nie schmaler als die Höhe — sonst stünde am Anfang ein
                    // gestauchter Punkt statt eines runden Endes.
                    Capsule().fill(Stil.schrift)
                        .frame(width: max(breite, breite > 0 ? hoehe : 0))
                } else {
                    Rectangle().fill(Musikstil.spur)
                    Rectangle().fill(Stil.schrift)
                        .frame(width: breite)
                }
            }
        }
        .frame(height: hoehe)
        .accessibilityHidden(true)
    }
}

// MARK: - Laden und leer

/// **Ein Platzhalter in der Form des Kommenden**, leise pulsierend (E17).
struct Ladefeld: View {
    var ecke: CGFloat = Musikstil.eckeKachel
    @State private var hell = false

    var body: some View {
        RoundedRectangle(cornerRadius: ecke, style: .continuous)
            .fill(Stil.flaeche)
            .animation(Musikstil.bewegungReduziert ? nil
                       : .easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                $0.opacity(hell ? 1 : 0.5)
            }
            .task { hell = true }
            .accessibilityHidden(true)
    }
}

/// **Leerzustand und Fehler** nach BRAND.md §7: Zeichen im Kreis von 78,
/// 22 Luft, Kopfzeile 20 Semibold, 7, Text 15 `schriftLeise`, 24, Knopf.
struct Leerzustand: View {
    let symbol: String
    let kopfzeile: Text
    let text: Text
    var knopf: (titel: Text, tun: () -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Stil.flaeche).frame(width: 78, height: 78)
                Image(systemName: symbol)
                    .font(.system(size: 44))
                    .foregroundStyle(Stil.schriftLeise)
            }
            .padding(.bottom, 22)
            .accessibilityHidden(true)

            kopfzeile
                .font(Musikstil.reihe)
                .tracking(Musikstil.sperrungReihe)
                .foregroundStyle(Stil.schrift)
                .multilineTextAlignment(.center)
                .padding(.bottom, 7)

            text
                .font(.system(size: 15))
                .foregroundStyle(Stil.schriftLeise)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            if let knopf {
                Button(action: knopf.tun) { knopf.titel.padding(.horizontal, 28) }
                    .buttonStyle(HauptknopfStil())
                    .fixedSize()
                    .padding(.top, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 34)
        .accessibilityElement(children: .combine)
        // Der Eintritt gehört ins Bauteil, das Wann zum Aufrufer
        // (`Leerzustand` in `Stil.swift`).
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

// MARK: - Profilzeichen

/// **Das Profilzeichen oben rechts**: 34, rund, mit Rand 12 % — einer der
/// `Stil.profiltoene` (`Sources/Shared/Farben.swift`), derselbe Satz wie im
/// Player, keiner aus der verworfenen Akzentfamilie (BRAND.md §10) — und der
/// Anfangsbuchstabe in 13 Semibold. Hat der Server ein Bild, steht es statt
/// des Buchstabens.
struct Profilzeichen: View {
    let name: String
    var bild: URL?
    var groesse: CGFloat = 34

    /// **Was schon geholt ist, steht im ersten Durchgang da** — im `init`
    /// nachgesehen, nicht erst im `task` (`Profilzeichen` im Player,
    /// `Sources/Shared/Bausteine.swift`). Ein nachgereichter Wert kommt
    /// einen Durchgang zu spät, und der eine Durchgang ist das Aufblitzen.
    @State private var geladen: Image?
    /// Der Abruf ist gescheitert — meist hat das Konto kein Bild. Dann
    /// gehört der Buchstabe hin.
    @State private var ohneBild = false

    init(name: String, bild: URL? = nil, groesse: CGFloat = 34) {
        self.name = name
        self.bild = bild
        self.groesse = groesse
        _geladen = State(initialValue: bild.flatMap { Bildlager.geteilt.bild($0) })
    }

    var body: some View {
        ZStack {
            grund
            // **Der Buchstabe ist Rückfall, nicht Untergrund.** Lag er immer
            // darunter, schien er während der Aufblende des Bildes durch.
            // Während des Abrufs steht nur der Verlauf.
            if let geladen {
                geladen.resizable().aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if bild == nil || ohneBild {
                Text(verbatim: String(name.prefix(1)).uppercased())
                    .font(.system(size: groesse * 0.38, weight: .semibold))
                    .foregroundStyle(Stil.schrift)
            }
        }
        .animation(Musikstil.einblenden, value: geladen == nil)
        .task(id: bild) {
            ohneBild = false
            guard let bild else { geladen = nil; return }
            if let da = Bildlager.geteilt.bild(bild) { geladen = da; return }
            geladen = await Bildlager.geteilt.laden(bild)
            ohneBild = geladen == nil
        }
        .frame(width: groesse, height: groesse)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Stil.rand, lineWidth: 1) }
        .accessibilityElement()
        .accessibilityLabel(Text("Konto von \(name)"))
    }

    /// Derselbe Verlauf wie im Player (`Profilzeichen` in
    /// `Sources/Shared/Bausteine.swift`): einer der `Stil.profiltoene`, nach
    /// dem Namen gewählt, damit dasselbe Konto auf beiden Seiten dieselbe
    /// Farbe trägt.
    private var grund: some View {
        let toene = Stil.profiltoene[abs(namensziffer) % Stil.profiltoene.count]
        return LinearGradient(colors: [toene.oben, toene.unten],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Eine feste Zahl zum Namen — `hashValue` taugt nicht: der ist je Start
    /// der App ein anderer, und dann wechselt das Zeichen seine Farbe, sobald
    /// man die App neu öffnet.
    private var namensziffer: Int {
        name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 1_000_003 }
    }
}

// MARK: - Lauftext

/// **Ein zu langer Titel läuft endlos** (25.09., wie Spotify): erst
/// steht er zwei Sekunden am Anfang, dann fährt er gleichmäßig mit ``tempo``
/// nach links — hinter ihm, nach ``luecke``, derselbe Text noch einmal. Ist
/// der zweite am Anfang angekommen, sieht es aus wie vorher: er steht
/// wieder zwei Sekunden, und alles beginnt von vorn. Kein Rücksprung, keine
/// Blende (vorher: bis zum Ende, warten, ausblenden, am Anfang einblenden).
///
/// **Die Stelle kommt aus der Uhr, nicht aus einer Animation** (25.09.:
/// tippte man während des Laufs auf Als Nächstes, sprang der Text weit nach
/// rechts oben und blieb dort stehen). Der Lauf war eine lineare Animation
/// über die ganze Strecke; ein Wechsel ohne Animation beendet sie in
/// SwiftUI nicht, die Restbewegung kommt obendrauf. Gemessen im Kopf: der
/// Titel begann bei x 181–206 statt im Rahmen bei 78 und kroch weiter.
/// Jetzt rechnet ein `TimelineView` die Stelle aus der Zeit seit dem Start;
/// endet `laufen`, steht er im selben Bild am Anfang.
///
/// **Er endet an seinem Rahmen, weich**: der Rahmen nimmt genau den
/// angebotenen Platz (`minWidth: 0`), schneidet hart ab und läuft rechts
/// weich aus statt „…"; links, solange der Anfang aus dem Bild ist.
///
/// - **Nur in Ruhe** (`laufen`): in jeder Bewegung steht er am Anfang.
/// - Nur Verschiebung; der Text wird einmal gesetzt, nie je Bild neu.
/// - Bewegung reduzieren: steht, rechts weich ausgeblendet.
/// - VoiceOver liest den ganzen Text.
struct Lauftext: View {
    let text: String
    let schrift: Font
    var sperrung: CGFloat = 0
    let farbe: Color
    let laufen: Bool

    /// Punkt je Sekunde.
    static let tempo: CGFloat = 30
    /// So breit laufen die Ränder aus.
    static let rand: CGFloat = 14
    /// Vom Ende des Texts bis zu seinem nächsten Anfang.
    static let luecke: CGFloat = 32
    /// So lange steht er am Anfang, bevor er losläuft.
    static let halt: Double = 2
    /// So lange blendet der linke Rand weich ein und wieder aus.
    static let randzeit: Double = 0.25

    @State private var textbreite: CGFloat = 0
    @State private var breite: CGFloat = 0
    /// Seit wann die laufende Runde läuft; `nil`: er steht am Anfang.
    @State private var beginn: Date?

    var body: some View {
        let zuLang = breite > 0 && textbreite > breite + 0.5
        let aktiv = laufen && zuLang && !Musikstil.bewegungReduziert
        let runde = textbreite + Self.luecke
        let seit = aktiv ? beginn : nil
        TimelineView(.animation(minimumInterval: nil, paused: seit == nil)) { uhr in
            let t = seit.map { max(uhr.date.timeIntervalSince($0), 0) } ?? 0
            let dauer = Double(runde / Self.tempo)
            let versatz = -min(CGFloat(t) * Self.tempo, runde)
            let weich = seit == nil ? 0 : min(t / Self.randzeit, (dauer - t) / Self.randzeit, 1)
            zeile
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textbreite = $0 }
                .overlay(alignment: .leading) {
                    if seit != nil {
                        zeile
                            .fixedSize()
                            .offset(x: runde)
                    }
                }
                .offset(x: versatz)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { breite = $0 }
                .clipped()
                .mask { if zuLang { rander(links: max(weich, 0)) } else { Rectangle() } }
        }
        .task(id: Runde(text: text, aktiv: aktiv, weg: runde)) {
            await laufenLassen(aktiv ? Double(runde / Self.tempo) : nil)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }

    private var zeile: some View {
        Text(verbatim: text)
            .font(schrift)
            .tracking(sperrung)
            .foregroundStyle(farbe)
    }

    /// `links`: wie weit der linke Rand weich ausläuft, 0 hart bis 1.
    private func rander(links: Double) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(1 - links), .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.rand)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.rand)
        }
    }

    private struct Runde: Equatable {
        let text: String
        let aktiv: Bool
        let weg: CGFloat
    }

    /// Stehen, eine Runde laufen, stehen — bis `laufen` endet. Zwischen den
    /// Runden steht die Uhr still; es wird nichts gezeichnet.
    private func laufenLassen(_ dauer: Double?) async {
        beginn = nil
        guard let dauer, dauer > 0 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.halt))
            guard !Task.isCancelled else { return }
            beginn = .now
            try? await Task.sleep(for: .seconds(dauer))
            guard !Task.isCancelled else { return }
            beginn = nil
        }
    }
}

// MARK: - Liedwechsel

/// **Ein neues Lied rückt nach wie in einem Karussell** (25.09.: beim
/// Wechsel wurde es kurz dunkel). Vorher ging das alte mit einer Blende,
/// dann kam das neue — dazwischen war für einen Augenblick keins zu sehen.
/// Jetzt schiebt das alte hinaus, und das neue folgt in derselben Bewegung,
/// um ``schritt`` dahinter: nur Verschiebung, keine Deckkraft, nie leer.
/// Weiter und natürliches Ende: das neue von rechts; zurück umgekehrt —
/// gerechnet am Platz in der Schlange (`stelle`).
///
/// **Eine Feder über ein Band**: jedes Lied hat seinen festen Platz
/// (`anker`), das Band (`lage`) fährt zum neuen. So beginnt die Bewegung im
/// selben Bild wie der Wechsel, und ein Wechsel mitten im Wechsel legt nur
/// eine Feder dazu — SwiftUI rechnet sie mit Tempo weiter, ohne Sprung.
///
/// **Ein Wisch gibt Stelle und Schwung mit** (``Anstoss``): das alte steht
/// dort, wo der Finger die Zeile losließ, und die Feder nimmt sein Tempo
/// — ohne Naht zwischen Finger und Bewegung.
///
/// Bewegung reduzieren und `an` aus: sofort getauscht.
struct Liedwechsel<Wert: Equatable, Inhalt: View>: View {
    let wert: Wert
    let stelle: Int?
    /// Wie weit das nächste Lied hinter dem jetzigen steht; ohne Angabe die
    /// eigene Breite und 24 Punkt.
    var schritt: CGFloat?
    var ausrichtung: Alignment = .center
    var an = true
    /// Ein Wisch hat den Wechsel ausgelöst.
    var anstoss: Anstoss?
    @ViewBuilder let inhalt: (Wert) -> Inhalt

    @State private var alt: Wert?
    /// Die Plätze auf dem Band, des jetzigen und des alten Lieds.
    @State private var anker: CGFloat = 0
    @State private var altAnker: CGFloat = 0
    /// Wo das Band steht — das jetzige Lied liegt bei `anker − lage`.
    @State private var lage: CGFloat = 0
    @State private var eigen: CGFloat = 0
    @State private var runde = 0

    var body: some View {
        let s = schritt ?? eigen + 24
        ZStack(alignment: ausrichtung) {
            if let alt {
                inhalt(alt)
                    .modifier(Karussellstand(lage: lage, anker: altAnker))
                    .transition(.identity)
                    .accessibilityHidden(true)
            }
            inhalt(wert)
                .modifier(Karussellstand(lage: lage, anker: anker))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { eigen = $0 }
        .onChange(of: Schluessel(wert: wert, stelle: stelle)) { vorher, neu in
            guard vorher.wert != neu.wert else { return }
            wechseln(von: vorher, nach: neu, schritt: s)
        }
    }

    private func wechseln(von vorher: Schluessel, nach neu: Schluessel, schritt s: CGFloat) {
        runde += 1
        let diese = runde
        guard an, !Musikstil.bewegungReduziert else {
            // `Halt` löst eine noch laufende Feder ab — ohne Animation
            // gesetzt, liefe sie obendrauf weiter.
            withAnimation(Animation(Halt())) {
                alt = nil
                lage = anker
            }
            return
        }
        let r: CGFloat
        if let anstoss {
            r = anstoss.richtung
        } else if let a = vorher.stelle, let b = neu.stelle, a != b {
            r = b > a ? 1 : -1
        } else {
            r = 1
        }
        // Das alte bleibt auf seinem Platz — nach einem Wisch dort, wo der
        // Finger es losließ —, das neue liegt einen Schritt dahinter.
        var ohne = Transaction(animation: nil)
        ohne.disablesAnimations = true
        withTransaction(ohne) {
            alt = vorher.wert
            altAnker = anker + (anstoss?.versatz ?? 0)
            anker = altAnker + r * s
        }
        // Der Schwung zählt in Anteilen der Strecke je Sekunde; das Band
        // fährt gegen die Zeilen.
        let strecke = anker - lage
        let schwung = abs(strecke) > 1 ? -(anstoss?.tempo ?? 0) / strecke : 0
        withAnimation(Musikstil.liedwechsel(schwung: schwung)) { lage = anker } completion: {
            if runde == diese { alt = nil }
        }
    }

    private struct Schluessel: Equatable {
        let wert: Wert
        let stelle: Int?
    }
}

/// Wo ein Wisch den Liedwechsel auslöste: die Stelle der Zeile, das Tempo
/// des Fingers (Punkt je Sekunde) und die Richtung (1: das neue kommt von
/// rechts).
struct Anstoss: Equatable {
    let versatz: CGFloat
    let tempo: CGFloat
    let richtung: CGFloat
}

/// **Die Stelle im Karussell, Bild für Bild**: der Platz des Lieds minus
/// die Stelle des Bands.
nonisolated struct Karussellstand: ViewModifier, Animatable {
    var lage: CGFloat
    let anker: CGFloat

    var animatableData: CGFloat {
        get { lage }
        set { lage = newValue }
    }

    @MainActor func body(content: Content) -> some View {
        content.offset(x: anker - lage)
    }
}

/// Ein Lied als Wert für den ``Liedwechsel`` — gleich, solange es dasselbe
/// Lied ist; der Text darf sich ändern.
struct Zeilenwert: Equatable {
    let kennung: String
    let text: String

    static func == (a: Self, b: Self) -> Bool { a.kennung == b.kennung }
}

/// Die Hülle eines Lieds — gleich, solange es dasselbe Lied ist, auch wenn
/// die Adresse wechselt (etwa, weil sie inzwischen abgelegt ist).
struct Huellenwert: Equatable {
    let kennung: String
    let bild: URL?

    static func == (a: Self, b: Self) -> Bool { a.kennung == b.kennung }
}

// MARK: - Deckwechsel

/// **Ein neuer Grund deckt über dem alten auf — nie wird es dazwischen
/// dunkel** (25.09.). Vorher blendete das alte aus, während das neue
/// einblendete: in der Mitte deckten beide zusammen nur drei Viertel, und
/// der dunkle Grund darunter schien durch. Beim Grund des Blatts blendete
/// dabei sogar das alte Bild über sich selbst — die Adresse war schon neu,
/// das Bild noch nicht geladen. Jetzt bleibt das alte voll stehen, bis das
/// neue darüber ganz da ist.
struct Deckwechsel<Wert: Equatable, Inhalt: View>: View {
    let wert: Wert
    @ViewBuilder let inhalt: (Wert) -> Inhalt

    @State private var unten: Wert?
    @State private var deckung: Double = 1
    @State private var runde = 0

    var body: some View {
        ZStack {
            if let unten {
                inhalt(unten)
                    .transition(.identity)
            }
            inhalt(wert)
                .opacity(deckung)
        }
        .onChange(of: wert) { vorher, _ in
            runde += 1
            let diese = runde
            withAnimation(Animation(Halt())) {
                unten = vorher
                deckung = 0
            }
            Task { @MainActor in
                withAnimation(Musikstil.bewegungReduziert ? Musikstil.blendeReduziert : .easeInOut(duration: 0.4)) {
                    deckung = 1
                } completion: {
                    if runde == diese { unten = nil }
                }
            }
        }
    }
}
