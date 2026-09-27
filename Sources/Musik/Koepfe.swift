import MusikKit
import SwiftUI

/// **Der Kopf einer Wurzelseite**: ein Verlauf von `grund` 94 % nach klar —
/// keine Unschärfe —, der Inhalt läuft darunter durch.
///
/// **Maße wie im Player** (`Unschaerfekopf` und `contentMargins(.top, 58)`
/// in `HomeView`): oben ohne Abstand unter der Statusleiste, eine Zeile von
/// 44 und darunter 14 — die erste Reihe beginnt 58 + 8 unter der
/// Statusleiste. Vorher 4 / 22: „Zuletzt hinzugefügt" stand 12 Punkt tiefer
/// als „Weiterschauen".
struct Wurzelkopf<Inhalt: View>: View {
    var unten: CGFloat = 14
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        inhalt()
            .padding(.horizontal, Musikstil.rand)
            .padding(.bottom, unten)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LinearGradient(stops: [.init(color: Stil.grund.opacity(0.94), location: 0),
                                       .init(color: Stil.grund.opacity(0.90), location: 0.45),
                                       .init(color: Stil.grund.opacity(0.60), location: 0.70),
                                       .init(color: Stil.grund.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
    }
}

/// Das Profilzeichen oben rechts; ein Tipp schiebt das Konto von rechts
/// herein (`Profilziel` in `Stil.swift`).
struct Kontoziel: View {
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        Button { modell.kontoOeffnen() } label: {
            Profilzeichen(name: modell.benutzername,
                          bild: modell.quelle?.profilbildadresse(kante: 120))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(Druckknopf())
        .padding(.trailing, -7)
        .accessibilityLabel(Text("Konto"))
    }
}

/// **Der Rückweg jeder Unterseite** — `Zurueckknopf` aus `Stil.swift`, 1:1:
/// ein blanker Pfeil `chevron.left` 20 Semibold, kein Kreis, 44 × 44 als
/// Ziel. Einmal gebaut statt an jeder Stelle neu — die Quick-Connect-Seite
/// und die Detailleiste hatten eigene, mit einem anderen Pfeil.
struct Zurueckknopf: View {
    let tun: () -> Void

    var body: some View {
        Button(action: tun) {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Stil.schrift)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(Druckknopf())
        .accessibilityLabel(Text("Zurück"))
    }
}

/// **Kopf einer Unterseite**: Pfeil links, Titel 22 Semibold linksbündig
/// daneben — kein zentrierter Titel, kein grauer Kreis (`Unterseitenkopf`
/// und `Zurueckknopf` in `Stil.swift`).
struct Unterseitenkopf: View {
    let titel: Text
    @Environment(\.dismiss) private var zurueck

    var body: some View {
        HStack(spacing: 4) {
            Zurueckknopf { zurueck() }

            titel
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.308)
                .foregroundStyle(Stil.schrift)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.bottom, 18)
    }
}

/// **Die Sortierpille**: eine Kapsel mit Sortierzeichen 13 und dem Wert,
/// der gilt; dahinter Swiftlys Auswahlblatt.
struct Sortierpille<Wert: Hashable>: View {
    let werte: [Wert]
    @Binding var gewaehlt: Wert
    let name: (Wert) -> String
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        Button {
            let bindung = $gewaehlt
            modell.handlungen = Handlungen.auswahl(String(localized: "Sortierung"), werte: werte,
                                                   gewaehlt: gewaehlt, name: name) { bindung.wrappedValue = $0 }
        } label: {
            HStack(spacing: 6) {
                Symbolbild(zeichen: .sortieren, groesse: 13)
                Text(verbatim: name(gewaehlt))
                    .font(Musikstil.kapsel)
                    .lineLimit(1)
            }
            .foregroundStyle(Stil.schriftLeise)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(Stil.flaeche, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(Druckknopf())
        .accessibilityLabel(Text("Sortierung"))
        .accessibilityValue(Text(verbatim: name(gewaehlt)))
    }
}

/// **Oben über einem Heldbild**: der Zurückpfeil in 44 × 44 bei x 10, rechts
/// „Mehr". Scrollt das Bild weg, legt sich der Grund darunter und der Titel
/// blendet in 17 Semibold ein (BRAND.md §7, „über einem Heldbild").
struct Detailleiste<Mehr: View>: View {
    let titel: String
    /// 0 über dem Bild, 1, sobald es weggescrollt ist.
    let deckung: Double
    /// **Die Seite deckt selbst** (``Seitenhintergrund``): die Leiste tönt
    /// sich in ``farbe`` statt in `grund`.
    var seitenfarbe = false
    /// Die Farbe der Seite, für ``Titelleistenglas`` — ohne Seitenfarbe
    /// bleibt es bei `grund`.
    var farbe: Color = Stil.grund
    @ViewBuilder var mehr: () -> Mehr
    @Environment(\.dismiss) private var zurueck

