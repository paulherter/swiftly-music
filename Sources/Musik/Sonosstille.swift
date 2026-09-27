import AVFoundation
import Foundation

/// **Stille, solange Sonos spielt — damit iOS die App als laufend zeigt.**
///
/// Wie bei Spotify (25.09.): Spielt die Musik auf Sonos, gibt das
/// iPhone unhörbare Stille aus. Dann ist diese App für iOS die, die gerade
/// spielt — Dynamic Island und Sperrbildschirm zeigen Hülle, Titel und die
/// laufende Stelle vom Sonos-Stand, und ihre Tasten gehen über
/// `MPRemoteCommandCenter` an den Lautsprecher (``Spieler`` reicht jeden
/// Befehl weiter, solange ``Spieler/fern`` Sonos ist). Und weil die App
/// dadurch wach bleibt, fragt ``Sonosmodell`` im Hintergrund weiter ab
/// (alle 5 s) — ein Liedwechsel drüben kommt so auch bei gesperrtem iPhone an.
///
/// **App Review 2.5.4** erlaubt Hintergrundton nur für hörbare Inhalte; Stille
/// in Dauerschleife kann beim Einreichen hinterfragt werden. Das ist eine
/// bewusste Entscheidung — Spotify macht es bei Sonos genauso.
///
/// **Sparsam:** ein `AVAudioPlayer` mit einer halben Sekunde Stille,
/// 8 kHz mono, in Endlosschleife — keine Engine, kein Rechnen je Probe.
/// Die Tonsitzung ist dieselbe wie beim ``Spieler`` und bei den
/// ``Lautstaerketasten`` (`.playback`, `.longFormAudio`, nicht mischbar);
/// die Systemlautstärke wird nie gesetzt, die Tasten reichen weiter wie bisher.
///
/// **Regeln:**
/// - Nie Stille, wenn nicht Sonos spielt — ``setzen(_:)`` bekommt nur
///   ``Fernstand/laeuft`` des Sonos-Ziels.
/// - Beim Zurückholen und Abmelden sofort aus (``Sonosmodell/loslassen(anhalten:)``,
///   ``Sonosmodell/beenden()``), bevor der ``Spieler`` die Sitzung übernimmt.
/// - Ein Anruf unterbricht nur die Stille; danach geht sie wieder an, wenn
///   Sonos noch spielt. Sonos selbst bekommt davon keinen Befehl, und der
///   Abgleich liest die Unterbrechung nie als Pause — keine Rückkopplung.
@MainActor
final class Sonosstille {

    /// Soll Stille laufen — Sonos spielt. Auch während eines Anrufs `true`.
    private(set) var an = false
    /// Meldet jeden Wechsel von ``an`` — der Takt der Abfrage folgt ihm.
    var gewechselt: (() -> Void)?

    private var spieler: AVAudioPlayer?
    /// Ein Anruf, ein Wecker: die Sitzung gehört gerade dem System.
    private var unterbrochen = false
    private var beobachtungen: [any NSObjectProtocol] = []

    init() {
        let zentrale = NotificationCenter.default
        beobachtungen.append(zentrale.addObserver(forName: AVAudioSession.interruptionNotification,
                                                  object: nil, queue: .main) { [weak self] meldung in
            let roh = meldung.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated { self?.unterbrechung(roh) }
        })
        beobachtungen.append(zentrale.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                                  object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dienstNeuGestartet() }
        })
    }

    /// **Sonos spielt (`true`) oder nicht.** Nur ein Wechsel tut etwas.
    func setzen(_ soll: Bool) {
        guard soll != an else { return }
        an = soll
        if soll { starten() } else { anhalten() }
        Protokoll.schreib("[Sonos] Stille \(soll ? "an" : "aus")")
        gewechselt?()
    }

    private func starten() {
        guard an, !unterbrochen else { return }
        let sitzung = AVAudioSession.sharedInstance()
        do {
            try sitzung.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try sitzung.setActive(true)
        } catch {
            Protokoll.schreib("[Sonos] Stille: Tonsitzung nicht aktiv (\(error.localizedDescription))")
            return
        }
        if spieler == nil {
            guard let neu = try? AVAudioPlayer(data: Self.stille, fileTypeHint: AVFileType.wav.rawValue) else {
                Protokoll.schreib("[Sonos] Stille: Spieler nicht angelegt")
                return
            }
            neu.numberOfLoops = -1
            neu.prepareToPlay()
            spieler = neu
        }
        spieler?.play()
    }

    /// Nur anhalten — die Sitzung bleibt aktiv, damit die App die
    /// Now-Playing-App bleibt (pausiert) und der ``Spieler`` sie beim
    /// Zurückholen ohne Umschalten übernimmt.
    private func anhalten() {
        spieler?.pause()
    }

    private func unterbrechung(_ roh: UInt?) {
        guard let roh, let art = AVAudioSession.InterruptionType(rawValue: roh) else { return }
        switch art {
        case .began:
            unterbrochen = true
        case .ended:
            unterbrochen = false
            // Ohne Blick auf `shouldResume`: es ist Stille, und Sonos spielte
            // die ganze Zeit weiter — nur die Anzeige hier soll wieder laufen.
            if an { starten() }
        @unknown default:
            break
        }
    }

    /// Nach einem Neustart der Mediendienste ist der alte Spieler tot.
    private func dienstNeuGestartet() {
        spieler = nil
        unterbrochen = false
        if an { starten() }
    }

    /// **Eine halbe Sekunde Stille als WAV**, 8 kHz, mono, 16 bit — 8 KB.
    static let stille: Data = {
        let rate: UInt32 = 8000
        let proben = rate / 2
        let bytes = proben * 2
        var d = Data()
        func text(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func zahl32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func zahl16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        text("RIFF"); zahl32(36 + bytes); text("WAVE")
        text("fmt "); zahl32(16); zahl16(1); zahl16(1); zahl32(rate); zahl32(rate * 2); zahl16(2); zahl16(16)
        text("data"); zahl32(bytes)
        d.append(Data(count: Int(bytes)))
        return d
    }()
}
