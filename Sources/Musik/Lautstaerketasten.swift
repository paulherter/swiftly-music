import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// **Lauter und Leiser am iPhone, solange Sonos spielt** — wie bei Spotify.
///
/// iOS gibt die Tasten keiner App direkt. Was geht: eine aktive Tonsitzung
/// (`.playback`), und dann meldet `outputVolume` jeden Druck als Änderung. Die Richtung reicht —
/// jeder Druck ist eine Stufe am Lautsprecher (``Sonosmodell/stufe``).
///
/// **App Review 2.5.9** verbietet, Standardschalter wie die Lautstärketasten
/// zu verändern oder abzuschalten. Deshalb nur beobachten und weiterreichen,
/// wie Spotify und die Sonos-App es tun:
/// - **Gesetzt wird die Systemlautstärke nie**, auch nicht zurück. Die
///   Tasten tun also weiter, was sie immer tun; am Anschlag (ganz oben oder
///   unten) kommt ein Druck in diese Richtung nicht mehr an.
/// - Die Anzeige des Systems versteckt ein ``Lautstaerkeversteck`` nur,
///   solange unser Lautstärke-Blatt offen ist (``Sonosmodell/anzeigeVerstecken``).
/// - Einen Schalter dafür gibt es nicht: die Tasten steuern Sonos immer,
///   solange dort gespielt wird (25.09.).
@MainActor
@Observable
final class Lautstaerketasten {
    /// `+1` für Lauter, `-1` für Leiser.
    @ObservationIgnored var gedrueckt: ((Int) -> Void)?
    /// Ob die Tasten gerade abgefangen werden — dann steht das Versteck im Fenster.
    private(set) var aktiv = false
    @ObservationIgnored private var beobachtung: NSKeyValueObservation?

    /// **Die Sitzung des Spielers, aktiv — nicht mischbar.** Eine mischbare
    /// Sitzung (`mixWithOthers`, bis 25.09.) macht die App für iOS zu einer,
    /// die nur nebenher klingt: dann ist sie nicht die Now-Playing-App, und
    /// Sperrbildschirm und Dynamic Island blieben leer. Dieselbe Kategorie wie
    /// ``Spieler`` (`.longFormAudio`), damit nichts umschaltet.
    func an() {
        guard !aktiv else { return }
        let sitzung = AVAudioSession.sharedInstance()
        do {
            try sitzung.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try sitzung.setActive(true)
        } catch {
            Protokoll.schreib("[Sonos] Tasten: Tonsitzung nicht aktiv (\(error.localizedDescription))")
            return
        }
        Protokoll.schreib("[Sonos] Tonsitzung aktiv, nicht mischbar — Tasten an")
        aktiv = true
        beobachtung = sitzung.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, wechsel in
            guard let neu = wechsel.newValue, let alt = wechsel.oldValue, neu != alt else { return }
            let richtung = neu > alt ? 1 : -1
            Task { @MainActor in self?.gedrueckt?(richtung) }
        }
    }

    /// Nur nicht mehr hinhören. **Die Sitzung bleibt aktiv** — auch im
    /// Hintergrund, damit Sperrbildschirm und Dynamic Island den Stand von
    /// Sonos weiter zeigen; der Spieler übernimmt sie beim Zurückholen.
    func aus() {
        guard aktiv else { return }
        aktiv = false
        beobachtung?.invalidate()
        beobachtung = nil
    }
}

/// **Ein `MPVolumeView`, das niemand sieht.** Steht eines im Fenster, zeigt
/// iOS seine eigene Lautstärkeanzeige nicht — dafür unser Lautstärke-Blatt.
/// Es liegt außerhalb des Schirms und ist fast durchsichtig; ganz
/// unsichtbar (`isHidden`, Deckkraft 0) zählte es für iOS nicht.
struct Lautstaerkeversteck: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        v.alpha = 0.01
        v.isUserInteractionEnabled = false
        v.accessibilityElementsHidden = true
        return v
    }

    func updateUIView(_ v: MPVolumeView, context: Context) {}
}
