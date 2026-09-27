import Foundation
import MusikKit

/// **Die genaue Fassung gestreamter FLAC-Dateien, nebenher geladen**
/// (``Genaufassung``).
///
/// Ein eigener Zwischenspeicher unter `Caches/Genau`, getrennt von der
/// ``Ablage``: was hier liegt, hat niemand geladen, es zählt nirgends als
/// „Geladen" und darf jederzeit fallen. Höchstens die Dateien des laufenden
/// und des nächsten Liedes — was der Spieler nicht mehr braucht, löscht
/// ``behalten(_:ladenErlaubt:)`` sofort; beim Start fällt, was vom letzten
/// Mal übrig ist.
@MainActor
final class Genaulager {

    /// Eine Datei ist da — die Lied-ID.
    var fertig: ((String) -> Void)?

    private struct Lauf {
        let nummer: UUID
        let aufgabe: Task<Void, Never>
        let beginn: Date
        var anteil: Double = 0
    }

    private var laeufe: [String: Lauf] = [:]
    private var dateien: [String: URL] = [:]
    /// Lieder, deren Datei der Server verweigert hat — nicht bei jedem
    /// Abgleich der Schlange noch einmal fragen.
    private var abgelehnt = Set<String>()
    private let ordner: URL

    init() {
        let basis = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        ordner = basis.appendingPathComponent("Genau", isDirectory: true)
        // Vom letzten Mal: kein Lied, das jetzt läuft.
        try? FileManager.default.removeItem(at: ordner)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    }

    /// Die fertige Datei zu einem Lied, falls sie da ist.
    func datei(fuer lied: String) -> URL? {
        guard let url = dateien[lied] else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            dateien[lied] = nil
            return nil
        }
        return url
    }

    /// Wie lange das Laden noch dauert (``Genaufassung/restzeit(anteil:seit:)``).
    func restzeit(fuer lied: String) -> TimeInterval? {
        guard let lauf = laeufe[lied] else { return nil }
        return Genaufassung.restzeit(anteil: lauf.anteil, seit: Date().timeIntervalSince(lauf.beginn))
    }

    /// **Die Datei zu einem Lied laden**, falls sie weder da ist noch lädt.
    /// Nur über WLAN — die Anfrage verbietet teure und gesparte Netze
    /// selbst, damit ein Wechsel ins Mobilfunknetz mitten im Laden nichts
    /// kostet.
    func laden(_ lied: String, adresse: URL) {
        guard dateien[lied] == nil, laeufe[lied] == nil, !abgelehnt.contains(lied) else { return }
        var anfrage = URLRequest(url: adresse)
        anfrage.allowsCellularAccess = false
        anfrage.allowsExpensiveNetworkAccess = false
        anfrage.allowsConstrainedNetworkAccess = false
        let ziel = ordner.appendingPathComponent("\(Ablage.dateiname(lied)).flac")
        let nummer = UUID()
        let aufgabe = Task { [weak self] in _ = await self?.lade(lied, anfrage: anfrage, nach: ziel, nummer: nummer) }
        laeufe[lied] = Lauf(nummer: nummer, aufgabe: aufgabe, beginn: Date())
    }

    private func lade(_ lied: String, anfrage: URLRequest, nach ziel: URL, nummer: UUID) async {
        // Ein abgebrochener Lauf räumt nur auf, was noch seins ist — sonst
        // löschte er den Eintrag eines neuen Laufs für dasselbe Lied.
        let giltNoch = { [weak self] in !Task.isCancelled && self?.laeufe[lied]?.nummer == nummer }
        do {
            let (vorlaeufig, antwort) = try await Hintergrundlader.vorn.laden(
                anfrage, kennung: "genau|\(lied)|\(nummer.uuidString)") { [weak self] anteil in
                Task { @MainActor in
                    guard self?.laeufe[lied]?.nummer == nummer else { return }
                    self?.laeufe[lied]?.anteil = anteil
                }
            }
            let status = (antwort as? HTTPURLResponse)?.statusCode ?? 200
            guard giltNoch(), status == 200 else {
                try? FileManager.default.removeItem(at: vorlaeufig)
                guard giltNoch() else { return }
                laeufe[lied] = nil
                if (400 ..< 500).contains(status) { abgelehnt.insert(lied) }
                return
            }
            try? FileManager.default.removeItem(at: ziel)
            try FileManager.default.moveItem(at: vorlaeufig, to: ziel)
            laeufe[lied] = nil
            dateien[lied] = ziel
            fertig?(lied)
        } catch {
            // Abgebrochen oder das Netz ist weg: beim nächsten Abgleich ein
            // neuer Versuch, falls das Lied dann noch dran ist.
            if giltNoch() { laeufe[lied] = nil }
        }
    }

    /// **Nur diese Lieder behalten** — alle anderen Dateien löschen, ihr
    /// Laden abbrechen. Ohne `ladenErlaubt` bricht auch das Laden dieser ab
    /// (ins Mobilfunknetz gewechselt); was schon da ist, bleibt.
    func behalten(_ lieder: Set<String>, ladenErlaubt: Bool) {
        for (lied, lauf) in laeufe where !ladenErlaubt || !lieder.contains(lied) {
            lauf.aufgabe.cancel()
            laeufe[lied] = nil
        }
        for (lied, url) in dateien where !lieder.contains(lied) {
            try? FileManager.default.removeItem(at: url)
            dateien[lied] = nil
        }
    }
}
