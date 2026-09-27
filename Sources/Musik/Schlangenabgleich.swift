import Foundation
import MusikKit
import UIKit

/// **Weiterhören mit Navidrome** — über die Schlange des Servers.
///
/// **Keine Live-Steuerung, und das mit Absicht nicht nachgebaut.** Subsonic
/// hat keinen Kanal vom Server zu den Apps (``Serverschlange``): kein Gerät
/// kann ein anderes anhalten, weiterschalten oder sehen, was dort läuft. Was
/// geht, ist die abgelegte Schlange je Konto. Die legt Swiftly Music ab,
/// wenn sich etwas ändert (Pause, Liedwechsel — über `Spieler.geaendert`),
/// beim Gang in den Hintergrund und alle 30 Sekunden, solange Musik läuft.
/// Beim Öffnen sieht es nach, ob ein anderes Gerät danach eine neuere
/// abgelegt hat (``Schlangenvergleich``), und bietet sie an.
///
/// **Erst ablegen, wenn hier gespielt wurde.** Sonst schriebe schon der
/// Gang in den Hintergrund die alte Schlange dieses Geräts über die neuere
/// eines anderen — nur weil die App kurz offen war.
@MainActor
final class Schlangenabgleich {

    private var quelle: (any Serverschlange)?
    private weak var modell: Musikmodell?
    private var konto: Kontokennung?
    private var takt: Task<Void, Never>?
    private var vorgemerkt: Task<Void, Never>?
    private var hatGespielt = false
    /// Was zuletzt abgelegt wurde — dieselbe Schlange an derselben Stelle
    /// geht nicht zweimal hinaus.
    private var zuletzt: (ids: [String], aktuell: String?, stelle: Int)?

    private var spieler: Spieler? { modell?.spieler }

    func starten(_ quelle: any Serverschlange, konto: Kontokennung, modell: Musikmodell) {
        beenden()
        self.quelle = quelle
        self.konto = konto
        self.modell = modell
        takt = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                if self.spieler?.spielt == true { await self.sichern() }
            }
        }
        Task { [weak self] in await self?.nachsehen() }
    }

    func beenden() {
        takt?.cancel(); takt = nil
        vorgemerkt?.cancel(); vorgemerkt = nil
        quelle = nil
        konto = nil
        hatGespielt = false
        zuletzt = nil
    }

    /// Nach jeder Änderung am Spieler, zwei Sekunden gesammelt.
    func vormerken() {
        guard quelle != nil else { return }
        if spieler?.spielt == true { hatGespielt = true }
        vorgemerkt?.cancel()
        vorgemerkt = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.sichern()
        }
    }

    /// Beim Gang in den Hintergrund — mit etwas Zeit vom System, damit die
    /// Anfrage noch hinausgeht, bevor iOS die App anhält.
    func hintergrund() {
        guard quelle != nil, hatGespielt else { return }
        let aufschub = UIApplication.shared.beginBackgroundTask(withName: "Schlange ablegen")
        Task { [weak self] in
            await self?.sichern()
            UIApplication.shared.endBackgroundTask(aufschub)
        }
    }

    private func sichern() async {
        guard let quelle, let konto, hatGespielt, let spieler,
              let aktuell = spieler.aktuell else { return }
        let ids = spieler.schlange.eintraege.map(\.lied.id)
        let stelle = spieler.stelle()
        let stand = (ids, Optional(aktuell.id), Int(stelle))
        if let z = zuletzt, z.ids == stand.0, z.aktuell == stand.1, z.stelle == stand.2 { return }
        do {
            try await quelle.schlangeSichern(ids: ids, aktuell: aktuell.id, stelle: stelle)
            zuletzt = stand
            UserDefaults.standard.set(Date(), forKey: Self.schluessel(konto))
        } catch {
            // Still: beim nächsten Anlass geht sie wieder hinaus.
        }
    }

    private static func schluessel(_ konto: Kontokennung) -> String {
        "musik.schlangeGesichert.\(konto.ablagename)"
    }

    /// **Beim Öffnen: hat ein anderes Gerät danach eine Schlange abgelegt?**
    func nachsehen() async {
        guard let quelle, let konto, let spieler, let modell, !spieler.spielt,
              let server = try? await quelle.schlangeHolen(), self.quelle === quelle else { return }
        let eigene = UserDefaults.standard.object(forKey: Self.schluessel(konto)) as? Date
        let hier = spieler.aktuell.map { (liedID: $0.id, stelle: spieler.position) }
        guard Schlangenvergleich.lohntAngebot(server, eigeneSicherung: eigene, hier: hier,
                                              hierSpielt: spieler.spielt),
              let lied = server.lied else { return }
        let von = server.von.flatMap { $0.isEmpty ? nil : $0 }
        modell.angebot = Weiterhoerangebot(
            schluessel: "subsonic|\(server.geaendert?.timeIntervalSince1970 ?? 0)",
            titel: von.map { String(localized: "Zuletzt auf \($0) gehört") }
                ?? String(localized: "Zuletzt auf einem anderen Gerät gehört"),
            lied: lied, zeichen: "clock.arrow.circlepath", art: .subsonic(server))
    }

    /// „Hier weiterhören": die Schlange des Servers, ab dem Lied und der Stelle.
    func annehmen(_ server: Gespeicherteschlange) {
        guard let modell else { return }
        hatGespielt = true
        modell.spielen(server.lieder, ab: server.aktuell, herkunft: nil, stelle: server.stelle)
    }
}
