import MusikKit
import SwiftUI
import UIKit

/// **Bildschirmfotos im Simulator**: mit `-SwiftlyScreenshot 1` überspringt
/// die App den Startvorhang (``Wurzel``) — nur wirksam im Simulator, im
/// Gerätebau nicht enthalten.
enum Bildschirmfotostart {
    static var uebersprungen: Bool {
        #if targetEnvironment(simulator)
        UserDefaults.standard.bool(forKey: "SwiftlyScreenshot")
        #else
        false
        #endif
    }
}

@main
struct SwiftlyMusicApp: App {
    @UIApplicationDelegateAdaptor(Musikanwendung.self) private var anwendung
    @State private var modell = Musikmodell()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Wurzel()
                .environment(modell)
                .preferredColorScheme(.dark)
                .tint(Stil.akzent)
                .task { await modell.starten() }
        }
        .onChange(of: phase) { alt, neu in
            // Die Stelle mitnehmen, bevor iOS die App vielleicht beendet;
            // beim Zurückkommen nachsehen, ob woanders etwas läuft.
            if neu == .active, alt != .active {
                modell.phaseGewechselt(aktiv: true)
            } else if neu == .background {
                modell.phaseGewechselt(aktiv: false)
            } else if neu != .active {
                modell.schlangeSichern()
            }
        }
    }
}

/// Anmelden oder Musik.
///
/// **Das erste Bild liegt unter dem Vorhang**, wie im Player (`RootView`;
/// 24.09.: beim Kaltstart „animiert sich einmal alles ein"). Die
/// Blende hängt am Übergang selbst (`.transition(.opacity.animation(…))`),
/// nicht mehr als `.animation(_, value: modell.lage)` am Stapel — so läuft
/// nur sie animiert, nicht alles andere, was sich im selben Zug ändert.
struct Wurzel: View {
    @Environment(Musikmodell.self) private var modell
    /// Der Vorhang liegt über allem, bis die Marke durch ist — außer bei
    /// Bildschirmfotos im Simulator (``Bildschirmfotostart``): der Vorhang
    /// stört nur beim Aufnehmen.
    @State private var gestartet = Bildschirmfotostart.uebersprungen

    var body: some View {
        let blende = AnyTransition.opacity.animation(Musikstil.einblenden)
        ZStack {
            Stil.grund.ignoresSafeArea()
            switch modell.lage {
            case .startet:
                EmptyView()
            case .abgemeldet:
                Anmeldeseite().transition(blende)
            case .angemeldet:
                Hauptansicht().transition(blende)
            }
        }
        // Hier und nicht in der Hauptansicht: die ignoriert die Tastatur, das
        // Namensblatt muss über ihr stehen.
        .overlay { Namensebene() }
        .overlay {
            if !gestartet {
                Startvorhang {
                    withAnimation(Musikstil.einblenden) { gestartet = true }
                }
            }
        }
    }
}

/// **Die Hauptansicht**: je Bereich ein eigener Seitenstapel, darüber fest
/// der Mini-Player und die Leiste, darüber das Wiedergabeblatt.
///
/// Leiste und Mini-Player stehen **außerhalb** der Stapel: sie bleiben stehen,
/// wenn eine Albumseite hereinfährt, wie im Entwurf.
///
/// **Der Platz unten kommt von hier, für jede Seite** (24.09.: der
/// Sofortmix-Titel verschwand unter Pille und Leiste). Vorher hing das an
/// einem `safeAreaInset` um alle Stapel; der erreichte die Scrollflächen
/// nicht zuverlässig durch den `NavigationStack` hindurch. Jetzt bekommt
/// jede Seite **innerhalb** ihres Stapels — die Wurzelseite und jede
/// hereinfahrende — einen eigenen Einzug unten (``Unterkante``): Leiste,
/// dazu, solange die Pille steht, Pille + 8 + ``pillenluft``. Pille und
/// Leiste selbst liegen darüber (`overlay`), der Inhalt läuft darunter durch.
struct Hauptansicht: View {
    @Environment(Musikmodell.self) private var modell
    @State private var breite: CGFloat = 0
    /// Wie weit das Wiedergabeblatt offen ist — Pille, Leiste und Blatt lesen
    /// dieselbe Zahl (``Blattstand``).
    @State private var stand = Blattstand()
    /// Zählt je Bereich, wie oft er nach oben scrollen soll (``Nachoben``).
    @State private var nachOben: [Bereich: Int] = [:]

