import SwiftUI

/// **Der Vorhang beim Start** — derselbe wie `Startvorhang` im Player
/// (`Sources/Shared/Startanimation.swift`): fester Grund, darauf die
/// Lottie-Animation, ist sie durch, blendet die App darunter auf.
///
/// Die Vorlage ist die des Players mit dem Ausschlag statt des
/// Play-Dreiecks (`MusikStartanimation`). Ablauf und Fristen sind dieselben:
/// Animation, 0,5 Sekunden Standbild, spätestens nach 3,5 Sekunden weiter.
///
/// **Bewegung reduzieren:** gleich das Standbild vom Ende, dann weiter.
struct Startvorhang: View {
    let fertig: () -> Void

    var body: some View {
        // Der Stapel selbst ignoriert den sicheren Bereich, sonst liegt seine
        // Mitte 12 Punkt zu tief (oben 59 frei, unten 34).
        ZStack {
            Stil.grund
            MusikStartanimation(standbild: Musikstil.bewegungReduziert, fertig: fertig)
                // Das Quadrat der Vorlage, die Marke füllt nur den mittleren
                // Streifen — dasselbe Maß wie im Player auf dem iPhone.
                .frame(width: 440, height: 440)
                // Wer die Marke nicht sieht, erfährt so, wer da startet.
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: "Swiftly Music"))
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }
}
