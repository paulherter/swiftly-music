import MusikKit
import SwiftUI

// **Die Kacheln aus dem Entwurf**: die 112er in einer Reihe, dieselbe im
// Raster mit drei Spalten, die kleine für „Zuletzt gehört" in vier Spalten
// und das Mosaik des Sofortmix. Eine Bauart je Rolle (`VERHALTEN.md` E12).

/// **Die Kachel**: Hülle mit Ecke 10, Titel 13 Medium (7 darunter),
/// Angabe 12 `schriftSehrLeise`. Ihre Kante ist ein Drittel der Breite —
/// in der Reihe wie im Raster dieselbe (``Musikstil/kachelkante(breite:)``).
struct Kachel: View {
    let bild: URL?
    let titel: String
    let angabe: String?
    var rund = false
    var neu = false
    var laeuft: Bool?
    @Environment(\.kachelkante) private var breite

    var body: some View {
        VStack(alignment: rund ? .center : .leading, spacing: 0) {
            huelle
            Text(verbatim: titel)
                .font(Musikstil.kacheltitel)
                .foregroundStyle(Stil.schrift)
                .lineLimit(1)
                .padding(.top, 7)
            if let angabe {
                Text(verbatim: angabe)
                    .font(Musikstil.angabe)
                    .foregroundStyle(Stil.schriftSehrLeise)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
        }
        .frame(width: breite, alignment: rund ? .center : .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Ein Quadrat, das die Breite vorgibt, und das Bild darin — so bleibt
    /// die Kachel quadratisch, egal welches Seitenverhältnis die Hülle hat.
    private var huelle: some View {
        Color.clear
            .frame(width: breite, height: breite)
            .overlay { Netzhuelle(adresse: bild, zeichengroesse: 26) }
            .clipShape(rund ? AnyShape(Circle())
                       : AnyShape(RoundedRectangle(cornerRadius: Musikstil.eckeKachel, style: .continuous)))
            .overlay(alignment: .topTrailing) { if neu { NeuMarke() } }
            .overlay(alignment: .bottomTrailing) { if let laeuft { Laufmarke(laeuft: laeuft) } }
    }
}

/// **„Zuletzt gehört"**: vier Spalten, 1 : 1, Künstler rund, Titel 12
/// Medium und Art 11 mittig darunter. Was läuft, trägt die Laufmarke.
struct Zuletztkachel: View {
    let verweis: Sammlungsverweis
    let bild: URL?
    var laeuft: Bool?
    /// Statt der Art: „Single", „3 Singles".
    var bezeichnung: String?

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    // Die Lieblingssongs haben keine Hülle, sondern ihre Kachel.
                    if verweis.art == .playlist, verweis.kennung == Musikmodell.lieblingskennung {
                        Lieblingskachel()
                    } else {
                        Netzhuelle(adresse: bild, zeichengroesse: 20)
                    }
                }
                .clipShape(verweis.art == .kuenstler ? AnyShape(Circle())
                           : AnyShape(RoundedRectangle(cornerRadius: Musikstil.eckeKachel, style: .continuous)))
                .overlay(alignment: .bottomTrailing) { if let laeuft { Laufmarke(laeuft: laeuft) } }
            Text(verbatim: verweis.titel)
                .font(Musikstil.kleinkachelTitel)
                .foregroundStyle(Stil.schrift)
                .lineLimit(1)
                .padding(.top, 7)
            (bezeichnung.map { Text(verbatim: $0) } ?? art)
                .font(Musikstil.kleinkachelArt)
                .foregroundStyle(Stil.schriftSehrLeise)
                .lineLimit(1)
                .padding(.top, 1)
        }
        .multilineTextAlignment(.center)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var art: Text {
        switch verweis.art {
        case .album: Text("Album")
        // Eigener Schlüssel: auf Englisch heißt es hier „Artist", als
        // Überschrift „Artists" — auf Deutsch beides „Künstler".
        case .kuenstler: Text("Künstler (einer)")
        case .playlist: Text("Playlist")
        case .hoerbuch: Text("Hörbuch")
        }
    }
}

/// **Der Sofortmix als Kachel**: ein 2 × 2-Mosaik aus Hüllen, unten ein
/// Verlauf von Schwarz 60 % nach klar, darauf das Etikett 12 Semibold.
struct Mixkachel: View {
    let huellen: [URL?]
    let etikett: String
    let titel: String
    let angabe: String
    @Environment(\.kachelkante) private var kante

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        feld(0)
                        feld(1)
                    }
                    GridRow {
                        feld(2)
                        feld(3)
                    }
                }
                LinearGradient(stops: [.init(color: .black.opacity(0.6), location: 0),
                                       .init(color: .black.opacity(0), location: 0.6)],
                               startPoint: .bottom, endPoint: .top)
                Text(verbatim: etikett)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Stil.schrift)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 7)
            }
            .frame(width: kante, height: kante)
            .clipShape(RoundedRectangle(cornerRadius: Musikstil.eckeKachel, style: .continuous))

            Text(verbatim: titel)
                .font(Musikstil.kacheltitel)
                .foregroundStyle(Stil.schrift)
                .lineLimit(1)
                .padding(.top, 7)
            Text(verbatim: angabe)
                .font(Musikstil.angabe)
                .foregroundStyle(Stil.schriftSehrLeise)
                .lineLimit(1)
                .padding(.top, 1)
        }
        .frame(width: kante, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func feld(_ i: Int) -> some View {
        Netzhuelle(adresse: i < huellen.count ? huellen[i] : nil, zeichengroesse: 12)
            .frame(width: kante / 2, height: kante / 2)
            .clipped()
    }
}

