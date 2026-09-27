import AVKit
import MusikKit
import SwiftUI

/// **„Abspielen auf": wohin die Musik geht** — ein eigenes Blatt von unten,
/// aufgemacht vom Knopf „Ausgabe" im Wiedergabeblatt.
///
/// Oben „Dieses iPhone", darunter die Swiftly-Geräte desselben Kontos (nur
/// Swiftly Music, keine anderen Jellyfin-Programme), dann die Sonos-Gruppen
/// im Netz — beide Abschnitte nur, wenn es dort etwas gibt —, ganz unten „AirPlay und Bluetooth" — das öffnet Apples Auswahl, die
/// einzige Stelle mit einem Blatt des Systems (eine eigene Liste der
/// AirPlay-Ziele lässt iOS nicht zu). Wo die Musik gerade läuft, steht in
/// `akzent`, mit Pegel.
///
/// Wie jedes Blatt in Swiftly Music über ``Musikblatt``: kein Glas, dieselbe
/// Feder, derselbe Griff.
struct Geraeteebene: View {
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .musikblatt(offen: Binding(get: { modell.fern.blattOffen },
                                       set: { modell.fern.blattOffen = $0 })) {
                Geraeteinhalt()
            }
    }
}

private struct Geraeteinhalt: View {
    @Environment(Musikmodell.self) private var modell
    /// Der Pegel der gewählten Zeile wandert von Zeile zu Zeile.
    @Namespace private var auswahl

    var body: some View {
        let fern = modell.fern
        let sonos = modell.sonos
        let spieler = modell.spieler
        VStack(alignment: .leading, spacing: 0) {
            // Rubrik 17 Semibold wie im Handlungsblatt.
            Text("Abspielen auf")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.136)
                .foregroundStyle(Stil.schrift)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Musikstil.rand)
                .padding(.top, 5)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                VStack(spacing: 0) {
                    Geraetezeile(zeichen: "iphone", name: Text("Dieses iPhone"),
                                 angabe: hierAngabe(spieler), gewaehlt: spieler.fern == nil,
                                 laeuft: spieler.fern == nil && spieler.spielt, auswahl: auswahl) {
                        fern.blattOffen = false
                        if spieler.fern != nil { Task { await fern.hierWeiterhoeren() } }
                    }
                    .modifier(Kartenteil(anfang: true, ende: true))

                    // Nur, was es gibt: ohne ein anderes Swiftly-Gerät kein
                    // Abschnitt dafür, ohne Lautsprecher keiner für Sonos
                    // (25.09.).
                    if fern.verfuegbar, fern.geraeteGeladen, !fern.geraete.isEmpty {
                        Abschnittstitel(text: Text("Swiftly-Geräte"))
                        ForEach(fern.geraete) { s in
                            let gewaehlt = fern.ziel?.sitzungID == s.id
                            Geraetezeile(zeichen: s.zeichen, name: Text(verbatim: s.geraetename),
                                         angabe: angabe(s, gewaehlt: gewaehlt, spieler: spieler),
                                         gewaehlt: gewaehlt,
                                         laeuft: gewaehlt ? spieler.spielt : s.spielt, auswahl: auswahl) {
                                fern.waehlen(s)
                            }
                            .disabled(fern.beschaeftigt)
                            .modifier(Kartenteil(anfang: true, ende: true))
                        }
                    }

                    if !sonos.gruppen.isEmpty {
                        Abschnittstitel(text: Text(verbatim: "Sonos"))
                        Sonosliste(auswahl: auswahl)
                    }
                }
                .padding(.horizontal, 12)
                // **Ein Wechsel bewegt, statt zu springen**: der Pegel wandert
                // zur neuen Zeile, Abschnitte blenden weich ein.
                .animation(Musikstil.blattbewegung, value: spieler.fern?.sitzungID)
                .animation(Musikstil.blattbewegung, value: fern.geraete.map(\.id))
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 480)
            .fixedSize(horizontal: false, vertical: true)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            Blattlinie()
            Systemausgabezeile()
        }
        .padding(.bottom, 4)
    }

    /// Unter „Dieses iPhone": wohin der Ton hier geht, wenn nicht in den
    /// eingebauten Lautsprecher — „AirPods Pro", „Wohnzimmer".
    private func hierAngabe(_ spieler: Spieler) -> String? {
        let name = spieler.ausgabename
        return name.isEmpty || name == UIDevice.current.model ? nil : name
    }

    /// Was dort läuft — beim gewählten Gerät der Stand, wie ihn das Blatt zeigt.
    private func angabe(_ s: Musiksitzung, gewaehlt: Bool, spieler: Spieler) -> String? {
        let lied = gewaehlt ? spieler.aktuell : s.lied
        guard let lied else { return s.programm }
        return [lied.titel, lied.kuenstlerzeile].compactMap { $0 }.joined(separator: " · ")
    }
}

