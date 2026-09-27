import MusikKit
import SwiftUI

/// **Die Zeile der Liedliste** (Übergabe §4): 48 hoch — mit einer zweiten
/// Zeile (Gäste, die nicht der Albumkünstler sind: 13 `schriftSehrLeise`)
/// so hoch, wie sie braucht; Nummer in einer 22
/// breiten Spalte (15 `schriftSehrLeise`, tabellarisch), 14 Abstand, Titel
/// 15 Semibold, rechts die Dauer 15 `schriftLeise`. Die Haarlinie beginnt an
/// der Textkante (x 46). Das laufende Lied trägt Weiß zu 8 % in der Ecke
/// der Pille (``Zeilenflaeche``, vorher `erhoeht`, Ecke 10), und der Pegel
/// steht an der Stelle der Nummer — ohne Linien daneben. Seine zweite Zeile
/// steht dort in `schriftLeise`: auf der Fläche hielte `schriftSehrLeise`
/// die 4,5 : 1 nicht.
///
/// Die Zeile steht 10 über den Rand ihrer Spalte hinaus (`margin: 0 -10`),
/// damit die Fläche des laufenden Liedes um den Text herum Luft hat.
struct Liedzeile: View {
    let nummer: Int?
    let titel: String
    var unter: String? = nil
    let dauer: TimeInterval?
    var laeuft = false
    var spielt = false
    /// Die Haarlinie unten — aus, wenn die Zeile darunter läuft.
    var linie = true
    var gesperrt = false

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if laeuft {
                    Pegel(laeuft: spielt)
                } else {
                    Text(verbatim: nummer.map(String.init) ?? "")
                        .font(.system(size: 15))
                        .monospacedDigit()
                        .foregroundStyle(Stil.schriftSehrLeise)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: titel)
                    .font(Musikstil.zeile)
                    .foregroundStyle(gesperrt ? Stil.schriftSehrLeise : Stil.schrift)
                    .lineLimit(1)
                if let unter {
                    Text(verbatim: unter)
                        .font(.system(size: 13))
                        .foregroundStyle(laeuft ? Stil.schriftLeise : Stil.schriftSehrLeise)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let dauer {
                Text(verbatim: Zeitformat.dauer(dauer))
                    .font(Musikstil.dauer)
                    .monospacedDigit()
                    .foregroundStyle(Stil.schriftLeise)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, unter == nil ? 0 : 8)
        .frame(minHeight: 48)
        .background {
            if laeuft { Zeilenflaeche() }
        }
        .overlay(alignment: .bottom) {
            if linie && !laeuft {
                Rectangle().fill(Stil.linie).frame(height: 1)
                    .padding(.leading, 46)
                    .padding(.trailing, 10)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, -10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(laeuft ? [.isButton, .isSelected] : .isButton)
    }
}

/// **Platzhalter in der Form einer `Liedzeile`**: 48 hoch, Nummernspalte 22,
/// 14 Abstand, Titel, rechts die Dauer — und dieselbe Haarlinie ab x 46.
/// Aneinander ohne Abstand, wie die Zeilen selbst; kommen die Lieder, springt
/// nichts.
struct Liedplatzhalter: View {
    var body: some View {
        HStack(spacing: 14) {
            Ladefeld(ecke: 3).frame(width: 14, height: 12).frame(width: 22)
            Ladefeld(ecke: 4).frame(width: 170, height: 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            Ladefeld(ecke: 3).frame(width: 34, height: 12)
        }
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Stil.linie).frame(height: 1).padding(.leading, 36)
        }
        .accessibilityHidden(true)
    }
}

/// **Eine Liste von Liedern** im Stil der Liedliste — für Alben, Playlists,
/// Hörbücher und die Schlange. Die Zeile vor dem laufenden Lied verliert
/// ihre Linie, sonst stieße sie an dessen Fläche.
struct Liedliste: View {
    let lieder: [Lied]
    /// Welche Zeile läuft (Index in `lieder`).
    let laufend: Int?
    let spielt: Bool
    var nummer: (Int, Lied) -> Int? = { i, l in l.nummer ?? i + 1 }
    /// Die zweite Zeile unter dem Titel, wenn es eine gibt.
    var unter: (Lied) -> String? = { _ in nil }
    let tippen: (Int) -> Void
    /// Der Seitenrand — die Liste reicht bis an den Schirmrand, damit sich
    /// Zeilen wischen lassen; der Rand liegt in der Zeile.
    var rand: CGFloat = 0
    /// Wisch nach rechts (die Handlung erscheint links), etwa „Zur
    /// Warteschlange"; Wisch nach links, etwa „Entfernen".
    var links: ((Int, Lied) -> Wischhandlung?)?
    var rechts: ((Int, Lied) -> Wischhandlung?)?
    /// Was langer Druck auf eine Zeile anbietet.
    let handlungen: (Lied) -> Handlungsliste
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(lieder.enumerated()), id: \.offset) { i, lied in
                let l = links?(i, lied)
                let r = rechts?(i, lied)
                if l != nil || r != nil {
                    Wischzeile(links: l, rechts: r) { zeile(i, lied) }
                } else {
                    zeile(i, lied)
                }
            }
        }
    }

    private func zeile(_ i: Int, _ lied: Lied) -> some View {
        Button { if modell.frei { tippen(i) } } label: {
            Liedzeile(nummer: nummer(i, lied), titel: lied.titel, unter: unter(lied), dauer: lied.dauer,
                      laeuft: i == laufend, spielt: spielt,
                      linie: laufend.map { $0 != i + 1 } ?? true)
        }
        // Die Fläche reicht wie die der laufenden Zeile 10 über den Text hinaus.
        .buttonStyle(Zeilendruck(links: -10, rechts: -10))
        .langerDruck { handlungen(lied) }
        .padding(.horizontal, rand)
    }
}

