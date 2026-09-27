import SwiftUI

/// **Die Zeichen aus dem Entwurf**, als SVG-Pfade im 24er-Feld.
///
/// Wörtlich aus `Notizen/SwiftlyMusic/entwurf.html` übernommen (Rechtecke und
/// Kreise dort als Pfad ausgeschrieben), damit Strichstärke und Form stimmen —
/// eine SF-Symbol-Näherung sähe neben dem Entwurf anders aus. Gezeichnet wird
/// über `SVGPfad` aus `Sources/Shared`.
enum Zeichen: Hashable {
    case start, bibliothek, suche, hoerbuecher
    case abspielen, pause, weiter, zurueck
    case zufall, herz, herzUmriss, laden, geladen, mehr
    case sofortmix, liedtext, ausgabe, alsNaechstes, wiederholen, wiederholenEines
    case winkelRunter, winkelRechts, sortieren, haken, kreuz

    /// Ein Teil ist gestrichen oder gefüllt.
    enum Art: Hashable {
        case strich(CGFloat)
        case flaeche
    }

    struct Teil: Hashable {
        let pfad: String
        let art: Art
    }

    var teile: [Teil] {
        switch self {
        case .start:
            [Teil(pfad: "M4 11.5L12 4l8 7.5M6.5 10.5V20h11v-9.5", art: .strich(1.9))]
        case .bibliothek:
            [Teil(pfad: "M4.5 4h2a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-2a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z"
                  + "M11 4h2a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-2a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z"
                  + "M14.9 5.2l3.8-1 3.1 15.4-3.8 1z", art: .strich(1.9))]
        case .suche:
            [Teil(pfad: "M18 11a7 7 0 1 1-14 0a7 7 0 1 1 14 0zM20 20l-4.2-4.2", art: .strich(1.9))]
        case .hoerbuecher:
            // Nicht im Entwurf — ein offenes Buch in derselben Strichstärke.
            [Teil(pfad: "M12 6.5C10 5 7.5 4.5 4 4.5v13c3.5 0 6 .5 8 2 2-1.5 4.5-2 8-2v-13c-3.5 0-6 .5-8 2zM12 6.5v13",
                  art: .strich(1.9))]
        case .abspielen:
            [Teil(pfad: "M7 4.9v14.2c0 .9 1 1.4 1.7.9l11-7.1a1.1 1.1 0 0 0 0-1.8l-11-7.1C8 3.5 7 4 7 4.9z",
                  art: .flaeche)]
        case .pause:
            [Teil(pfad: "M7.2 4h1.8a1.2 1.2 0 0 1 1.2 1.2v13.6a1.2 1.2 0 0 1-1.2 1.2h-1.8a1.2 1.2 0 0 1-1.2-1.2V5.2a1.2 1.2 0 0 1 1.2-1.2z"
                  + "M15 4h1.8a1.2 1.2 0 0 1 1.2 1.2v13.6a1.2 1.2 0 0 1-1.2 1.2h-1.8a1.2 1.2 0 0 1-1.2-1.2V5.2a1.2 1.2 0 0 1 1.2-1.2z",
                  art: .flaeche)]
        case .weiter:
            [Teil(pfad: "M2.5 6.2v11.6c0 .8.9 1.3 1.6.8l8.4-5.8a1 1 0 0 0 0-1.6L4.1 5.4c-.7-.5-1.6 0-1.6.8z"
                  + "M12 6.2v11.6c0 .8.9 1.3 1.6.8l8.4-5.8a1 1 0 0 0 0-1.6l-8.4-5.8c-.7-.5-1.6 0-1.6.8z",
                  art: .flaeche)]
        case .zurueck:
            [Teil(pfad: "M21.5 6.2v11.6c0 .8-.9 1.3-1.6.8l-8.4-5.8a1 1 0 0 1 0-1.6l8.4-5.8c.7-.5 1.6 0 1.6.8z"
                  + "M12 6.2v11.6c0 .8-.9 1.3-1.6.8L2 12.8a1 1 0 0 1 0-1.6l8.4-5.8c.7-.5 1.6 0 1.6.8z",
                  art: .flaeche)]
        case .zufall:
            [Teil(pfad: "M3 7h3.5c4.5 0 6.5 10 11 10H21M3 17h3.5c1.8 0 3.1-1.6 4.2-3.4M13.3 10.4C14.4 8.6 15.7 7 17.5 7H21M18 4l3 3-3 3M18 14l3 3-3 3",
                  art: .strich(1.9))]
        // **Gefüllt so groß wie der Umriss** (25.09.: nach dem
        // Antippen wurde das Herz kleiner): der Strich des Umrisses liegt zur
        // Hälfte außerhalb des Pfads — nur gefüllt war es 2 Punkt kleiner.
        case .herz:
            [Teil(pfad: Self.herzpfad, art: .flaeche), Teil(pfad: Self.herzpfad, art: .strich(1.9))]
        case .herzUmriss:
            [Teil(pfad: Self.herzpfad, art: .strich(1.9))]
        case .laden:
            [Teil(pfad: "M20.5 12a8.5 8.5 0 1 1-17 0a8.5 8.5 0 1 1 17 0zM12 7.5v8M8.5 12.5 12 16l3.5-3.5",
                  art: .strich(1.9))]
        case .geladen:
            // Der Kreis vom Laden, mit Haken statt Pfeil.
            [Teil(pfad: "M20.5 12a8.5 8.5 0 1 1-17 0a8.5 8.5 0 1 1 17 0zM8.3 12.3l2.5 2.5 4.9-5",
                  art: .strich(1.9))]
        case .mehr:
            [Teil(pfad: "M7 12a1.5 1.5 0 1 1-3 0a1.5 1.5 0 1 1 3 0zM13.5 12a1.5 1.5 0 1 1-3 0a1.5 1.5 0 1 1 3 0z"
                  + "M20 12a1.5 1.5 0 1 1-3 0a1.5 1.5 0 1 1 3 0z", art: .flaeche)]
        case .sofortmix:
            [Teil(pfad: "M4 12c2-5 4-5 6 0s4 5 6 0 3-4 4-2M17 5.5l2.5-1.5M19.5 4v3", art: .strich(1.9))]
        case .liedtext:
            [Teil(pfad: "M4.5 5.5h15a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H10l-4.5 3.5v-3.5h-1a1 1 0 0 1-1-1v-10a1 1 0 0 1 1-1zM8 10h8M8 13h5",
                  art: .strich(1.9))]
        case .ausgabe:
            [Teil(pfad: "M7 16.5a7 7 0 1 1 10 0M9.5 14a3.5 3.5 0 1 1 5 0", art: .strich(1.9)),
             Teil(pfad: "M12 14.5 16.5 21h-9z", art: .flaeche)]
        case .alsNaechstes:
            [Teil(pfad: "M4 6h16M4 12h10M4 18h10", art: .strich(1.9)),
             Teil(pfad: "M16.5 14.5v7l4.5-3.5z", art: .flaeche)]
        case .wiederholen:
            // Nicht im Entwurf — zwei Pfeile im Kreislauf, Strich wie Zufall.
            [Teil(pfad: Self.kreislauf, art: .strich(1.9))]
        case .wiederholenEines:
            // Dasselbe mit einer Eins in der Mitte, wie überall üblich.
            [Teil(pfad: Self.kreislauf, art: .strich(1.9)),
             Teil(pfad: "M10.9 10.4 12.4 9.4V14.6", art: .strich(1.7))]
        case .winkelRunter:
            [Teil(pfad: "M5 9l7 7 7-7", art: .strich(2.2))]
        case .winkelRechts:
            [Teil(pfad: "M9 5l7 7-7 7", art: .strich(2.2))]
        case .sortieren:
            [Teil(pfad: "M4 7h16M7 12h10M10 17h4", art: .strich(2))]
        case .haken:
            [Teil(pfad: "M4 12.5l5.5 5.5L20 6.5", art: .strich(3))]
        case .kreuz:
            [Teil(pfad: "M6 6l12 12M18 6L6 18", art: .strich(3.4))]
        }
    }

