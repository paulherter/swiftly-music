import SwiftUI
import UIKit

/// **Die Leiste unten — normal, nicht schwebend** (Übergabe §4).
///
/// **Zeichen und Maße wie im Player, eins zu eins** (24.09.: „sehen
/// deutlich schlechter aus als in Swiftly Player") — `Navileiste` und
/// `Bereichsknopf` in `Sources/Shared/Stil.swift`: SF Symbols 20 Punkt,
/// gewählt Semibold, sonst Regular; Beschriftung 10, gewählt Semibold, sonst
/// Medium; 4 Abstand; 9 Innenabstand oben, Leiste 54 hoch
/// (`Stil.leisteHoehe`); gewählt `akzent`, sonst `schriftSehrLeise`.
/// Start und Suche tragen dieselben Zeichen wie dort (`house`,
/// `magnifyingglass`); Bibliothek und Hörbücher gibt es im Player nicht —
/// sie nehmen Zeichen derselben Familie in derselben Strichstärke.
///
/// Der Grund bleibt das Glas aus dem Entwurf statt der deckenden Fläche:
/// bei 92 % Grundton darüber bleibt von der hellen Schicht der Materialien
/// nichts sichtbar (vgl. `Fallen/swiftui.md`, „Leistenglas über einer
/// dunklen Seite").
///
/// **Kein Tipp fällt durch.** Jeder Knopf reicht über die ganze Höhe, und
/// die Fläche bis unter den Home-Indikator schluckt, was dazwischen landet
/// (24.09.: „man kann durch die Leiste hindurch Inhalte antippen" —
/// das Glas nimmt keine Tipps an, und die Knöpfe waren nur 41 hoch).
struct Leiste: View {
    let bereiche: [Bereich]
    @Binding var gewaehlt: Bereich
    /// Ein zweiter Tipp auf den offenen Bereich: zur Wurzel, dort nach oben
    /// (``Hauptansicht``).
    var nochmal: (Bereich) -> Void = { _ in }

    /// `Stil.leisteHoehe` — ohne den Home-Indikator.
    static let hoehe: CGFloat = 54

    var body: some View {
        HStack(spacing: 0) {
            ForEach(bereiche) { bereich in
                let aktiv = bereich == gewaehlt
                Button {
                    if aktiv {
                        nochmal(bereich)
                    } else {
                        gewaehlt = bereich
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: bereich.leistenzeichen)
                            .font(.system(size: 20, weight: aktiv ? .semibold : .regular))
                        Text(bereich.name)
                            .font(.system(size: 10, weight: aktiv ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(aktiv ? Stil.akzent : Stil.schriftSehrLeise)
                    .padding(.top, 9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(Druckknopf())
                .accessibilityLabel(Text(bereich.name))
                .accessibilityAddTraits(aktiv ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(height: Self.hoehe)
        .background {
            ZStack {
                Leistenglas()
                // Das Glas nimmt keine Tipps an — diese Fläche schon.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Stil.linie).frame(height: 1)
        }
    }
}

extension Bereich {
    /// Das SF-Symbol in der Leiste (`Bereich.symbol` im Player).
    var leistenzeichen: String {
        switch self {
        case .start: "house"
        case .bibliothek: "square.stack"
        case .suche: "magnifyingglass"
        case .hoerbuecher: "book"
        }
    }
}

/// **Glas:** gleichmäßig unscharf, darüber der Grundton zu 92 %
/// (`Leistenglas` in `Stil.swift` :2504, mit der Tiefe aus dem Entwurf).
struct Leistenglas: View {
    var tiefe: Double = 0.92

    var body: some View {
        ZStack {
            Unschaerfe()
            Stil.grund.opacity(tiefe)
        }
        .allowsHitTesting(false)
    }
}

/// Das dünnste Material ohne Maske — eine Maske, die je Bild neu gerechnet
/// wird, ließe die Fläche beim Federn aufblitzen (`Unschaerfe` in
/// `Stil.swift` :2415).
struct Unschaerfe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let ansicht = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        ansicht.isUserInteractionEnabled = false
        return ansicht
    }

    func updateUIView(_ ansicht: UIVisualEffectView, context: Context) {}
}

/// **Wischen zurück, obwohl die Navigationsleiste verborgen ist**
/// (`WischZurueck` in `Sources/iOS/Orientierung.swift`).
struct WischZurueck: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Halter() }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}

    private final class Halter: UIViewController, UIGestureRecognizerDelegate {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            uebernehmen()
        }

        override func viewDidAppear(_ animiert: Bool) {
            super.viewDidAppear(animiert)
            uebernehmen()
        }

        private func uebernehmen() {
            guard let geste = navigationController?.interactivePopGestureRecognizer else { return }
            geste.delegate = self
            geste.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