    /// Luft zwischen dem Ende einer Seite und der Pille.
    static let pillenluft: CGFloat = 8

    private var bereiche: [Bereich] {
        modell.hatHoerbuecher ? [.start, .bibliothek, .suche, .hoerbuecher] : [.start, .bibliothek, .suche]
    }

    /// Wie viel unten frei bleiben muss, über dem sicheren Bereich.
    private var unten: CGFloat {
        Leiste.hoehe + (modell.spieler.aktuell == nil ? 0 : 58 + 8 + Self.pillenluft)
    }

    var body: some View {
        @Bindable var modell = modell
        ZStack {
            ForEach(bereiche) { bereich in
                let aktiv = bereich == modell.bereich
                // Die Deckkraft schaltet hart — liefe sie mit, sähe man im
                // Wechsel durch beide Seiten hindurch (`VERHALTEN.md` E20).
                // Kein Heranziehen mehr (``Bereichsinhalt``): jede Maßstabs-
                // bewegung nahm der Scrollfläche für ihre Dauer den Platz
                // unter Pille und Leiste.
                Bereichsstapel(bereich: bereich, nachOben: nachOben[bereich] ?? 0)
                    .environment(\.bereichAktiv, aktiv)
                    .opacity(aktiv ? 1 : 0)
                    .allowsHitTesting(aktiv)
                    .accessibilityHidden(!aktiv)
                    .zIndex(aktiv ? 1 : 0)
            }
        }
        .environment(\.unterkante, unten)
        .animation(Musikstil.blattbewegung, value: modell.spieler.aktuell == nil)
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                Hinweis()
                Angebotsstreifen()
                Minispieler()
                    .padding(.horizontal, 8)
                    .padding(.bottom, modell.spieler.aktuell == nil ? 0 : 8)
                    // Solange das Blatt aus ihr herauswächst, steht die
                    // wachsende Pille an ihrer Stelle (``Wiedergabeblatt``).
                    .modifier(Pillenplatz())
                Leiste(bereiche: bereiche, gewaehlt: Binding(get: { modell.bereich }, set: { reiterWechseln($0) }),
                       nochmal: reiterNochmal)
                // Die Leiste fährt nach unten weg, während das Blatt wächst.
                .modifier(Leistenfahrt())
            }
            .padding(.top, modell.spieler.aktuell == nil ? 0 : Self.pillenluft)
            // **Nichts fällt durch** (24.09.): die ganze Zone vom Ende
            // der Seite bis unter den Home-Indikator schluckt Tipps — die
            // Lücken neben und unter der Pille ebenso wie die Leiste selbst.
            // Die Knöpfe darin liegen davor und bekommen ihre Tipps zuerst.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityHidden(true)
            }
            .animation(Musikstil.blattbewegung, value: modell.spieler.aktuell == nil)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Ohne Animation, auch mitten in einer: die Kachelkante folgt dem
        // Maß des Schirms, sie wächst nicht dorthin.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { neu in
            var ohne = Transaction(animation: nil)
            ohne.disablesAnimations = true
            withTransaction(ohne) { breite = neu }
        }
        .environment(\.kachelkante, Musikstil.kachelkante(breite: breite))
        .overlay { Wiedergabeblatt() }
        // Über dem Wiedergabeblatt: von dort aus gewählt.
        .overlay { Kuenstlerwahlebene() }
        // Über dem Wiedergabeblatt: dort sitzt der Knopf, der es öffnet.
        .overlay { Geraeteebene() }
        // Über allem außer dem Handlungsblatt: die Tasten am iPhone öffnen es,
        // solange Sonos spielt.
        .overlay { Lautstaerkeebene() }
        // Solange das Lautstärke-Blatt offen ist: das Versteck, das die
        // Lautstärkeanzeige des Systems unterdrückt (``Lautstaerketasten``).
        .background(alignment: .topLeading) {
            if modell.sonos.anzeigeVerstecken {
                Lautstaerkeversteck()
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        // Über dem Wiedergabeblatt: auch dort öffnen „Mehr" und langer Druck
        // dieses Blatt.
        .overlay { Handlungsebene() }
        .onChange(of: modell.hatHoerbuecher) { _, da in
            if !da, modell.bereich == .hoerbuecher { modell.bereich = .start }
        }
        .environment(stand)
    }

    /// **Ein Tipp auf einen anderen Reiter führt zu seiner Wurzel** (24.09.: „Start sollte immer wieder zurück auf die Startseite heißen").
    /// Der Stapel geht ohne Bewegung zurück, solange er noch verdeckt ist —
    /// man sieht keine Seite durchlaufen; das Heranziehen der Scrollfläche
    /// bleibt.
    private func reiterWechseln(_ neu: Bereich) {
        if !(modell.pfade[neu] ?? []).isEmpty {
            var ohne = Transaction(animation: nil)
            ohne.disablesAnimations = true
            withTransaction(ohne) { modell.pfade[neu] = [] }
        }
        modell.bereich = neu
    }

    /// **Ein zweiter Tipp auf den offenen Reiter**: steht eine Seite darauf,
    /// geht der Stapel zurück zur Wurzel (wie gewohnt, mit Bewegung); steht
    /// schon die Wurzel da, scrollt sie nach oben wie im Player. Die Suche
    /// holt dazu ihr Feld nach vorn (`reiterNochmal` in `HauptView`).
    private func reiterNochmal(_ bereich: Bereich) {
        if !(modell.pfade[bereich] ?? []).isEmpty {
            modell.pfade[bereich] = []
            return
        }
        nachOben[bereich, default: 0] += 1
        if bereich == .suche { modell.sucheNochmal += 1 }
    }
}

