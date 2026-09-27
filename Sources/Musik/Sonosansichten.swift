import MusikKit
import SwiftUI

// MARK: - Im Blatt „Abspielen auf"

/// **Die Lautsprecher im Blatt „Abspielen auf"** — klein und ruhig wie in
/// der Sonos-App. Oben die, auf denen unsere Musik läuft, auf einer
/// gemeinsamen Karte und **jeder mit seinem Regler** — so lässt sich auch in
/// der Gruppe jeder einzeln regeln. Darunter die übrigen, nur Bild, Name und
/// leerer Kreis.
///
/// - **Tipp auf die Zeile:** nur noch dieser Lautsprecher spielt
///   (``Sonosmodell/alleinSpielen(_:)``).
/// - **Tipp auf den Kreis:** leer holt ihn dazu (läuft noch nichts auf Sonos:
///   dorthin), Haken nimmt ihn heraus. Der Kreis füllt sich sofort, die Zeile
///   wandert nach oben und bekommt ihren Regler, die Karten verschmelzen
///   (``Kartenteil``) — alles in einer Feder, rückwärts genauso.
struct Sonosliste: View {
    let auswahl: Namespace.ID
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        let sonos = modell.sonos
        let spieler = modell.spieler
        // Unsere Gruppe steht fest, sobald der Tipp beim Spieler ist — nicht
        // erst, wenn der Lautsprecher antwortet.
        let ziel: String? = spieler.fern?.art == .sonos
            ? spieler.fern.map { String($0.sitzungID.dropFirst("sonos:".count)) } : nil
        let zeilen = Sonoszeile.zeilen(sonos.gruppen, ziel: ziel, vorgemerkt: sonos.vorgemerkt)
        let unsere = zeilen.filter(\.unser).count
        VStack(spacing: 0) {
            ForEach(zeilen) { z in
                Lautsprecherzeile(zeile: z, allein: z.unser && unsere == 1,
                                  laeuft: z.unser && spieler.spielt, auswahl: auswahl)
                    .modifier(Kartenteil(anfang: z.kopf, ende: z.ende))
            }
        }
        .animation(Musikstil.blattbewegung, value: zeilen)
        .animation(Musikstil.blattbewegung, value: ziel)
    }
}

/// **Ein Lautsprecher**: Bild, Name, rechts der Kreis; spielt er unsere
/// Musik, darunter sein Regler.
private struct Lautsprecherzeile: View {
    let zeile: Sonoszeile
    /// Der einzige, der unsere Musik spielt — sein Haken bleibt.
    let allein: Bool
    let laeuft: Bool
    let auswahl: Namespace.ID
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        let sonos = modell.sonos
        let l = zeile.lautsprecher
        let unser = zeile.unser
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button { sonos.alleinSpielen(l) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: sonos.bilder[l.id] ?? "hifispeaker.fill")
                            .font(.system(size: 19))
                            .frame(width: 28)
                        Text(verbatim: l.name)
                            .font(.system(size: 16))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if unser, zeile.kopf {
                            Auswahlpegel(laeuft: laeuft, auswahl: auswahl)
                                .padding(.trailing, 4)
                        }
                    }
                    .foregroundStyle(unser ? Stil.akzent : Stil.schrift)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(Druckknopf())
                .disabled(sonos.beschaeftigt)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(unser ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(Text("Nur hier abspielen"))

                Gruppenkreis(drin: unser, name: l.name) {
                    if sonos.ziel == nil { sonos.alleinSpielen(l) } else { sonos.umschalten(l) }
                }
                .disabled(sonos.beschaeftigt || allein)
            }

            if unser {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Stil.schriftLeise)
                        .accessibilityHidden(true)
                    Lautstaerkeregler(wert: sonos.lautstaerken[l.id], name: Text(verbatim: l.name), setzen: {
                        sonos.lautstaerkeSetzen(l, $0)
                    }, hoch: 24)
                }
                // Unter dem Namen: Bild (28) und Abstand (12); rechts bis unter den Kreis.
                .padding(.leading, 40)
                .padding(.trailing, 44)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .padding(.leading, 12)
    }
}

/// **Der Kreis rechts**: leer = nicht dabei, Haken = in unserer Gruppe. Er
/// füllt sich beim Tipp sofort (``Sonosmodell/vorgemerkt``).
private struct Gruppenkreis: View {
    let drin: Bool
    let name: String
    let tun: () -> Void