    private static let kreislauf =
        "M17 2.5l3 3-3 3M20 5.5H8.5a4.5 4.5 0 0 0-4.5 4.5v.5M7 21.5l-3-3 3-3M4 18.5h11.5a4.5 4.5 0 0 0 4.5-4.5v-.5"

    private static let herzpfad =
        "M12 20s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7.2a4.3 4.3 0 0 1 7.5 2.6C19.5 15.4 12 20 12 20z"
}

/// Ein Zeichen in `groesse` × `groesse` Punkt, in der Vordergrundfarbe.
struct Symbolbild: View {
    let zeichen: Zeichen
    var groesse: CGFloat = 22

    private static let feld = CGRect(x: 0, y: 0, width: 24, height: 24)

    var body: some View {
        ZStack {
            ForEach(Array(zeichen.teile.enumerated()), id: \.offset) { _, teil in
                switch teil.art {
                case let .strich(breite):
                    SVGForm(daten: teil.pfad, box: Self.feld)
                        .stroke(style: StrokeStyle(lineWidth: breite * groesse / 24,
                                                   lineCap: .round, lineJoin: .round))
                case .flaeche:
                    SVGForm(daten: teil.pfad, box: Self.feld).fill()
                }
            }
        }
        .frame(width: groesse, height: groesse)
        .accessibilityHidden(true)
    }
}