/// **Der Einzug unten, auf jeder Seite** — gesetzt in jedem Stapel an der
/// Seite selbst, nicht um den Stapel herum (``Hauptansicht``).
private struct Unterkante: ViewModifier {
    @Environment(\.unterkante) private var unten

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: unten)
                .allowsHitTesting(false)
        }
    }
}

extension EnvironmentValues {
    /// Was unten von Leiste und Pille belegt ist (``Hauptansicht``).
    @Entry var unterkante: CGFloat = 0
}

/// Die echte Pille tritt zurück, solange die wachsende an ihrer Stelle steht
/// (``Wiedergabeblatt``) — **hart, in einem Bild** (``Blattstand/buehne``).
/// Hing sie am Anteil, blendete sie beim Schließen über die ganze Feder ein,
/// während das Blatt darüber ausblendete. Bei „Bewegung reduzieren" blendet
/// das Blatt über der Pille, die dann gleich geht.
private struct Pillenplatz: ViewModifier {
    @Environment(Blattstand.self) private var stand

    func body(content: Content) -> some View {
        let weg = Musikstil.bewegungReduziert ? stand.anteil > 0 : stand.buehne
        content.opacity(weg ? 0 : 1)
    }
}

/// Die Leiste fährt um ``weg`` nach unten weg, während das Blatt wächst.
struct Leistenfahrt: ViewModifier {
    @Environment(Blattstand.self) private var stand

    /// So weit — der Schatten der Karte endet an ihrer Oberkante
    /// (``Wiedergabeblatt``).
    static let weg: CGFloat = 110

    func body(content: Content) -> some View {
        content.offset(y: Musikstil.bewegungReduziert ? 0 : stand.anteil * Self.weg)
    }
}

/// Ein Bereich mit eigenem Seitenstapel.
///
/// **Der Stapel selbst trägt den Grund der App** (24.09.: beim
/// Wechsel der Bereiche blitzte über und unter der Pille Schwarz auf).
/// Unter jeder Seite lag der Grund des `NavigationStack` — gemessen: jede
/// `HostingView` der Stapel deckend #000000 über den ganzen Schirm, die
/// Seiten darauf #101010. Wo eine Seite im Wechsel für ein Bild nicht
/// hinreichte — im Streifen unter Pille und Leiste —, stand reines Schwarz.
/// Jetzt ist der Grund dahinter derselbe wie auf der Seite.
private struct Bereichsstapel: View {
    let bereich: Bereich
    let nachOben: Int
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        @Bindable var modell = modell
        NavigationStack(path: Binding(get: { modell.pfade[bereich] ?? [] },
                                      set: { modell.pfade[bereich] = $0 })) {
            wurzelseite
                .modifier(Unterkante())
                .background { Nachoben(zaehler: nachOben) }
                .containerBackground(Stil.grund, for: .navigation)
                .navigationDestination(for: Seite.self) { seite in
                    Group {
                        switch seite {
                        case .konto: Kontoseite()
                        case let .playlistBearbeiten(p): Playlistbearbeitung(playlist: p)
                        case .geladen: Geladenseite()
                        case let .ziel(.kuenstler(k)): Kuenstlerseite(kuenstler: k)
                        case let .ziel(ziel): Albumseite(ziel: ziel)
                        }
                    }
                    .modifier(Unterkante())
                    .containerBackground(Stil.grund, for: .navigation)
                }
        }
    }

    @ViewBuilder private var wurzelseite: some View {
        switch bereich {
        case .start: Startseite()
        case .bibliothek: Bibliotheksseite()
        case .suche: Suchseite()
        case .hoerbuecher: Hoerbuecherseite()
        }
    }
}

