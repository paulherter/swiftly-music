import AVFoundation
import Combine
import MusikKit

/// **Das laufende Item gegen seine genaue Fassung tauschen — an derselben
/// Stelle** (``Genaufassung``).
///
/// Zuerst lädt das Asset der Datei seine Eigenschaften — mit
/// `AVURLAssetPreferPreciseDurationAndTimingKey` liest AVFoundation dafür die
/// ganze Datei einmal durch; das geschieht hier vorab, nicht im Augenblick
/// des Tauschs. Dann wird eine Stelle knapp voraus gewählt
/// (``Genaufassung/vorlauf(laeuft:)``). Kommt das laufende Item dort an
/// (`addBoundaryTimeObserver`), rückt das neue in den `AVQueuePlayer`, der
/// Player schaltet weiter und springt im neuen genau an diese Stelle.
///
/// Zwei naheliegende Wege tragen nicht (gemessen 25.09.): hinter dem
/// laufenden Item im `AVQueuePlayer` wird das neue nicht bereit, solange das
/// laufende noch vom Server lädt (nach 28 s noch `unknown`); und ein Item,
/// das ein Hilfsplayer vorbereitet hat, nimmt kein zweiter Player an
/// („cannot be associated with more than one instance of AVPlayer").
///
/// Der Tausch selbst kostet Ton: nach dem Weiterschalten steht er 0,44–0,6 s,
/// bis das neue Item läuft — etwa so lange wie nach jedem Sprung
/// (0,48–0,49 s, mit dem Tap am Item). Wann getauscht
/// wird, entscheidet deshalb ``Genaufassung/einwechseln(stelle:dauer:springt:bereit:laeuft:verrutscht:)``:
/// in der Pause, mit einem Sprung, oder mitten im Spielen nur, um einen
/// ungenauen Sprung zu berichtigen.
///
/// Steht der Player, wird sofort an derselben Stelle getauscht. Ändert sich
/// unterwegs der Lauf (Pause, Warten), wird neu gewählt. Ist das laufende
/// Item nicht mehr das alte, wird abgebrochen. `sprung`: an ein festes Ziel
/// und sofort — ein Sprung von Hand, der gleich genau landet.
///
/// Keine Schließung, die AVFoundation auf einem fremden Faden ruft, ist an
/// den Hauptakteur gebunden (siehe ``Spieler``).
@MainActor
final class Genauwechsel {

    enum Art: Equatable {
        case mitlaufen
        case sprung(TimeInterval)
    }

    enum Ausgang: Equatable { case getauscht, abgebrochen }

    let alt: AVPlayerItem
    let neu: AVPlayerItem
    let art: Art
    /// Genau einmal: nach dem Tausch (das neue Item steht an der Stelle)
    /// oder nach dem Abbruch.
    var fertig: ((Ausgang) -> Void)?

    private let player: AVQueuePlayer
    private var vorbereitung: Task<Void, Never>?
    private var lauf: AnyCancellable?
    private var grenze: Any?
    private var ziel: CMTime?
    private var versuche = 0
    private var vorbei = false
    private var getauscht = false

    init(player: AVQueuePlayer, alt: AVPlayerItem, neu: AVPlayerItem, art: Art) {
        self.player = player
        self.alt = alt
        self.neu = neu
        self.art = art
    }

    func starten() {
        guard player.currentItem === alt else {
            beenden(.abgebrochen)
            return
        }
        let asset = neu.asset
        vorbereitung = Task { [weak self] in
            let bereit = (try? await asset.load(.isPlayable)) ?? false
            _ = try? await asset.load(.duration, .tracks)
            guard let self, !Task.isCancelled else { return }
            guard bereit else {
                self.beenden(.abgebrochen)
                return
            }
            self.lauf = self.player.publisher(for: \.timeControlStatus)
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.laufGewechselt() }
            self.planen()
        }
    }

    func abbrechen() { beenden(.abgebrochen) }

    /// Pause, Warten, weiter: die Stelle von eben stimmt nicht mehr.
    private func laufGewechselt() {
        guard !vorbei, !getauscht, grenze != nil else { return }
        planen()
    }

    /// Die Stelle wählen, an der getauscht wird.
    private func planen() {
        guard !vorbei, !getauscht else { return }
        grenzeWeg()
        guard player.currentItem === alt, versuche < 8 else {
            beenden(.abgebrochen)
            return
        }
        versuche += 1
        switch art {
        case let .sprung(sekunden):
            tauschen(an: CMTime(seconds: sekunden, preferredTimescale: 44_100))
        case .mitlaufen:
            let jetzt = player.currentTime()
            guard player.timeControlStatus == .playing else {
                tauschen(an: jetzt)
                return
            }
            let z = CMTimeAdd(jetzt, CMTime(seconds: Genaufassung.vorlauf(laeuft: true), preferredTimescale: 44_100))
            ziel = z
            grenze = player.addBoundaryTimeObserver(forTimes: [NSValue(time: z)], queue: .main) { [weak self] in
                MainActor.assumeIsolated { self?.grenzeErreicht() }
            }
        }
    }

    private func grenzeErreicht() {
        guard !vorbei, !getauscht, let ziel else { return }
        tauschen(an: ziel)
    }

    private func tauschen(an stelle: CMTime) {
        guard !vorbei, !getauscht else { return }
        grenzeWeg()
        guard player.currentItem === alt else {
            beenden(.abgebrochen)
            return
        }
        getauscht = true
        player.insert(neu, after: alt)
        player.advanceToNextItem()
        player.seek(to: stelle, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.beenden(.getauscht) }
        }
    }

    private func grenzeWeg() {
        if let grenze { player.removeTimeObserver(grenze) }
        grenze = nil
    }

    private func beenden(_ ausgang: Ausgang) {
        guard !vorbei else { return }
        vorbei = true
        vorbereitung?.cancel()
        grenzeWeg()
        lauf = nil
        let melden = fertig
        fertig = nil
        melden?(getauscht ? .getauscht : ausgang)
    }
}