/// Platzhalter für eine Reihe Kacheln (E17) — Überschrift und Kacheln
/// stehen dort, wo sie nachher stehen.
///
/// **Die Kacheln liegen als Auflage, nicht im Fluss** (24.09.: beim
/// Kaltstart „animiert sich einmal alles ein"). Vier Kacheln sind breiter
/// als der Schirm (440 → 578 im Probelauf); im Fluss machten sie die ganze
/// Startseite so breit, jede Reihe stand um 69 nach links versetzt, und
/// sobald der letzte Platzhalter ging, schrumpfte alles auf Schirmbreite.
/// Als Auflage zählt nur ihre Höhe, und sie laufen rechts aus dem Bild wie
/// die echte Reihe.
struct Reihenplatzhalter: View {
    @Environment(\.kachelkante) private var kante

    var body: some View {
        VStack(alignment: .leading, spacing: Musikstil.reihentitelAbstand) {
            Ladefeld(ecke: 4).frame(width: 148, height: 20)
                .frame(height: Musikstil.reihentitelHoehe)
            Color.clear
                .frame(height: kante + 7 + 11)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: Musikstil.kachelAbstand) {
                        ForEach(0 ..< 4, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 7) {
                                Ladefeld().frame(width: kante, height: kante)
                                Ladefeld(ecke: 3).frame(width: 80, height: 11)
                            }
                        }
                    }
                    .fixedSize()
                }
        }
        .padding(.horizontal, Musikstil.rand)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Lädt"))
    }
}

/// Platzhalter für ein Raster mit drei Spalten.
struct Rasterplatzhalter: View {
    var rund = false
    @Environment(\.kachelkante) private var kante

    var body: some View {
        LazyVGrid(columns: Kachelraster.spalten(kante), alignment: .leading, spacing: Musikstil.rasterZeile) {
            ForEach(0 ..< 9, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 7) {
                    Ladefeld(ecke: rund ? 999 : Musikstil.eckeKachel).frame(width: kante, height: kante)
                    Ladefeld(ecke: 3).frame(width: kante * 0.7, height: 11)
                }
            }
        }
        .padding(.horizontal, Musikstil.rand)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Lädt"))
    }
}

/// **Das Raster mit drei Spalten**: feste Spalten in der Kachelkante, damit
/// eine Hülle hier genau dort steht, wo sie in einer Reihe stünde.
enum Kachelraster {
    static func spalten(_ kante: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.fixed(kante), spacing: Musikstil.kachelAbstand, alignment: .top), count: 3)
    }
}