/// **Ein Gerät im Blatt, ruhig wie in der Sonos-App**: Zeichen, Name,
/// darunter klein, was dort läuft. Gewählt sind Name und Zeichen in `akzent`
/// und rechts der Pegel — kein Gewichtswechsel (BRAND.md §5, „Gewählt ändert
/// kein Maß"), also kein Sprung in der Liste, wenn die Wahl wechselt.
private struct Geraetezeile: View {
    let zeichen: String
    let name: Text
    let angabe: String?
    let gewaehlt: Bool
    let laeuft: Bool
    let auswahl: Namespace.ID
    let tun: () -> Void

    var body: some View {
        Button(action: tun) {
            HStack(spacing: 12) {
                Image(systemName: zeichen)
                    .font(.system(size: 19))
                    .frame(width: 28)
                    .foregroundStyle(gewaehlt ? Stil.akzent : Stil.schrift)
                VStack(alignment: .leading, spacing: 1) {
                    name
                        .font(.system(size: 16))
                        .foregroundStyle(gewaehlt ? Stil.akzent : Stil.schrift)
                        .lineLimit(1)
                    if let angabe {
                        Text(verbatim: angabe)
                            .font(.system(size: 13))
                            .foregroundStyle(Stil.schriftLeise)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if gewaehlt {
                    Auswahlpegel(laeuft: laeuft, auswahl: auswahl)
                } else if laeuft {
                    Pegel(laeuft: laeuft)
                        .opacity(0.6)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(Druckknopf())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(gewaehlt ? [.isButton, .isSelected] : .isButton)
    }
}

/// **Der Pegel der gewählten Zeile** — es gibt ihn einmal im Blatt, und er
/// gleitet von Zeile zu Zeile, von „Dieses iPhone" zum Lautsprecher und
/// zurück. Mit reduzierter Bewegung blendet er nur über.
struct Auswahlpegel: View {
    let laeuft: Bool
    let auswahl: Namespace.ID

    var body: some View {
        Pegel(laeuft: laeuft)
            .matchedGeometryEffect(id: Musikstil.bewegungReduziert ? "aus" : "ausgabe",
                                   in: auswahl, isSource: true)
            .transition(.opacity)
    }
}

/// **Eine Karte oder ein Stück davon.** Beginnt die Zeile eine Karte, ist
/// sie oben rund und hat Luft darüber; endet sie eine, ist sie unten rund.
/// Rücken zwei Lautsprecher zu einer Gruppe zusammen, laufen Ecken und Luft
/// dazwischen mit der Feder auf null — die zwei Karten verschmelzen zu
/// einer, und beim Trennen teilen sie sich genau rückwärts.
struct Kartenteil: ViewModifier {
    let anfang: Bool
    let ende: Bool

    func body(content: Content) -> some View {
        let r = Musikstil.eckeMini
        content
            .background(Stil.flaeche,
                        in: UnevenRoundedRectangle(topLeadingRadius: anfang ? r : 0,
                                                   bottomLeadingRadius: ende ? r : 0,
                                                   bottomTrailingRadius: ende ? r : 0,
                                                   topTrailingRadius: anfang ? r : 0,
                                                   style: .continuous))
            .padding(.top, anfang ? 8 : 0)
    }
}

/// **Über jedem Abschnitt im Blatt** — leise, im Maß der Zeilen darunter.
private struct Abschnittstitel: View {
    let text: Text

    var body: some View {
        text
            .font(Musikstil.zeile)
            .foregroundStyle(Stil.schriftLeise)
            .frame(maxWidth: .infinity, alignment: .leading)
            // In der Spalte der Karten (12 eingerückt): auf dem Rand des Blatts.
            .padding(.horizontal, Musikstil.rand - 12)
            .padding(.top, 16)
            .accessibilityAddTraits(.isHeader)
    }
}

/// **„AirPlay und Bluetooth"** — darüber unsichtbar Apples Auswahl
/// (`AVRoutePickerView`), die den Tipp fängt und die Liste der Lautsprecher
/// und Kopfhörer öffnet. Derselbe Griff wie vorher am Knopf „Ausgabe".
private struct Systemausgabezeile: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "airplay.audio")
                .font(.system(size: 20))
                .frame(width: 28)
            Text("AirPlay und Bluetooth")
                .font(.system(size: 17))
            Spacer(minLength: 0)
            Symbolbild(zeichen: .winkelRechts, groesse: 13)
                .foregroundStyle(Stil.schriftSehrLeise)
        }
        .foregroundStyle(Stil.schrift)
        .padding(.horizontal, Musikstil.rand)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .overlay { Systemausgabewahl().accessibilityLabel(Text("AirPlay und Bluetooth")) }
    }
}

private struct Systemausgabewahl: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let wahl = AVRoutePickerView()
        wahl.tintColor = .clear
        wahl.activeTintColor = .clear
        wahl.prioritizesVideoDevices = false
        return wahl
    }

    func updateUIView(_ wahl: AVRoutePickerView, context: Context) {}
}

