import MusikKit
import SwiftUI

// **Swiftlys eigene Blätter statt der Systemmenüs.**
//
// Menüs, Kontextmenüs und Rückfragen des Systems erscheinen unter iOS 26 als
// Liquid Glass — Swiftly soll aber auf jedem System gleich aussehen. Deshalb
// geht jede Auswahl und jede Handlungsliste über dasselbe Blatt von unten,
// das der Player für „Mehr" und Auswahl nutzt (`Blattmodifikator`,
// `Handlungsblatt` und `Auswahlblatt` in `Sources/Shared/Stil.swift`).
// Nachgebaut statt geteilt, weil `Stil.swift` nicht ohne `AppModel` übersetzt.

// MARK: - Inhalt

/// Eine Zeile in einem Blatt: sie löst etwas aus, und das Blatt schließt.
struct Handlung: Identifiable {
    let id = UUID()
    let text: String
    var symbol: String?
    /// **Ein eigenes Zeichen statt eines SF-Symbols** — für Handlungen, die
    /// es auch als Knopf gibt: Abspielen, Zufall, Herz, Sofortmix. So sieht
    /// Abspielen im Blatt aus wie auf der Seite und im Spieler, statt je
    /// nach Ort anders (`Zeichen`).
    var zeichen: Zeichen?
    /// **Die Kachel der Lieblingssongs** statt eines Zeichens — in „Zu
    /// Playlist hinzufügen" steht die Sammlung so da wie in der Bibliothek.
    var lieblingskachel = false
    /// Rot — wo etwas verloren geht.
    var warnend = false
    /// Nur in einer Auswahl: ob dieser Wert gerade gilt. Dann steht vorn
    /// ein Haken statt eines Zeichens.
    var gewaehlt: Bool?
    let tun: @MainActor () -> Void
}

/// Was ein Blatt zeigt: eine Rubrik, auf Wunsch ein Satz darunter, und die
/// Zeilen.
struct Handlungsliste: Identifiable {
    let id = UUID()
    /// Woran das Blatt arbeitet — ein Albumtitel, „Sortierung", „Abmelden?".
    let titel: String
    var hinweis: String?
    let handlungen: [Handlung]
}

// MARK: - Das Blatt

/// **Ein Blatt von unten** — die Bewegung aus `Blattmodifikator`: Gummikante
/// nach oben, der Schwung des Fingers geht in die Feder, geschlossen wird ab
/// einem Viertel der Höhe oder 700 Punkt je Sekunde, und die Fläche reicht
/// unten weiter, als die Karte je fährt.
struct Musikblatt<Blattinhalt: View>: ViewModifier {
    @Binding var offen: Bool
    @ViewBuilder var blattinhalt: () -> Blattinhalt

    @State private var kartenhoehe: CGFloat = 400
    @State private var zug: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay { blatt }
    }

    private var blatt: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(offen ? 0.55 * (1 - anteil) : 0))
                .ignoresSafeArea()
                .animation(Musikstil.blattbewegung, value: offen)
                .onTapGesture { schliessen(mit: 0) }

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .accessibilityHidden(true)

                blattinhalt()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: Musikstil.eckeBlatt,
                                       topTrailingRadius: Musikstil.eckeBlatt,
                                       style: .continuous)
                    .fill(Stil.flaeche)
                    .padding(.bottom, -400)
                    .ignoresSafeArea(edges: .bottom)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { kartenhoehe = $0 }
            .offset(y: offen ? zug : kartenhoehe + 400)
            .animation(Musikstil.blattbewegung, value: offen)
            .gesture(ziehen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(offen)
        .accessibilityAction(.escape) { if offen { schliessen(mit: 0) } }
    }

    private var anteil: Double {
        Double(min(max(zug, 0) / max(kartenhoehe, 1), 1))
    }

    private var ziehen: some Gesture {
        DragGesture()
            .onChanged { wert in
                let weg = wert.translation.height
                zug = weg >= 0 ? weg : -Blattphysik.gummi(-weg, hoehe: kartenhoehe)
            }
            .onEnded { wert in
                let schnell = wert.velocity.height
                if wert.translation.height > kartenhoehe * 0.25 || schnell > 700 {
                    schliessen(mit: schnell)
                } else {
                    withAnimation(Blattphysik.feder(von: zug, nach: 0, schwung: schnell)) { zug = 0 }
                }
            }
    }

    private func schliessen(mit schwung: CGFloat) {
        withAnimation(Blattphysik.feder(von: zug, nach: kartenhoehe + 400, schwung: schwung)) {
            offen = false
            zug = 0
        }
    }
}