    var body: some View {
        HStack(spacing: 4) {
            Zurueckknopf { zurueck() }

            Text(verbatim: titel)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Stil.schrift)
                .lineLimit(1)
                .opacity(deckung)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(deckung < 0.5)

            mehr()
        }
        // 8 wie im Unterseitenkopf (`Detailkopf` im Player) — der Pfeil
        // steht auf jeder Seite an derselben Stelle.
        .padding(.leading, 8)
        .padding(.trailing, 10)
        // Der Pfeil sitzt bei y 52, zwei Punkt über der Kante der Statusleiste.
        .padding(.top, -2)
        .padding(.bottom, 4)
        .background {
            ZStack {
                // **Ein eigener Verlauf hinter Pfeil und „Mehr"** (`Detailkopf`
                // im Player): er hält beide auf jedem Heldbild lesbar, auch
                // wo das Bild oben hell ist — der Verlauf im Bild allein
                // reichte dort nicht. Deckt der Grund, geht er.
                Kopfverlauf().opacity(0.7 * (1 - deckung))
                // **Eine echte Unschärfe statt nur der Hintergrundfarbe**
                // (24.09.): dieselbe Machart wie `Leistenglas` in
                // `Leiste.swift`, aber in der Farbe der Seite, nicht in
                // `grund` — bis ganz oben, hinter die Statusleiste.
                if deckung > 0 {
                    Titelleistenglas(farbe: seitenfarbe ? farbe : Stil.grund)
                        .opacity(deckung)
                        .ignoresSafeArea(edges: .top)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Stil.linie).frame(height: 1).opacity(deckung)
            }
        }
    }
}

/// **Nur die Unschärfe, keine Farbe** (25.09.: „Da soll gar keine
/// Farbe sein, nur ein Blur") — dasselbe Glas wie `Leistenglas`
/// (`Leiste.swift`, dieselbe `UIVisualEffectView`, kein Liquid Glass), ohne
/// eigene Tönung: der darunter scrollende Inhalt bleibt durch das Glas
/// sichtbar. `systemUltraThinMaterialDark` dunkelt für sich genommen schon
/// ab, das trägt Titel und Knöpfe (`Stil.schrift`, weiß) — ``farbe`` bleibt
/// als Parameter für den Aufrufer, wird aber nicht mehr gezeichnet.
private struct Titelleistenglas: View {
    let farbe: Color

    var body: some View {
        Unschaerfe()
            .allowsHitTesting(false)
    }
}

/// **Der Verlauf unter einem Kopf** — `Kopfverlauf` aus `Stil.swift`, 1:1:
/// neun Stufen gegen `grund`, nach dem Gefälle gesetzt, nicht nach dem
/// Endwert, und 17 Punkt über den Kopf hinaus.
struct Kopfverlauf: View {
    var zugabe: CGFloat = 17