// MARK: - Das Angebot

/// **„Läuft auf ‹Gerät›" mit „Hier weiterhören"** — ein Streifen über dem
/// Mini-Player. Ein Angebot, kein Zwang: wer ihn übersieht, dem passiert
/// nichts; das Kreuz nimmt ihn weg, bis dort etwas anderes läuft.
///
/// Ein Tipp auf den Text verbindet nur (Jellyfin) — dann steuert man von
/// hier, was drüben läuft.
struct Angebotsstreifen: View {
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        ZStack {
            if let a = modell.angebot {
                HStack(spacing: 10) {
                    Button { modell.angebotSteuern() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: a.zeichen)
                                .font(.system(size: 17))
                                .foregroundStyle(Stil.akzent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: a.titel)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Stil.akzent)
                                    .lineLimit(1)
                                if let lied = a.lied {
                                    Text(verbatim: [lied.titel, lied.kuenstlerzeile].compactMap { $0 }
                                        .joined(separator: " · "))
                                        .font(Musikstil.angabe)
                                        .foregroundStyle(Stil.schriftLeise)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(Druckknopf())
                    .accessibilityElement(children: .combine)

                    Button { modell.angebotAnnehmen() } label: {
                        Text("Hier weiterhören")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Stil.schrift)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Stil.erhoeht, in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(Druckknopf())

                    Button { modell.angebotAblehnen() } label: {
                        Symbolbild(zeichen: .kreuz, groesse: 11)
                            .foregroundStyle(Stil.schriftSehrLeise)
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(Druckknopf())
                    .accessibilityLabel(Text("Schließen"))
                }
                .padding(.leading, 14)
                .padding(.trailing, 4)
                .frame(minHeight: 58)
                .background(Stil.flaeche,
                            in: RoundedRectangle(cornerRadius: Musikstil.eckeMini, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Musikstil.blattbewegung, value: modell.angebot?.id)
    }
}
