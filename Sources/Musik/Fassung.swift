import Foundation

/// **Die Fassung von Swiftly Music, an einer Stelle gerechnet** — wie
/// `Sources/Shared/Fassung.swift` im Player, dessen Kommentar erklärt,
/// warum: eine zweite Rechnung in einer Ansicht läuft irgendwann auseinander.
/// Eine eigene Datei, weil die des Players „Swiftly Player" und VLCKit
/// nennt. `Protokollteilen.swift` liest von hier.
enum Fassung {

    /// Womit abgespielt wird.
    static let abspieler = "AVFoundation"

    /// „Swiftly Music 1.0.0 (Build 1)" — aus dem Bündel, nicht getippt.
    static var zeile: String {
        let b = Bundle.main.infoDictionary
        let fassung = b?["CFBundleShortVersionString"] as? String ?? "?"
        let bau = b?["CFBundleVersion"] as? String ?? "?"
        return "Swiftly Music \(fassung) (Build \(bau))"
    }

    /// Dieselbe Zeile plus den Unterbau — für das geteilte Protokoll.
    static var mitUnterbau: String { zeile + " · " + abspieler }
}
