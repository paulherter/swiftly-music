import Foundation
import MusikKit
import Network

/// **Über welches Netz das Gerät gerade geht** — für die Höchstrate beim
/// Streamen, „Nur über WLAN laden", den Offline-Betrieb und das Nachtragen
/// von Meldungen, sobald das Netz wieder da ist.
@MainActor
@Observable
final class Netzwaechter {
    private(set) var verbindung: Verbindung = .wlan
    /// **Datensparmodus** (`NWPath.isConstrained`) — auch im WLAN. Dann lädt
    /// die genaue Fassung einer FLAC-Datei nicht nebenher (``Genaufassung``).
    private(set) var sparsam = false
    /// Gerufen bei jedem Wechsel, nach dem Setzen.
    @ObservationIgnored var beiWechsel: ((Verbindung, Verbindung) -> Void)?
    /// Gerufen, wenn der Datensparmodus an- oder ausgeht.
    @ObservationIgnored var beiSparmodus: ((Bool) -> Void)?
    @ObservationIgnored private let waechter = NWPathMonitor()

    init() {
        waechter.pathUpdateHandler = Self.melder(self)
        waechter.start(queue: DispatchQueue(label: "de.paulherter.swiftly.music.netz"))
    }

    /// Außerhalb des Hauptakteurs gebaut: Network ruft auf seinem eigenen
    /// Faden.
    nonisolated private static func melder(_ waechter: Netzwaechter) -> @Sendable (NWPath) -> Void {
        { [weak waechter] pfad in
            let neu: Verbindung = pfad.status != .satisfied ? .keine
                : (pfad.isExpensive || pfad.usesInterfaceType(.cellular)) ? .mobil : .wlan
            let sparsam = pfad.isConstrained
            Task { @MainActor in
                waechter?.setzen(neu)
                waechter?.sparmodus(sparsam)
            }
        }
    }

    private func sparmodus(_ an: Bool) {
        guard an != sparsam else { return }
        sparsam = an
        beiSparmodus?(an)
    }

    private func setzen(_ neu: Verbindung) {
        guard neu != verbindung else { return }
        let alt = verbindung
        verbindung = neu
        beiWechsel?(alt, neu)
    }
}
