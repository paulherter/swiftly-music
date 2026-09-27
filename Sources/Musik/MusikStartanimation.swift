import Lottie
import SwiftUI
import UIKit

/// **Die Startanimation von Swiftly Music** — Kopie der UIKit-Fassung von
/// `Startanimation` im Player (`Sources/Shared/Startanimation.swift`), mit
/// dem Namen der Vorlage als Parameter.
///
/// **Warum eine Kopie und kein Pfad in `project.yml`:** die geteilte Datei
/// legt `Startvorhang` gleich mit an (Kollision mit dem eigenen hier) und
/// lädt fest `"startanimation"`. Sie gehört dem Player und bleibt, wie sie
/// ist. Ändert sich dort der Ablauf, gehört die Änderung hierher mit.
///
/// Die Vorlage `Mittel/startanimation-musik.json` ist die des Players, nur
/// ist das Play-Dreieck durch den **Ausschlag** ersetzt — drei Kapseln aus
/// `Notizen/SwiftlyMusic/logo/zeichen.svg`, die leicht versetzt aus ihrer
/// Mitte wachsen. Weil das Dreieck am Ende als i-Punkt über dem Strich landet,
/// steht danach von selbst die Wortmarke von Swiftly Music da.
///
/// Der Ausschlag hat Lücken, das volle Dreieck hatte keine — im Player
/// verdeckt es die Buchstaben, bis sie darunter hervorkommen. Hier blenden
/// die Buchstaben stattdessen selbst weich auf (Frame 33 bis 49, kurz nach
/// dem Player), während sie wie gehabt nach außen laufen. Eine Deckfläche in
/// der Grundfarbe war als graues Feld hinter den Kapseln zu sehen.
struct MusikStartanimation: UIViewRepresentable {
    var name = "startanimation-musik"
    var nachlauf: TimeInterval = 0.5
    /// Spätestens dann geht es weiter, egal was die Animation macht.
    var spaetestens: TimeInterval = 3.5
    /// Bewegung reduzieren: gleich das Standbild vom Ende, ohne Weg.
    var standbild = false
    let fertig: () -> Void

    /// Hülle ohne eigenes Wunschmaß — sonst setzt `LottieAnimationView` ihr
    /// 1024 × 1024 gegen den Rahmen von SwiftUI durch.
    final class Huelle: UIView {
        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
    }

    /// `fertig` genau einmal — vom Abschluss oder von der Frist.
    final class Einmal {
        private var schonGerufen = false
        func ruf(_ tun: () -> Void) {
            guard !schonGerufen else { return }
            schonGerufen = true
            tun()
        }
    }

    func makeCoordinator() -> Einmal { Einmal() }

    func makeUIView(context: Context) -> Huelle {
        let huelle = Huelle()
        huelle.setContentHuggingPriority(.defaultLow, for: .horizontal)
        huelle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        huelle.setContentHuggingPriority(.defaultLow, for: .vertical)
        huelle.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let ansicht = LottieAnimationView(name: name)
        ansicht.contentMode = .scaleAspectFit
        ansicht.loopMode = .playOnce
        ansicht.backgroundBehavior = .pauseAndRestore
        ansicht.translatesAutoresizingMaskIntoConstraints = false
        huelle.addSubview(ansicht)
        NSLayoutConstraint.activate([
            ansicht.topAnchor.constraint(equalTo: huelle.topAnchor),
            ansicht.bottomAnchor.constraint(equalTo: huelle.bottomAnchor),
            ansicht.leadingAnchor.constraint(equalTo: huelle.leadingAnchor),
            ansicht.trailingAnchor.constraint(equalTo: huelle.trailingAnchor),
        ])
        let einmal = context.coordinator
        let weiter = { DispatchQueue.main.asyncAfter(deadline: .now() + nachlauf) {
            einmal.ruf(fertig)
        } }

        // Ohne Vorlage gar nicht erst spielen: `play(completion:)` riefe
        // seinen Abschluss nie, der Vorhang läge für immer über der App.
        guard ansicht.animation != nil else {
            einmal.ruf(fertig)
            return huelle
        }

        if standbild {
            ansicht.currentProgress = 1
            weiter()
        } else {
            ansicht.play { _ in weiter() }
        }

        // Zweiter Weg zum selben Ziel, falls Lottie im Hintergrund pausiert
        // und seinen Abschluss nicht mehr ruft.
        DispatchQueue.main.asyncAfter(deadline: .now() + spaetestens) {
            einmal.ruf(fertig)
        }
        return huelle
    }

    func updateUIView(_ ansicht: Huelle, context: Context) {}
}
