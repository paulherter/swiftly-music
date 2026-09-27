import MediaPlayer
import MusikKit
import UIKit

/// **Sperrbildschirm, Kontrollzentrum, Kopfhörertasten.**
///
/// `MPNowPlayingInfoCenter` bekommt Titel, Künstler, Album, Dauer, Stelle,
/// Rate und Hülle; `MPRemoteCommandCenter` die Befehle Abspielen, Pause,
/// Umschalten, Weiter, Zurück, die Spulleiste, Zufall und Wiederholen.
///
/// **Keine Schließung hier ist an den Hauptakteur gebunden.** MediaPlayer
/// ruft die Befehle und die Bildanfrage der Hülle auf einem eigenen Faden;
/// eine Schließung, die Swift 6 dem Hauptakteur zugeordnet hat, stürzt dort
/// ab. Deshalb entstehen sie in `nonisolated`-Funktionen, und die Befehle
/// springen ausdrücklich zurück (`Task { @MainActor … }`).
@MainActor
final class Jetztlaeuft {

    private var info: [String: Any] = [:]
    private var liedID: String?

    func setzen(lied: Lied, dauer: TimeInterval?, position: TimeInterval, laeuft: Bool) {
        if liedID != lied.id {
            info = [:]
            liedID = lied.id
        }
        info[MPMediaItemPropertyTitle] = lied.titel
        info[MPMediaItemPropertyArtist] = lied.kuenstlerzeile
        info[MPMediaItemPropertyAlbumTitle] = lied.album
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        zeitSetzen(position: position, dauer: dauer, laeuft: laeuft)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func zeit(position: TimeInterval, dauer: TimeInterval?, laeuft: Bool) {
        guard liedID != nil else { return }
        zeitSetzen(position: position, dauer: dauer, laeuft: laeuft)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func zeitSetzen(position: TimeInterval, dauer: TimeInterval?, laeuft: Bool) {
        info[MPMediaItemPropertyPlaybackDuration] = dauer
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position.isFinite ? max(0, position) : 0
        // Mit der Rate rechnet das System die Stelle selbst weiter; in der
        // Pause muss sie 0 sein, sonst läuft die Leiste im Sperrbildschirm.
        info[MPNowPlayingInfoPropertyPlaybackRate] = laeuft ? 1.0 : 0.0
    }

    func bild(_ bild: UIImage) {
        guard liedID != nil else { return }
        info[MPMediaItemPropertyArtwork] = Self.hueller(bild)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Zufall und Wiederholen, wie sie im Blatt stehen — damit Kontrollzentrum
    /// und CarPlay denselben Stand zeigen.
    func modiSetzen(gemischt: Bool, wiederholung: Warteschlange.Wiederholung) {
        let zentrale = MPRemoteCommandCenter.shared()
        zentrale.changeShuffleModeCommand.currentShuffleType = gemischt ? .items : .off
        zentrale.changeRepeatModeCommand.currentRepeatType = switch wiederholung {
        case .aus: .off
        case .alles: .all
        case .eines: .one
        }
    }

    func leeren() {
        info = [:]
        liedID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Außerhalb des Hauptakteurs gebaut: MediaPlayer fragt das Bild auf
    /// einem eigenen Faden ab.
    nonisolated private static func hueller(_ bild: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: bild.size) { _ in bild }
    }

    // MARK: - Befehle

    func befehleEinrichten(fuer spieler: Spieler) {
        Self.befehle(Befehlsweg(spieler: spieler))
    }

    /// Hält den Spieler schwach und springt für jeden Befehl auf den
    /// Hauptlauf.
    struct Befehlsweg: Sendable {
        weak var spieler: Spieler?

        func tun(_ was: @escaping @MainActor @Sendable (Spieler) -> Void) {
            Task { @MainActor [spieler] in
                if let spieler { was(spieler) }
            }
        }
    }

    nonisolated private static func befehle(_ weg: Befehlsweg) {
        let zentrale = MPRemoteCommandCenter.shared()

        zentrale.playCommand.isEnabled = true
        zentrale.playCommand.addTarget { _ in
            weg.tun { $0.abspielen() }
            return .success
        }
        zentrale.pauseCommand.isEnabled = true
        zentrale.pauseCommand.addTarget { _ in
            weg.tun { $0.pausieren() }
            return .success
        }
        zentrale.togglePlayPauseCommand.isEnabled = true
        zentrale.togglePlayPauseCommand.addTarget { _ in
            weg.tun { $0.umschalten() }
            return .success
        }
        zentrale.nextTrackCommand.isEnabled = true
        zentrale.nextTrackCommand.addTarget { _ in
            weg.tun { $0.weiter() }
            return .success
        }
        zentrale.previousTrackCommand.isEnabled = true
        zentrale.previousTrackCommand.addTarget { _ in
            weg.tun { $0.zurueck() }
            return .success
        }
        zentrale.changePlaybackPositionCommand.isEnabled = true
        zentrale.changePlaybackPositionCommand.addTarget { ereignis in
            guard let e = ereignis as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let stelle = e.positionTime
            weg.tun { $0.springe(auf: stelle) }
            return .success
        }
        // Was es nicht gibt, bleibt aus — sonst zeigt der Sperrbildschirm
        // Knöpfe, die nichts tun.
        zentrale.skipForwardCommand.isEnabled = false
        zentrale.skipBackwardCommand.isEnabled = false
        zentrale.seekForwardCommand.isEnabled = false
        zentrale.seekBackwardCommand.isEnabled = false
        zentrale.likeCommand.isEnabled = false
        zentrale.dislikeCommand.isEnabled = false
        zentrale.bookmarkCommand.isEnabled = false
        zentrale.changeShuffleModeCommand.isEnabled = true
        zentrale.changeShuffleModeCommand.addTarget { ereignis in
            guard let e = ereignis as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            let an = e.shuffleType != .off
            weg.tun { $0.mischen(an) }
            return .success
        }
        zentrale.changeRepeatModeCommand.isEnabled = true
        zentrale.changeRepeatModeCommand.addTarget { ereignis in
            guard let e = ereignis as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let neu: Warteschlange.Wiederholung = switch e.repeatType {
            case .one: .eines
            case .all: .alles
            default: .aus
            }
            weg.tun { $0.wiederholen(neu) }
            return .success
        }
    }
}