/// Die Rechnung hinter jedem Blatt — beim Handlungsblatt wie beim
/// Wiedergabeblatt dieselbe.
enum Blattphysik {
    /// Die Gummikante von `UIScrollView`: je weiter man zieht, desto weniger
    /// gibt es nach. `c = 0,55` ist Apples Beiwert.
    static func gummi(_ weg: CGFloat, hoehe: CGFloat) -> CGFloat {
        let d = max(hoehe, 1)
        return (1 - (1 / (weg * 0.55 / d + 1))) * d
    }

    /// Eine Feder, die den Schwung des Fingers übernimmt. `initialVelocity`
    /// zählt in Wertänderung je Sekunde, nicht in Punkten — deshalb durch
    /// die Restentfernung teilen.
    @MainActor
    static func feder(von stelle: CGFloat, nach ziel: CGFloat, schwung: CGFloat) -> Animation {
        if Musikstil.bewegungReduziert { return Musikstil.blendeReduziert }
        let strecke = max(abs(ziel - stelle), 1)
        let richtung: CGFloat = ziel >= stelle ? 1 : -1
        let anfang = min(max(Double(schwung * richtung / strecke), -25), 25)
        return .interpolatingSpring(mass: 1, stiffness: 280, damping: 32, initialVelocity: anfang)
    }

    /// **Die Feder des Wiedergabeblatts, auf und zu dieselbe** — die von
    /// ``Musikstil/blattbewegung`` (0,35 s, 14 % Nachfedern), dazu der
    /// Schwung des Fingers (24.09.: beim Öffnen federt es schön nach,
    /// beim Schließen soll es genauso). Wie ``feder(von:nach:schwung:)``
    /// zählt der Schwung in Anteilen des Rests je Sekunde.
    ///
    /// **Ein schneller Wurf federt nicht nach** (25.09.: beim schnellen
    /// Schließen schlug das Cover aus). Mit 0,14 Nachfedern schießt die
    /// Feder bei 25 Rest je Sekunde rund 40 Punkt über die Pille hinaus. Ab
    /// 6 Rest je Sekunde nimmt das Nachfedern ab, ab 12 ist die Feder
    /// kritisch gedämpft; der Schwung zählt höchstens bis 20 — dort schießt
    /// auch die gedämpfte Feder nicht mehr über (gerechnet: unter 0,1 Punkt).
    @MainActor
    static func blattfeder(von stelle: CGFloat, nach ziel: CGFloat, schwung: CGFloat) -> Animation {
        if Musikstil.bewegungReduziert { return Musikstil.blendeReduziert }
        let strecke = max(abs(ziel - stelle), 1)
        let richtung: CGFloat = ziel >= stelle ? 1 : -1
        let anfang = min(max(Double(schwung * richtung / strecke), -20), 20)
        let nachfedern = 0.14 * min(max((12 - anfang) / 6, 0), 1)
        return .interpolatingSpring(duration: 0.35, bounce: nachfedern, initialVelocity: anfang)
    }
}

extension View {
    /// Ein Blatt von unten. **Immer anhängen, nie in ein `if offen`** —
    /// sonst sitzt die Karte beim Einhängen schon und das Auffahren fällt aus.
    func musikblatt<Inhalt: View>(offen: Binding<Bool>,
                                  @ViewBuilder inhalt: @escaping () -> Inhalt) -> some View {
        modifier(Musikblatt(offen: offen, blattinhalt: inhalt))
    }
}

// MARK: - Die Handlungsliste

/// **Das eine Blatt für „Mehr", langen Druck, Auswahl und Rückfragen.** Es
/// liegt über allem, auch über dem Wiedergabeblatt, und zeigt, was in
/// `Musikmodell.handlungen` steht.
struct Handlungsebene: View {
    @Environment(Musikmodell.self) private var modell
    /// Beim Schließen ist `handlungen` schon leer, die Karte fährt aber noch
    /// hinaus — solange steht hier, was sie zeigte.
    @State private var zuletzt: Handlungsliste?
    /// **Was das Blatt zeigt, steht schon im Baum, bevor es aufgeht.** Hing
    /// der Inhalt direkt an `modell.handlungen`, entstand er im selben
    /// Augenblick, in dem das Blatt aufging: eine neu eingefügte Ansicht
    /// steht sofort an ihrer Endstelle und fährt den animierten Versatz des
    /// Blatts nicht mit — Text und Knöpfe standen schon da, das Blatt kam
    /// darunter nach. Jetzt steht `zuletzt` zuerst, und das Blatt geht einen
    /// Takt später auf.
    @State private var offen = false

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .musikblatt(offen: Binding(get: { offen },
                                       set: { if !$0 { offen = false; modell.handlungen = nil } })) {
                if let liste = zuletzt {
                    Handlungsinhalt(liste: liste) { modell.handlungen = nil }
                }
            }
            .onChange(of: modell.handlungen?.id) { _, neu in
                guard neu != nil, let liste = modell.handlungen else {
                    offen = false
                    return
                }
                zuletzt = liste
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(30))
                    offen = modell.handlungen != nil
                }
            }
    }
}