    var body: some View {
        LinearGradient(stops: [
            .init(color: Stil.grund.opacity(0.98), location: 0),
            .init(color: Stil.grund.opacity(0.94), location: 0.30),
            .init(color: Stil.grund.opacity(0.85), location: 0.48),
            .init(color: Stil.grund.opacity(0.70), location: 0.62),
            .init(color: Stil.grund.opacity(0.52), location: 0.73),
            .init(color: Stil.grund.opacity(0.34), location: 0.82),
            .init(color: Stil.grund.opacity(0.19), location: 0.89),
            .init(color: Stil.grund.opacity(0.09), location: 0.95),
            .init(color: Stil.grund.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .padding(.bottom, -zugabe)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

/// Das weiße „Mehr" oben rechts über dem Heldbild.
struct Heldmehr: View {
    let liste: @MainActor () -> Handlungsliste
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        Button { modell.handlungen = liste() } label: {
            Symbolbild(zeichen: .mehr, groesse: 22)
                .foregroundStyle(Stil.schrift)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(Druckknopf())
        .accessibilityLabel(Text("Mehr"))
    }
}

/// **Die Verläufe über einem Heldbild**: oben 110 (`grund` 80 % → klar),
/// unten 150 (klar → 60 % → `grund`).
struct Heldverlaeufe: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Stil.grund.opacity(0.8), Stil.grund.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
            Spacer(minLength: 0)
            LinearGradient(stops: [.init(color: Stil.grund.opacity(0), location: 0),
                                   .init(color: Stil.grund.opacity(0.6), location: 0.45),
                                   .init(color: Stil.grund, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
        }
        .allowsHitTesting(false)
    }
}

/// Wie weit ein Heldbild weggescrollt ist — für die Detailleiste.
struct Scrolldeckung: ViewModifier {
    let heldhoehe: CGFloat
    @Binding var deckung: Double

    /// Über 70 Punkt Weg ab 150 vor dem Ende des Bilds — die Werte des
    /// `Detailkopf` im Player; 44 ab 140 kam knapp und abrupt. Auch der
    /// ``Seitenhintergrund`` rechnet damit, wann er unter die Leiste tritt.
    static func deckung(versatz: CGFloat, heldhoehe: CGFloat) -> Double {
        Double(min(max((versatz - (heldhoehe - 150)) / 70, 0), 1))
    }

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { g in
            g.contentOffset.y + g.contentInsets.top
        } action: { _, versatz in
            let neu = Self.deckung(versatz: versatz, heldhoehe: heldhoehe)
            if abs(neu - deckung) > 0.01 || (neu == 0) != (deckung == 0) || (neu == 1) != (deckung == 1) {
                deckung = neu
            }
        }
    }
}

// MARK: - Kapselwahl

/// **Die Kapseln über einer Liste** — Bibliothek und Suche teilen sie (24.09.): ohne Auswahl gilt alles, ein Tipp wählt genau eine, ein zweiter
/// Tipp auf dieselbe hebt sie auf. Es gibt keine Kapsel „Alles".
///
/// Die Wahl gilt sofort; die Liste darunter wartet auf nichts, was die
/// Kapsel bräuchte (``Kapselinhalt``).
struct Kapselwahl<Wert: Hashable & Identifiable>: View {
    let werte: [Wert]
    let name: (Wert) -> LocalizedStringKey
    @Binding var gewaehlt: Wert?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(werte) { w in
                    Kapsel(text: name(w), an: gewaehlt == w) {
                        gewaehlt = gewaehlt == w ? nil : w
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// **Die Liste unter den Kapseln, beim Wechsel ausgetauscht statt umgebaut.**
///
/// Vorher zog jede Zeile an ihren neuen Platz. Beim Abwählen liegen die
/// Einträge einer Art in der gemischten Liste weit auseinander, die Zeilen
/// flogen quer über den Schirm, und schnelles Hin und Her stapelte diese
/// Bewegungen. Jetzt bekommt jede Wahl eine eigene Liste: die alte geht in
/// 60 ms, die neue blendet in 160 ms ein. Bewegt wird nur die Kapsel.
///
/// Die `.id` liegt in einem `ZStack`, damit alte und neue Liste für den
/// Augenblick übereinander stehen statt untereinander, und damit ein
/// umgebender `LazyVStack` sie nicht für die Kennung einer Zeile hält
/// (``Wischzeile``).
struct Kapselinhalt<Schluessel: Hashable, Inhalt: View>: View {
    let schluessel: Schluessel
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        ZStack(alignment: .top) {
            inhalt()
                .id(schluessel)
                .transition(.asymmetric(insertion: .opacity,
                                        removal: .opacity.animation(.linear(duration: 0.06))))
        }
        .animation(.easeOut(duration: 0.16), value: schluessel)
    }
}

extension ScrollPosition {
    /// Ohne Bewegung an den Anfang — beim Wechsel der Kapsel steht die neue
    /// Liste oben, statt mitten in sich zu beginnen.
    mutating func sofortNachOben() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { scrollTo(edge: .top) }
    }
}