/// **Ein kurzer Hinweis** über dem Mini-Player — ein Streifen aus `flaeche`,
/// der nach drei Sekunden geht (`Hinweisstreifen` in `Stil.swift`).
private struct Hinweis: View {
    @Environment(Musikmodell.self) private var modell

    private var text: String? {
        modell.hinweis ?? modell.spieler.fehler ?? modell.ablage.hinweis
    }

    var body: some View {
        ZStack {
            if let text {
                HStack(spacing: 14) {
                    Text(verbatim: text)
                        .font(.system(size: 13))
                        .foregroundStyle(Stil.schrift)
                        .multilineTextAlignment(.center)
                    if let zurueck = modell.rueckgaengig {
                        Button {
                            withAnimation(Musikstil.einblenden) {
                                modell.hinweis = nil
                                modell.rueckgaengig = nil
                            }
                            zurueck()
                        } label: {
                            Text("Rückgängig")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Stil.akzent)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(Druckknopf())
                    }
                }
                    .padding(.horizontal, 18)
                    .padding(.vertical, modell.rueckgaengig == nil ? 12 : 0)
                    .background(Stil.flaeche, in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .transition(.opacity)
                    .id(text)
                    .task(id: text) {
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        withAnimation(Musikstil.einblenden) {
                            modell.rueckgaengig = nil
                            modell.hinweis = nil
                            modell.spieler.fehler = nil
                            modell.ablage.hinweis = nil
                        }
                    }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .allowsHitTesting(modell.rueckgaengig != nil)
        .animation(Musikstil.einblenden, value: text)
    }
}

/// **Nach oben scrollen** — die Scrollfläche der Wurzelseite, auf der dieser
/// Anker liegt, wenn `zaehler` wächst. Die Seiten müssen davon nichts wissen:
/// gesucht wird die größte senkrechte Scrollfläche unter dem Controller der
/// Seite, wie ein Tipp auf die Statusleiste es tut.
private struct Nachoben: UIViewRepresentable {
    let zaehler: Int

    func makeUIView(context: Context) -> Anker {
        let anker = Anker()
        anker.isUserInteractionEnabled = false
        anker.zuletzt = zaehler
        return anker
    }

    func updateUIView(_ anker: Anker, context: Context) {
        guard zaehler != anker.zuletzt else { return }
        anker.zuletzt = zaehler
        anker.nachOben()
    }

    final class Anker: UIView {
        var zuletzt = 0

        func nachOben() {
            var antwort: UIResponder? = self
            while let r = antwort, !(r is UIViewController) { antwort = r.next }
            guard let wurzel = (antwort as? UIViewController)?.view else { return }
            var beste: UIScrollView?
            func suchen(_ v: UIView) {
                if let flaeche = v as? UIScrollView, !flaeche.isHidden, flaeche.window != nil,
                   flaeche.contentSize.height > flaeche.bounds.height * 0.5,
                   flaeche.bounds.height * flaeche.bounds.width
                   > (beste.map { $0.bounds.height * $0.bounds.width } ?? 0) {
                    beste = flaeche
                }
                for u in v.subviews { suchen(u) }
            }
            suchen(wurzel)
            guard let flaeche = beste else { return }
            flaeche.setContentOffset(CGPoint(x: flaeche.contentOffset.x, y: -flaeche.adjustedContentInset.top),
                                     animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }
}