private struct Handlungsinhalt: View {
    let liste: Handlungsliste
    let schliessen: () -> Void
    @State private var inhaltshoehe: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Rubrik 17 Semibold ohne Linie darunter (`Blattrubrik`).
            Text(verbatim: liste.titel)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.136)
                .foregroundStyle(Stil.schrift)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Musikstil.rand)
                .padding(.top, 5)
                .padding(.bottom, liste.hinweis == nil ? 14 : 4)
                .accessibilityAddTraits(.isHeader)
            if let hinweis = liste.hinweis {
                Text(verbatim: hinweis)
                    .font(.system(size: 15))
                    .foregroundStyle(Stil.schriftLeise)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Musikstil.rand)
                    .padding(.bottom, 14)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(liste.handlungen.enumerated()), id: \.element.id) { i, handlung in
                        if i > 0 { Blattlinie() }
                        Button {
                            schliessen()
                            handlung.tun()
                        } label: {
                            zeile(handlung)
                        }
                        .buttonStyle(Zeilendruck.randbreit)
                        .accessibilityAddTraits(handlung.gewaehlt == true ? .isSelected : [])
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { inhaltshoehe = $0 }
            }
            .frame(height: min(inhaltshoehe, 420))
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            Blattlinie()
            Button(action: schliessen) {
                Text("Abbrechen")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Stil.schriftLeise)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(Zeilendruck.randbreit)
        }
    }

    private func zeile(_ handlung: Handlung) -> some View {
        HStack(spacing: 14) {
            if let gewaehlt = handlung.gewaehlt {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    // Der Haken in Akzent: er ist der Zustand, nicht die Zeile.
                    .foregroundStyle(gewaehlt ? Stil.akzent : .clear)
                    .frame(width: 20)
            } else if handlung.lieblingskachel {
                // 26 statt 20: eine Kachel braucht etwas mehr als ein Zeichen,
                // um zu lesen. Sie steht über die Spalte hinaus, der Text nicht.
                Lieblingskachel()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(width: 20)
            } else if let zeichen = handlung.zeichen {
                Symbolbild(zeichen: zeichen, groesse: 20)
                    .frame(width: 20)
            } else if let symbol = handlung.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .frame(width: 20)
            }
            Text(verbatim: handlung.text)
                .font(.system(size: 17, weight: handlung.gewaehlt == true ? .semibold : .regular))
            Spacer(minLength: 0)
        }
        .foregroundStyle(handlung.warnend ? Stil.warnung
                         : handlung.gewaehlt == false ? Stil.schriftLeise : Stil.schrift)
        .padding(.horizontal, Musikstil.rand)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Die Linie in einem Blatt — von Kartenrand zu Kartenrand (`Blattlinie`).
struct Blattlinie: View {
    var body: some View {
        Rectangle().fill(Stil.linie).frame(height: 1)
    }
}

// MARK: - Langer Druck

/// **Langer Druck öffnet die Handlungen** — statt des Kontextmenüs, das unter
/// iOS 26 als Glas aufgeht. Nach 0,45 s ein mittlerer Ruck und das Blatt.
///
/// Der Knopf darunter feuert beim Loslassen trotzdem; deshalb fragt jeder
/// Knopf mit langem Druck vor seiner Handlung, ob schon ein Blatt offen ist
/// (``Musikmodell/frei``).
struct LangerDruck: ViewModifier {
    let liste: @MainActor () -> Handlungsliste?
    @Environment(Musikmodell.self) private var modell

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        guard modell.handlungen == nil, let neu = liste() else { return }
                        Musikstil.ruck(.mittel)
                        modell.handlungen = neu
                    }
            )
            .accessibilityAction(named: Text("Mehr")) {
                if let neu = liste() { modell.handlungen = neu }
            }
    }
}

extension View {
    func langerDruck(_ liste: @escaping @MainActor () -> Handlungsliste?) -> some View {
        modifier(LangerDruck(liste: liste))
    }
}