    var body: some View {
        Button(action: tun) {
            Image(systemName: drin ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(drin ? Stil.akzent : Stil.schriftSehrLeise)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(Druckknopf())
        .accessibilityLabel(drin ? Text("Aus der Gruppe nehmen") : Text("Zur Gruppe holen"))
        .accessibilityValue(Text(verbatim: name))
    }
}

// MARK: - Der Regler

/// **Ein Lautstärkeregler** in der Form der Zeitspur im Player: die Spur
/// wird beim Ziehen dicker, der Punkt wächst. Ohne Wert (noch nicht
/// gefragt) steht er blass.
struct Lautstaerkeregler: View {
    let wert: Int?
    let name: Text
    let setzen: (Int) -> Void
    var hoch: CGFloat = 28

    @State private var zug: Double?

    private static let punkt: CGFloat = 16

    var body: some View {
        let anteil = zug ?? Double(wert ?? 0) / 100
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Fortschrittsspur(anteil: anteil, hoehe: zug != nil ? 6 : 4, rund: true)
                Circle().fill(Stil.schrift).frame(width: Self.punkt, height: Self.punkt)
                    .scaleEffect(zug != nil ? 1 : 12 / Self.punkt)
                    .offset(x: (g.size.width - Self.punkt) * min(max(anteil, 0), 1))
            }
            .animation(Musikstil.umschalten, value: zug != nil)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { w in
                        guard wert != nil else { return }
                        if zug == nil { Musikstil.ruck(.leicht) }
                        let a = min(max(w.location.x / max(g.size.width, 1), 0), 1)
                        zug = a
                        setzen(Int((a * 100).rounded()))
                    }
                    .onEnded { _ in zug = nil }
            )
        }
        .frame(height: hoch)
        .opacity(wert == nil ? 0.4 : 1)
        .accessibilityElement()
        .accessibilityLabel(Text("Lautstärke \(name)"))
        .accessibilityValue(Text(wert.map { "\($0) %" } ?? "–"))
        .accessibilityAdjustableAction { richtung in
            guard let wert else { return }
            switch richtung {
            case .increment: setzen(wert + Sonosmodell.stufe)
            case .decrement: setzen(wert - Sonosmodell.stufe)
            @unknown default: break
            }
        }
    }
}

// MARK: - Das Lautstärke-Blatt

/// **Das Blatt, das die Tasten am iPhone öffnen**, solange Sonos spielt —
/// statt der Anzeige des Systems. Die Gruppe mit Minus, Regler und Plus. Nach ein paar Sekunden ohne Druck geht es
/// von selbst zu; wer darin etwas anfasst, dem bleibt es offen.
struct Lautstaerkeebene: View {
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .musikblatt(offen: Binding(get: { modell.sonos.lautstaerkeOffen },
                                       set: { modell.sonos.lautstaerkeOffen = $0 })) {
                Lautstaerkeinhalt()
            }
    }
}

private struct Lautstaerkeinhalt: View {
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        let sonos = modell.sonos
        VStack(alignment: .leading, spacing: 0) {
            Text("Lautstärke")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.136)
                .foregroundStyle(Stil.schrift)
                .padding(.horizontal, Musikstil.rand)
                .padding(.top, 5)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)

            if let z = sonos.ziel {
                HStack(spacing: 10) {
                    Image(systemName: Sonosmodell.zeichen(z.gruppe))
                        .font(.system(size: 17))
                        .frame(width: 24)
                    Text(verbatim: z.gruppe.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(Stil.akzent)
                .padding(.horizontal, Musikstil.rand)
                .padding(.bottom, 6)

                HStack(spacing: 6) {
                    Stufenknopf(zeichen: "minus", titel: Text("Leiser")) { sonos.stufe(-1) }
                    Lautstaerkeregler(wert: sonos.gruppenlautstaerke, name: Text(verbatim: z.gruppe.name), setzen: {
                        sonos.gruppenlautstaerkeSetzen($0)
                    }, hoch: 44)
                    Stufenknopf(zeichen: "plus", titel: Text("Lauter")) { sonos.stufe(1) }
                }
                .padding(.horizontal, Musikstil.rand - 6)

                // Eine Gruppe hat hier nur ihren einen Regler: verbundene
                // Lautsprecher macht man gleich laut (25.09.).
            }
        }
        .padding(.bottom, 16)
        // Wer hier etwas anfasst, dem geht das Blatt nicht mehr von selbst zu.
        .simultaneousGesture(TapGesture().onEnded { sonos.offenHalten() })
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in sonos.offenHalten() })
    }
}

/// Minus und Plus neben dem Regler: 44, rund, auf `erhoeht`.
private struct Stufenknopf: View {
    let zeichen: String
    let titel: Text
    let tun: () -> Void

    var body: some View {
        Button {
            Musikstil.ruck(.leicht)
            tun()
        } label: {
            Image(systemName: zeichen)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Stil.schrift)
                .frame(width: 44, height: 44)
                .background(Stil.erhoeht, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(Druckknopf())
        .accessibilityLabel(titel)
    }
}
