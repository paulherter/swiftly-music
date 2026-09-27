import Foundation
import JellyfinKit

/// **Jellyfins Steuerkanal (`/socket`) für Swiftly Music.**
///
/// Über ihn kommen die Befehle anderer Geräte an — Jellyfin-Web, eine
/// zweite Swiftly Music, das Dashboard. Es gibt keinen Abruf dafür; der
/// Server schickt von sich aus. Gebaut nach ``Fernsteuerung`` aus JellyfinKit
/// (dort stehen die Fallen: Ausweis, Dauersitzung, Lebenszeichen), aber mit
/// allen drei Befehlsarten statt nur `Playstate` (``Kanalnachricht``).
///
/// **Ein Aktor, und jede Aufgabe hält ihn nur schwach.** Lauscher,
/// Lebenszeichen und Wiederaufbau laufen als eigene Aufgaben; mit einer
/// starken Bindung hielten sie den Kanal am Leben, auch wenn niemand ihn
/// mehr hat. ``beenden()`` bricht alle drei ab und sperrt den Wiederaufbau —
/// das Abmelden ruft es, und danach klopft nichts mehr beim Server an.
public actor Steuerkanal {

    public typealias Empfang = @Sendable (Kanalnachricht) -> Void

    private let anfrage: URLRequest
    private let sitzung: URLSession
    private var aufgabe: URLSessionWebSocketTask?
    private var lauscher: Task<Void, Never>?
    private var herzschlag: Task<Void, Never>?
    private var wiederaufbau: Task<Void, Never>?
    private var empfang: Empfang?
    private var abrisse = 0

    /// Die Dauersitzung aus JellyfinKit: **nicht `URLSession.shared`** — mit
    /// dessen Zeitgrenze riss der Kanal auf Linux nach genau 120 Sekunden ab
    /// (``Fernsteuerung/dauersitzung``).
    public init(anfrage: URLRequest, sitzung: URLSession = Fernsteuerung.dauersitzung) {
        self.anfrage = anfrage
        self.sitzung = sitzung
    }

    /// Ob gerade eine Leitung steht oder aufgebaut wird.
    public var verbunden: Bool { aufgabe != nil }

    /// Verbindet und ruft `empfang` für jede lesbare Nachricht. Ein zweiter
    /// Aufruf bei stehender Leitung ändert nur den Empfänger.
    public func starten(_ empfang: @escaping Empfang) {
        self.empfang = empfang
        guard aufgabe == nil else { return }
        wiederaufbau?.cancel(); wiederaufbau = nil
        Spur.sag("[Steuerkanal] verbinde …")
        let neu = sitzung.webSocketTask(with: anfrage)
        neu.resume()
        aufgabe = neu
        lauschen(neu)
        schlagen()
    }

    public func beenden() {
        empfang = nil             // sperrt den Wiederaufbau
        abrisse = 0
        wiederaufbau?.cancel(); wiederaufbau = nil
        lauscher?.cancel(); lauscher = nil
        herzschlag?.cancel(); herzschlag = nil
        aufgabe?.cancel(with: .goingAway, reason: nil)
        aufgabe = nil
    }

    private func lauschen(_ leitung: URLSessionWebSocketTask) {
        lauscher = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let nachricht = try await leitung.receive()
                    guard let self else { return }
                    if case let .string(text) = nachricht {
                        await self.verarbeiten(text)
                    }
                    await self.angekommen()
                } catch {
                    guard !Task.isCancelled, let self else { return }
                    await self.verloren(leitung, fehler: error)
                    return
                }
            }
        }
    }

    private func angekommen() {
        if abrisse > 0 { Spur.sag("[Steuerkanal] Leitung steht wieder") }
        abrisse = 0
    }

    private func verarbeiten(_ text: String) {
        guard let nachricht = Kanalnachricht.lesen(text) else { return }
        switch nachricht {
        case .lebenszeichenVerlangt:
            senden(#"{"MessageType":"KeepAlive"}"#)
        case .auftrag:
            Spur.sag("[Steuerkanal] Befehl: \(nachricht)")
            empfang?(nachricht)
        case .sonstiges:
            break
        }
    }

    /// **Neu verbinden, mit wachsender Pause** (``Kanalregel/wartezeit(nachAbrissen:)``).
    /// Ein Server, der neu startet, ist kein Netzwechsel — ohne Wiederaufbau
    /// bliebe die Sitzung bis zum nächsten App-Start stumm.
    private func verloren(_ leitung: URLSessionWebSocketTask, fehler: Error) {
        // Eine alte Leitung, die nach einem Neustart noch abreißt, zählt nicht.
        guard leitung === aufgabe else { return }
        var teile = ["[Steuerkanal] Leitung verloren"]
        if let http = leitung.response as? HTTPURLResponse { teile.append("HTTP \(http.statusCode)") }
        if leitung.closeCode != .invalid { teile.append("Schliesscode \(leitung.closeCode.rawValue)") }
        teile.append("\(fehler)")
        Spur.sag(teile.joined(separator: " · "))
        leitung.cancel(with: .abnormalClosure, reason: nil)
        aufgabe = nil
        herzschlag?.cancel(); herzschlag = nil
        guard empfang != nil else { return }
        abrisse += 1
        let warten = Kanalregel.wartezeit(nachAbrissen: abrisse)
        wiederaufbau = Task { [weak self] in
            try? await Task.sleep(for: .seconds(warten))
            guard !Task.isCancelled, let self else { return }
            await self.nochmal()
        }
    }

    private func nochmal() {
        guard let empfang, aufgabe == nil else { return }
        starten(empfang)
    }

    /// Alle 30 Sekunden ein Lebenszeichen — sonst räumt der Server auf.
    private func schlagen() {
        herzschlag?.cancel()
        herzschlag = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Kanalregel.lebenszeichen))
                // `try?` verschluckt den Abbruch; ohne diese Zeile ginge nach
                // dem Beenden noch ein Lebenszeichen hinaus.
                guard !Task.isCancelled, let self else { return }
                await self.senden(#"{"MessageType":"KeepAlive"}"#)
            }
        }
    }

    private func senden(_ text: String) {
        guard let aufgabe else { return }
        Task {
            do {
                try await aufgabe.send(.string(text))
            } catch {
                Spur.sag("[Steuerkanal] senden fehlgeschlagen: \(error)")
            }
        }
    }
}

/// Die Zahlen des Kanals, prüfbar ohne Leitung.
public enum Kanalregel {
    /// Sekunden zwischen zwei Lebenszeichen — dieselben 30 wie in
    /// ``Fernsteuerung``, dort am 10.09.2026 gemessen.
    public static let lebenszeichen: Double = 30

    /// 2, 4, 8, 16, dann 30 Sekunden: ein dauerhaft toter Server wird nicht
    /// im Sekundentakt angeklopft, ein kurz neu gestarteter ist schnell
    /// wieder da.
    public static func wartezeit(nachAbrissen n: Int) -> Int {
        min(30, 1 << min(max(n, 1), 5))
    }
}