/// **Die Zeile mit Bild** („Oft gehört", Lieder in der Bibliothek): 62 hoch,
/// Hülle 48 (Ecke 8), 14 Abstand, Titel 15 Semibold, darunter 12
/// `schriftSehrLeise`. Das laufende Lied: ``Zeilenflaeche`` und Pegel statt
/// „Mehr", die Angabe dann in `schriftLeise` wie in der ``Liedzeile``.
struct Zeilemitbild<Rechts: View>: View {
    let bild: URL?
    let titel: String
    let angabe: String?
    var laeuft = false
    var spielt = false
    var rund = false
    @ViewBuilder var rechts: () -> Rechts

    var body: some View {
        HStack(spacing: 14) {
            Netzhuelle(adresse: bild, zeichengroesse: 18)
                .frame(width: 48, height: 48)
                .clipShape(rund ? AnyShape(Circle())
                           : AnyShape(RoundedRectangle(cornerRadius: Musikstil.eckeKlein, style: .continuous)))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: titel)
                    .font(Musikstil.zeile)
                    .foregroundStyle(Stil.schrift)
                    .lineLimit(1)
                if let angabe {
                    Text(verbatim: angabe)
                        .font(Musikstil.angabe)
                        .monospacedDigit()
                        .foregroundStyle(laeuft ? Stil.schriftLeise : Stil.schriftSehrLeise)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if laeuft {
                Pegel(laeuft: spielt)
                    .frame(width: 44, height: 44)
            } else {
                rechts()
            }
        }
        .frame(height: 62)
        .padding(.horizontal, laeuft ? 10 : 0)
        .background {
            if laeuft { Zeilenflaeche() }
        }
        .padding(.horizontal, laeuft ? -10 : 0)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// „Mehr" in 44er-Ziel; öffnet Swiftlys Handlungsblatt.
struct Mehrknopf: View {
    var groesse: CGFloat = 20
    var farbe: Color = Stil.schriftSehrLeise
    let liste: @MainActor () -> Handlungsliste
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        Button { modell.handlungen = liste() } label: {
            Symbolbild(zeichen: .mehr, groesse: groesse)
                .foregroundStyle(farbe)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(Druckknopf())
        .accessibilityLabel(Text("Mehr"))
    }
}
