import AVFoundation
import Combine
import MediaPlayer
import MediaToolbox
import MusikKit
import SwiftUI
import Synchronization
import UIKit

/// **Der Spieler: AVQueuePlayer mit dem nächsten Lied vorgeladen.**
///
/// Die Reihenfolge weiß die ``Warteschlange`` (MusikKit); hier liegen nur
/// zwei Einträge im `AVQueuePlayer` — der laufende und der nächste. So
/// beginnt das nächste Lied ohne Lücke, und jede Änderung an der Schlange
/// („Als Nächstes", Mischen, Entfernen) muss nur den zweiten Platz abgleichen
/// (``naechstenAbgleichen()``).
///
/// **Alles läuft auf dem Hauptlauf.** Beobachtungen kommen über Combine mit
/// `receive(on: DispatchQueue.main)` herein, die Zeit über einen periodischen
/// Beobachter auf der Hauptschlange, Fernbefehle und Sprungabschlüsse über
/// einen ausdrücklichen Sprung zurück (`Task { @MainActor … }`). Keine
/// Schließung, die AVFoundation auf einem fremden Faden ruft, ist an den
/// Hauptakteur gebunden — sonst stürzt Swift 6 dort ab.
///
/// **Der Wechsel wird am Zustand gelesen, nicht am Ereignis.** Welches Lied
/// läuft, entscheidet `player.currentItem`, nachgeschlagen in ``kennungen``.
/// ``aktuellesAbgleichen()`` darf deshalb beliebig oft kommen — nach einem
/// eigenen Sprung sofort, und später noch einmal über die Beobachtung, ohne
/// dass etwas doppelt geschieht.
@MainActor
@Observable
final class Spieler {

    // MARK: Zustand für die Oberfläche

    private(set) var schlange = Warteschlange()
    /// Ob gespielt werden **soll** — der Knopf zeigt Pause.
    private(set) var spielt = false
    /// **Der Player wartet sichtbar lange auf Daten** — erst nach
    /// ``Ladeanzeige/schwelle``. Das kurze Warten nach jedem Abspielen
    /// bleibt unsichtbar; das Zeichen hängt nur an `spielt`.
    private(set) var puffert = false
    /// Sekunden im laufenden Lied.
    private(set) var position: TimeInterval = 0
    private(set) var dauer: TimeInterval?
    /// Wie das laufende Lied kommt — für die Plakette.
    private(set) var weg: Abspielweg?
    /// Die Sammlung, aus der die Schlange stammt — für die Laufmarke auf
    /// „Zuletzt gehört".
    private(set) var herkunft: Sammlungsverweis?
    /// Die Farbe aus der Hülle, für die Glut im Blatt.
    private(set) var glut: Huellenton.Glut?
    /// Wohin der Ton geht: „iPhone", „AirPods", „Wohnzimmer".
    private(set) var ausgabename = ""
    /// Ein Fehler zum Anzeigen; die Oberfläche setzt ihn zurück.
    var fehler: String?
    /// **Läuft die Wiedergabe auf einem anderen Gerät?** Dann zeigen Blatt
    /// und Mini-Player dessen Stand (``fernSpiegeln(_:lieder:index:)``), und
    /// jeder Knopf geht als Befehl dorthin (``fernsteuern``) — die Ansichten
    /// müssen davon nichts wissen.
    private(set) var fern: Fernanzeige?
    /// Was ein anderes Gerät per `SetVolume` gesetzt hat, 0 bis 1.
    private(set) var fernLautstaerke: Double = 1
    private(set) var stumm = false

    var aktuell: Lied? { schlange.aktuell?.lied }

    /// **Die Stelle je Bild** (24.09.: Spur und Griffpunkt liefen
    /// ruckweise, im Takt der halben Sekunde von ``position``). Die Uhr
    /// rechnet zwischen den Meldungen hoch; jede Zuweisung an `position`
    /// stellt sie nach — kleine Abweichungen gleiten, Sprünge springen.
    @ObservationIgnored private var uhr = Stellenuhr()
    /// Ob die Anzeige läuft — sonst stehen die Zeitleisten der Oberfläche
    /// still und rechnen nichts.
    private(set) var uhrLaeuft = false

    /// Die Stelle für die Anzeige, in diesem Bild. Liest ``position`` mit,
    /// damit ein Sprung in der Pause neu zeichnet.
    func anzeigestelle() -> TimeInterval {
        _ = position
        if fern == nil, let sprungziel { return sprungziel }
        return uhr.stelle(jetzt: CACurrentMediaTime())
    }

    /// Wie schnell es gerade läuft — 0 in der Pause und beim Puffern.
    private var laufrate: Double {
        if fern != nil { return spielt ? 1 : 0 }
        return player.timeControlStatus == .playing ? Double(player.rate) : 0
    }

    private func uhrStellen(_ stelle: TimeInterval) {
        uhr.melden(stelle, rate: laufrate, jetzt: CACurrentMediaTime())
        let laeuft = uhr.rate > 0
        if uhrLaeuft != laeuft { uhrLaeuft = laeuft }
    }

    /// Die Stelle, frisch vom Player — für den Liedtext, der feiner folgen
    /// muss als die halbe Sekunde von ``position``.
    func stelle() -> TimeInterval {
        if fern != nil { return position }
        if let sprungziel { return sprungziel }
        let s = player.currentTime().seconds
        return s.isFinite ? s : position
    }

    // MARK: Anschlüsse

    @ObservationIgnored var quelle: (any Musikquelle)?
    @ObservationIgnored weak var ablage: Ablage?
    @ObservationIgnored weak var einstellungen: Musikeinstellungen?
    /// Das Netz, über das gerade gestreamt würde (``Netzwaechter``).
    @ObservationIgnored var verbindung: Verbindung = .wlan {
        didSet { if verbindung != oldValue { genauAbgleichen() } }
    }
    /// Datensparmodus — dann lädt keine genaue Fassung nebenher.
    @ObservationIgnored var sparsam = false {
        didSet { if sparsam != oldValue { genauAbgleichen() } }
    }
    /// Wird gerufen, wenn sich Schlange, Lied oder Lauf ändern — dann legt
    /// das Modell den ``Schlangenstand`` ab.
    @ObservationIgnored var geaendert: (() -> Void)?
    /// Ein gehörtes Lied, das der Server gerade nicht annimmt — das Modell
    /// merkt es und trägt es nach (``Nachtragsliste``).
    @ObservationIgnored var nachtragen: ((Nachtrag) -> Void)?
    /// Schickt einen Befehl an das Gerät in ``fern`` (`Fernmodell`).
    @ObservationIgnored var fernsteuern: ((Fernaktion) -> Void)?
    /// Dasselbe für einen Sonos-Lautsprecher (`Sonosmodell`).
    @ObservationIgnored var sonossteuern: ((Fernaktion) -> Void)?
    /// **Sonos: die Schlange hat sich geändert** — das nächste Lied am
    /// Lautsprecher nachziehen.
    @ObservationIgnored var sonosSchlangeGeaendert: (() -> Void)?
    /// Einmal gesagt, dass sich die Schlange drüben nicht umstellen lässt.
    @ObservationIgnored var fernHinweis: ((String) -> Void)?

    // MARK: Innen

    @ObservationIgnored private var player = AVQueuePlayer()
    /// `AVPlayerItem` → Eintrag der Schlange.
    @ObservationIgnored private var kennungen: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored private var wege: [UUID: Abspielweg] = [:]
    /// Wo ein Eintrag anfangen soll, sobald er bereit ist (Hörbuch).
    @ObservationIgnored private var startstellen: [UUID: TimeInterval] = [:]
    /// Zurück von einem anderen Gerät: dieser Eintrag spielt erst, wenn er
    /// an seiner Startstelle steht (``fernBeenden(lieder:ab:stelle:spielen:)``).
    @ObservationIgnored private var losNachSprung: UUID?
    /// Einträge, deren Vorladen gescheitert ist — sie werden erst wieder
    /// angelegt, wenn sie dran sind.
    @ObservationIgnored private var gescheitert = Set<UUID>()
    @ObservationIgnored private var beobachtungen = Set<AnyCancellable>()
    @ObservationIgnored private var itemBeobachtungen: [ObjectIdentifier: AnyCancellable] = [:]
    @ObservationIgnored private var zeitbeobachter: Any?
    @ObservationIgnored private var meldetakt: Task<Void, Never>?
    @ObservationIgnored private var hoerzeit = Hoerzeit()
    @ObservationIgnored private var meldestand: Meldestand?
    /// Wir selbst haben weitergeschaltet — sonst war es das Ende des Liedes.
    @ObservationIgnored private var eigenerWechsel = false
    @ObservationIgnored private var fehlschlaege = 0
    @ObservationIgnored private var spielteVorUnterbrechung = false
    @ObservationIgnored private var ladeanzeige = Ladeanzeige()
    @ObservationIgnored private var ladepruefung: Task<Void, Never>?
    @ObservationIgnored private var angezeigterEintrag: UUID?
    /// **Wohin gerade gesprungen wird**, bis der Player dort ist. Solange
    /// meldet der Zeitbeobachter noch die alte Stelle — die Spur sprang nach
    /// dem Loslassen kurz dorthin zurück und dann erst zur neuen.
    @ObservationIgnored private var sprungziel: TimeInterval?
    @ObservationIgnored private var sprungnummer = 0
    @ObservationIgnored private let jetzt = Jetztlaeuft()
    /// Die Schlange, die beim Wegwischen der Pille stand (``wegraeumen()``).
    @ObservationIgnored private var ruhend: Schlangenstand?
    /// Welcher Tap an welchem Item hängt (``Pegelleitung/aktiv``).
    @ObservationIgnored private var tapkennungen: [ObjectIdentifier: UInt64] = [:]
    @ObservationIgnored private var naechsteTapkennung: UInt64 = 1
    /// **Die genaue Fassung gestreamter FLAC-Dateien** (``Genaufassung``):
    /// nebenher geladen, eingewechselt in der Pause oder mit einem Sprung.
    @ObservationIgnored private let genau = Genaulager()
    @ObservationIgnored private var wechsel: Genauwechsel?
    /// Items mit `AVURLAssetPreferPreciseDurationAndTimingKey` — dort
    /// sitzt jeder Sprung, dort gibt es nichts zu tauschen.
    @ObservationIgnored private var praezise = Set<ObjectIdentifier>()
    /// Gestreamte FLAC-Items, in denen ungenau gesprungen wurde: Ton und
    /// Anzeige liegen auseinander, bis die genaue Fassung kommt.
    @ObservationIgnored private var verrutscht = Set<ObjectIdentifier>()
    /// Ein Sprung, der auf die gleich fertige Datei wartet
    /// (``Genaufassung/sprungAbwarten(restzeit:)``).
    @ObservationIgnored private var wartenderSprung: (nummer: Int, ziel: TimeInterval, lied: String)?

    /// Was dem Server über das laufende Lied schon gesagt ist.
    private struct Meldestand {
        let eintrag: UUID
        let lied: Lied
        let weg: Abspielweg
        var beginn: Date?
        var gehoert = false
    }

    init() {
        // Die geteilte Leitung einmal hier anlegen — nicht beim ersten
        // Zugriff im Tonfaden, wo das Anlegen eine Sperre nähme.
        Pegelleitung.vorbereiten()
        playerEinrichten()
        systemEinrichten()
        ausgabeAktualisieren()
        jetzt.befehleEinrichten(fuer: self)
        genau.fertig = { [weak self] lied in self?.genauDa(lied) }
    }

    // MARK: - Einrichten

    private func playerEinrichten() {
        player.actionAtItemEnd = .advance
        player.allowsExternalPlayback = true

        player.publisher(for: \.currentItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.aktuellesAbgleichen()
                self?.pegelAbgleichen()
            }
            .store(in: &beobachtungen)

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.laufzustandGewechselt() }
            .store(in: &beobachtungen)

        zeitbeobachter = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] zeit in
            // Die Schlange ist `.main`, also läuft das hier auf dem Hauptlauf.
            MainActor.assumeIsolated { self?.takt(zeit) }
        }
    }

    private func systemEinrichten() {
        let zentrale = NotificationCenter.default

        zentrale.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meldung in self?.liedZuEnde(meldung.object as AnyObject?) }
            .store(in: &beobachtungen)

        zentrale.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meldung in
                let grund = meldung.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self?.itemGescheitert(meldung.object as AnyObject?, grund: grund)
            }
            .store(in: &beobachtungen)

        zentrale.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meldung in self?.unterbrechung(meldung.userInfo) }
            .store(in: &beobachtungen)

        zentrale.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meldung in self?.ausgabeGewechselt(meldung.userInfo) }
            .store(in: &beobachtungen)

        zentrale.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.dienstNeuGestartet() }
            .store(in: &beobachtungen)

        // Die Kategorie gleich zu Beginn, aktiviert wird erst beim ersten
        // Abspielen — sonst hielte ein bloßer App-Start fremde Musik an.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                         policy: .longFormAudio, options: [])
    }

    private func sitzungAktivieren() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Ohne aktive Sitzung spielt AVFoundation trotzdem, nur ohne
            // Hintergrund und Sperrbildschirm — kein Grund abzubrechen.
        }
    }

    // MARK: - Abspielen

    /// **Die Schlange führt hier**: ohne anderes Gerät, und bei Sonos — der
    /// Lautsprecher kennt nur das laufende und das nächste Lied, alles
    /// andere entscheidet diese Schlange. Bei Connect steht hier nur die
    /// Spiegelung der Schlange drüben.
    var schlangeIstEigen: Bool { fern == nil || fern?.art == .sonos }

    private var sonosFuehrt: Bool { fern?.art == .sonos }

    /// Ein Befehl an das Gerät in ``fern`` — Connect oder Sonos.
    private func fernSenden(_ aktion: Fernaktion) {
        if sonosFuehrt { sonossteuern?(aktion) } else { fernsteuern?(aktion) }
    }

    /// **Sonos: ein anderes Lied der eigenen Schlange ist dran.** Die
    /// Anzeige folgt sofort, der Lautsprecher lädt es (``Sonosmodell``).
    /// `spielen`: es soll laufen (ein Lied gewählt); sonst bleibt, was war —
    /// „Weiter" in der Pause bleibt in der Pause, wie hier auf dem iPhone.
    private func sonosNeu(stelle: TimeInterval, spielen: Bool = false) {
        position = stelle
        uhrStellen(position)
        if let lied = aktuell { dauer = lied.dauer }
        fernSenden(.spielen(ids: schlange.eintraege.map(\.lied.id), ab: schlange.position ?? 0, stelle: stelle))
        if spielen { fernSenden(.weiter) }
        fernLied = aktuell?.id
        jetzt.modiSetzen(gemischt: schlange.gemischt, wiederholung: schlange.wiederholung)
        jetztLaeuftSetzen()
        glutLaden()
        geaendert?()
    }

    /// **Eine neue Schlange spielen.** `ab`: das gewählte Lied; `nil` mit
    /// `mischen` heißt „Zufall" — dann ist auch das erste zufällig.
    func spiele(_ lieder: [Lied], ab start: Int?, mischen: Bool, herkunft: Sammlungsverweis?,
                stelle: TimeInterval? = nil) {
        guard !lieder.isEmpty else { return }
        if sonosFuehrt {
            // Die Schlange bleibt hier; der Lautsprecher spielt ihr erstes Lied.
            ruhend = nil
            schlange.setzen(lieder, ab: start, mischen: mischen)
            self.herkunft = herkunft
            var ab = stelle ?? 0
            if let erstes = schlange.aktuell, erstes.lied.istHoerbuch, let f = erstes.lied.fortsetzen, stelle == nil { ab = f }
            sonosNeu(stelle: ab, spielen: true)
            return
        }
        if fern != nil {
            // Läuft es drüben, geht auch die neue Schlange dorthin — wie bei
            // Spotify. Gemischt wird hier, damit das gewählte Lied vorn steht.
            var neu = Warteschlange()
            neu.setzen(lieder, ab: start, mischen: mischen)
            self.herkunft = herkunft
            fernSenden(.spielen(ids: neu.eintraege.map(\.lied.id), ab: neu.position ?? 0, stelle: stelle ?? 0))
            return
        }
        endeMelden(bisZumEnde: false)
        ruhend = nil
        schlange.setzen(lieder, ab: start, mischen: mischen)
        jetzt.modiSetzen(gemischt: schlange.gemischt, wiederholung: schlange.wiederholung)
        self.herkunft = herkunft
        fehlschlaege = 0
        gescheitert = []
        fehler = nil
        if let erstes = schlange.aktuell, let stelle = erstes.lied.fortsetzen, erstes.lied.istHoerbuch {
            startstellen[erstes.id] = stelle
        }
        if let erstes = schlange.aktuell, let stelle, stelle > 1 { startstellen[erstes.id] = stelle }
        spielt = true
        sitzungAktivieren()
        allesNeuLaden()
        player.play()
        geaendert?()
    }

    func abspielen() {
        if fern != nil { fernSenden(.weiter); return }
        guard schlange.aktuell != nil else { return }
        sitzungAktivieren()
        // Nach einem Stopp von außen ist dem Server das Lied zu Ende gemeldet;
        // spielt es weiter, beginnt es für ihn neu.
        if meldestand == nil, let id = angezeigterEintrag, let lied = schlange.aktuell?.lied, let w = wege[id] {
            meldestand = Meldestand(eintrag: id, lied: lied, weg: w)
        }
        // Auch ein gescheitertes Item wird ersetzt — sonst drückt man auf
        // Abspielen, und nichts geschieht.
        if player.currentItem == nil || player.currentItem?.status == .failed {
            fehlschlaege = 0
            allesNeuLaden()
        }
        spielt = true
        player.play()
        fortschrittMelden()
        jetztLaeuftZeit()
    }

    func pausieren() {
        if fern != nil { fernSenden(.pause); return }
        spielt = false
        player.pause()
        wartenMelden(false)
        // **Die Anzeige steht sofort**, nicht erst, wenn der Player den
        // neuen Zustand meldet.
        uhr.anhalten(jetzt: CACurrentMediaTime())
        if uhrLaeuft { uhrLaeuft = false }
        fortschrittMelden()
        jetztLaeuftZeit()
        geaendert?()
    }

    func umschalten() {
        if fern != nil {
            // Pause oder Weiter entscheidet der Stand drüben
            // (`Fernstand.aufloesen`) — nicht, was hier gerade angezeigt war.
            fernSenden(.umschalten)
            return
        }
        spielt ? pausieren() : abspielen()
    }

    /// **Ein Stopp von außen** (`Playstate: Stop`): anhalten und dem Server
    /// das Ende melden, damit die Sitzung nicht mehr als laufend dasteht —
    /// das Gerät, das übernommen hat, zeigt uns sonst weiter als „läuft".
    /// Die Schlange bleibt; Abspielen macht dort weiter.
    func stoppen() {
        guard fern == nil else { return }
        spielt = false
        player.pause()
        endeMelden(bisZumEnde: false)
        jetztLaeuftZeit()
        geaendert?()
    }

    /// Zum nächsten Lied. Liegt es vorgeladen, ist es sofort da.
    func weiter() {
        if sonosFuehrt {
            guard schlange.weiter() != nil else { return }
            sonosNeu(stelle: 0)
            return
        }
        if fern != nil { fernSenden(.naechstes); return }
        // Erst den Stand am Player ablesen: hat er gerade von selbst
        // weitergeschaltet, ist die Schlange sonst eins hinterher.
        aktuellesAbgleichen()
        guard schlange.naechster != nil else { return }
        naechstenAbgleichen()
        if player.items().count >= 2 {
            eigenerWechsel = true
            player.advanceToNextItem()
            aktuellesAbgleichen()
        } else {
            // Das nächste ließ sich nicht vorladen — dann eben neu, mit
            // Fehlermeldung, statt einen leeren Player stehen zu lassen.
            endeMelden(bisZumEnde: false)
            schlange.weiter()
            allesNeuLaden()
        }
        if spielt { player.play() }
    }

    /// Nach drei Sekunden an den Anfang, davor zum vorigen Lied — wie jeder
    /// Spieler es macht.
    func zurueck() {
        if sonosFuehrt {
            guard position <= 3, schlange.zurueck() != nil else {
                springe(auf: 0)
                return
            }
            sonosNeu(stelle: 0)
            return
        }
        if fern != nil { fernSenden(.voriges); return }
        guard position <= 3, schlange.vorheriger != nil else {
            springe(auf: 0)
            return
        }
        endeMelden(bisZumEnde: false)
        schlange.zurueck()
        allesNeuLaden()
        if spielt { player.play() }
    }

    /// Zu einem Eintrag der Schlange („Als Nächstes"-Liste).
    func springe(zuEintrag id: UUID) {
        guard id != schlange.aktuell?.id else { return }
        if sonosFuehrt {
            guard schlange.springe(zu: id) != nil else { return }
            sonosNeu(stelle: 0, spielen: true)
            return
        }
        if fern != nil {
            // Jellyfin kennt keinen Befehl „spring zu Eintrag n" — dieselbe
            // Schlange noch einmal, ab dem gewählten Lied.
            if let ab = schlange.eintraege.firstIndex(where: { $0.id == id }) {
                fernSenden(.spielen(ids: schlange.eintraege.map(\.lied.id), ab: ab, stelle: 0))
            }
            return
        }
        if id == schlange.naechster?.id {
            spielt = true
            weiter()
            player.play()
            return
        }
        endeMelden(bisZumEnde: false)
        schlange.springe(zu: id)
        spielt = true
        sitzungAktivieren()
        allesNeuLaden()
        player.play()
    }

    /// An eine Stelle im laufenden Lied.
    /// `danach` läuft, wenn der Player an der Stelle steht (`true`) oder der
    /// Sprung abgebrochen wurde (`false`) — nicht bei einem Gerät drüben.
    func springe(auf sekunden: TimeInterval, danach: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        if fern != nil {
            let ziel = max(0, min(sekunden, dauer ?? sekunden))
            position = ziel
            uhrStellen(position)
            fernSenden(.springen(ziel))
            return
        }
        guard player.currentItem != nil else { return }
        let ziel = max(0, min(sekunden, (dauer ?? sekunden) - 0.25))
        sprungnummer += 1
        let nummer = sprungnummer
        sprungziel = ziel
        position = ziel
        uhrStellen(position)
        hoerzeit.gesprungen(auf: ziel)
        if !genauSpringen(auf: ziel, nummer: nummer, danach: danach) {
            stellen(auf: ziel, nummer: nummer, danach: danach)
        }
        jetztLaeuftZeit()
    }

    /// Der Sprung im laufenden Item selbst.
    private func stellen(auf ziel: TimeInterval, nummer: Int, danach: (@MainActor @Sendable (Bool) -> Void)?) {
        // Ein gestreamtes FLAC-Item landet daneben (``Abspielregel/genauerZugriff(_:startMitten:)``);
        // die genaue Fassung holt den Ton später an die angezeigte Stelle.
        if ziel > 0.5, let item = player.currentItem, !praezise.contains(ObjectIdentifier(item)),
           let id = kennungen[ObjectIdentifier(item)], let w = wege[id], Genaufassung.betrifft(w) {
            verrutscht.insert(ObjectIdentifier(item))
        }
        player.seek(to: CMTime(seconds: ziel, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] fertig in
            Task { @MainActor in
                danach?(fertig)
                // Ein späterer Sprung hat übernommen — der räumt auf.
                guard let self, self.sprungnummer == nummer else { return }
                self.sprungziel = nil
                guard fertig else { return }
                self.fortschrittMelden()
                self.jetztLaeuftZeit()
                self.einwechselnPruefen()
            }
        }
    }

    // MARK: - Schlange ändern

    func alsNaechstes(_ lieder: [Lied]) {
        guard !lieder.isEmpty else { return }
        if fern != nil, !sonosFuehrt { fernSenden(.alsNaechstes(lieder.map(\.id))); return }
        let warLeer = schlange.istLeer
        schlange.alsNaechstes(lieder)
        if warLeer, sonosFuehrt {
            sonosNeu(stelle: 0, spielen: true)
        } else if warLeer {
            spielt = true
            sitzungAktivieren()
            allesNeuLaden()
            player.play()
        } else {
            naechstenAbgleichen()
        }
        geaendert?()
    }

    func hintenAn(_ lieder: [Lied]) {
        guard !lieder.isEmpty else { return }
        if fern != nil, !sonosFuehrt { fernSenden(.hintenAn(lieder.map(\.id))); return }
        let warLeer = schlange.istLeer
        schlange.hintenAn(lieder)
        if warLeer, sonosFuehrt {
            sonosNeu(stelle: 0, spielen: true)
        } else if warLeer {
            spielt = true
            sitzungAktivieren()
            allesNeuLaden()
            player.play()
        } else {
            naechstenAbgleichen()
        }
        geaendert?()
    }

    func entfernen(_ id: UUID) {
        guard fernUmstellbar() else { return }
        schlange.entfernen(id)
        naechstenAbgleichen()
        geaendert?()
    }

    func verschieben(_ id: UUID, nach ziel: Int) {
        guard fernUmstellbar() else { return }
        schlange.verschieben(id, nach: ziel)
        naechstenAbgleichen()
        geaendert?()
    }

    func kommendeLeeren() {
        guard fernUmstellbar() else { return }
        schlange.kommendeLeeren()
        naechstenAbgleichen()
        geaendert?()
    }

    func mischen(_ an: Bool) {
        if fern != nil, !sonosFuehrt { fernSenden(.mischen(an)); return }
        schlange.mischen(an)
        naechstenAbgleichen()
        jetzt.modiSetzen(gemischt: schlange.gemischt, wiederholung: schlange.wiederholung)
        lautstaerkeSetzen()
        geaendert?()
    }

    /// Aus → alles → ein Lied → aus (``Warteschlange/Wiederholung``).
    func wiederholungWeiterschalten() {
        wiederholen(schlange.wiederholung.naechste)
    }

    func wiederholen(_ neu: Warteschlange.Wiederholung) {
        if fern != nil, !sonosFuehrt { fernSenden(.wiederholung(neu)); return }
        schlange.wiederholen(neu)
        naechstenAbgleichen()
        jetzt.modiSetzen(gemischt: schlange.gemischt, wiederholung: schlange.wiederholung)
        geaendert?()
    }

    // MARK: - Über den Neustart

    /// Was abgelegt wird: die Schlange, die Stelle, die Herkunft — nach dem
    /// Wegwischen der Pille die, die dabei stand.
    ///
    /// **Nie die Spiegelung.** Läuft es auf einem anderen Gerät, steht hier
    /// dessen Schlange — Fernlieder, die dieses iPhone so nicht abspielen
    /// kann. Als eigene abgelegt, kamen sie beim nächsten Start als Schlange
    /// zurück (`Schlangenstand.taugt` sieht den Unterschied nicht).
    func schlangenstand() -> Schlangenstand? {
        if !schlangeIstEigen { return nil }
        if schlange.istLeer, let ruhend { return ruhend }
        let stand = Schlangenstand(schlange: schlange, stelle: sprungziel ?? position, herkunft: herkunft)
        return stand.taugt ? stand : nil
    }

    /// **Nach dem Start: dasselbe Lied an derselben Stelle, angehalten.**
    /// Es spielt erst, wenn jemand auf Abspielen tippt.
    func wiederherstellen(_ stand: Schlangenstand) {
        guard stand.taugt, schlange.istLeer else { return }
        ruhend = nil
        schlange = stand.schlange
        herkunft = stand.herkunft
        spielt = false
        if let aktuell = schlange.aktuell, stand.fortsetzen > 0 {
            startstellen[aktuell.id] = stand.fortsetzen
        }
        allesNeuLaden()
        player.pause()
        position = stand.fortsetzen
        uhrStellen(position)
        jetzt.modiSetzen(gemischt: schlange.gemischt, wiederholung: schlange.wiederholung)
        jetztLaeuftSetzen()
    }

    /// **Die Pille ist weggewischt**: anhalten, dem Server das Ende melden,
    /// Anzeige und Sperrbildschirm leeren. Die Schlange mit ihrer Stelle
    /// bleibt als ``schlangenstand()`` stehen, bis eine neue beginnt — so
    /// wird sie weiter abgelegt und steht nach dem nächsten Start bereit.
    /// Zurück kommt sie für „Rückgängig".
    ///
    /// Während Connect bleibt nichts liegen: dann löst sich nur dieses
    /// iPhone, und die gespiegelte Schlange ist keine, die hier taugt.
    func wegraeumen() -> Schlangenstand? {
        let stand = schlangenstand()
        beenden()
        ruhend = stand
        geaendert?()
        return stand
    }

    /// Nach einem umgeschalteten Favoriten: das Lied überall ersetzen.
    func aktualisieren(_ lied: Lied) {
        schlange.aktualisieren(lied)
    }

    /// Alles anhalten und leeren — beim Abmelden.
    func beenden() {
        endeMelden(bisZumEnde: false)
        player.pause()
        player.removeAllItems()
        kennungen = [:]
        tapkennungen = [:]
        genauVergessen()
        wege = [:]
        startstellen = [:]
        gescheitert = []
        itemBeobachtungen = [:]
        genau.behalten([], ladenErlaubt: false)
        schlange = Warteschlange()
        herkunft = nil
        spielt = false
        wartenMelden(false)
        position = 0
        uhrStellen(position)
        dauer = nil
        weg = nil
        glut = nil
        angezeigterEintrag = nil
        fern = nil
        fernLied = nil
        fernLautstaerke = 1
        stumm = false
        meldetakt?.cancel()
        jetzt.leeren()
        pegelAbgleichen()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Items

    /// Die Schlange vom laufenden Eintrag an neu in den Player legen.
    ///
    /// Lässt sich schon das laufende Lied nicht anlegen (keine Quelle, keine
    /// Adresse), bleibt der Player stehen und sagt es — ohne von hier aus
    /// weiterzuspringen, sonst liefe eine Schlange voller solcher Lieder in
    /// einer einzigen Kette durch.
    private func allesNeuLaden() {
        endverhaltenSetzen()
        player.removeAllItems()
        kennungen = [:]
        tapkennungen = [:]
        genauVergessen()
        itemBeobachtungen = [:]
        guard let eintrag = schlange.aktuell else {
            aktuellesAbgleichen()
            return
        }
        guard let item = macheItem(eintrag) else {
            // **Ohne Netz: zum nächsten geladenen Lied**, statt stehen zu
            // bleiben — einmal, und nie im Kreis.
            if verbindung == .keine, let ablage,
               schlange.weiterZuSpielbarem({ ablage.istGeladen($0) }) != nil {
                allesNeuLaden()
                return
            }
            fehler = verbindung == .keine
                ? String(localized: "Ohne Netz läuft nur, was geladen ist.")
                : String(localized: "Dieses Lied lässt sich nicht abspielen.")
            endeMelden(bisZumEnde: false)
            spielt = false
            wartenMelden(false)
            angezeigterEintrag = nil
            player.pause()
            jetztLaeuftSetzen()
            return
        }
        player.insert(item, after: nil)
        if let naechster = schlange.naechster, !gescheitert.contains(naechster.id),
           let zweites = macheItem(naechster) {
            player.insert(zweites, after: item)
        }
        eigenerWechsel = true
        aktuellesAbgleichen()
        genauAbgleichen()
    }

    /// **Der zweite Platz im Player muss der nächste der Schlange sein.**
    ///
    /// Ein Eintrag, dessen Vorladen gescheitert ist, wird hier nicht noch
    /// einmal angelegt — sonst scheiterte er sofort wieder, und der Player
    /// fragte den Server in einer Schleife. Er bekommt seinen neuen Versuch,
    /// wenn er dran ist.
    private func naechstenAbgleichen() {
        // Bei Sonos liegt nichts im Player: der Lautsprecher bekommt das
        // nächste Lied (``sonosSchlangeGeaendert``).
        if sonosFuehrt {
            sonosSchlangeGeaendert?()
            return
        }
        endverhaltenSetzen()
        aushandeln()
        aktuellesAbgleichen()
        let liegend = player.items()
        guard let erstes = liegend.first else { return }
        let gewollt = schlange.naechster
        defer { genauAbgleichen() }
        if let zweites = liegend.dropFirst().first,
           let id = kennungen[ObjectIdentifier(zweites)], id == gewollt?.id {
            for rest in liegend.dropFirst(2) { raus(rest) }
            return
        }
        for rest in liegend.dropFirst() { raus(rest) }
        if let gewollt, !gescheitert.contains(gewollt.id), let neu = macheItem(gewollt) {
            player.insert(neu, after: erstes)
        }
    }

    /// **Vorab mit dem Server aushandeln**, was er für die nächsten Lieder
    /// zulässt (``Musikquelle/vorbereiten(_:hoechstens:)``) — drei voraus,
    /// damit die Antwort da ist, bevor ein Lied vorgeladen wird. Was schon
    /// ausgehandelt ist, fragt die Quelle nicht noch einmal.
    private func aushandeln() {
        guard let quelle, verbindung != .keine else { return }
        let eintraege = [schlange.aktuell].compactMap { $0 } + Array(schlange.kommende.prefix(3))
        let lieder = eintraege.map(\.lied).filter { ablage?.istGeladen($0) != true }
        guard !lieder.isEmpty else { return }
        let grenze = einstellungen?.hoechstens(bei: verbindung)
        Task.detached(priority: .utility) { await quelle.vorbereiten(lieder, hoechstens: grenze) }
    }

    /// **Ein Lied, das sich wiederholt, darf nicht weiterschalten.** Der
    /// Player bleibt dann am Ende stehen, und ``liedZuEnde(_:)`` springt an
    /// den Anfang — das nächste bleibt vorgeladen für „Weiter" von Hand.
    private func endverhaltenSetzen() {
        let gewollt: AVPlayer.ActionAtItemEnd = schlange.wiederholtLaufendes ? .none : .advance
        if player.actionAtItemEnd != gewollt { player.actionAtItemEnd = gewollt }
    }

    private func raus(_ item: AVPlayerItem) {
        player.remove(item)
        vergessen(item)
    }

    /// Ein Item, das nicht mehr im Player liegt, aus allen Tafeln.
    private func vergessen(_ item: AVPlayerItem) {
        let k = ObjectIdentifier(item)
        kennungen[k] = nil
        itemBeobachtungen[k] = nil
        tapkennungen[k] = nil
        praezise.remove(k)
        verrutscht.remove(k)
    }

    /// Ein Item für einen Eintrag: die geladene Datei, wenn es sie gibt,
    /// sonst die Abspieladresse der Quelle (`VERHALTEN.md` H8 — ohne den
    /// Server zu fragen).
    private func macheItem(_ eintrag: Warteschlange.Eintrag) -> AVPlayerItem? {
        let lied = eintrag.lied
        let neuerWeg: Abspielweg
        if let datei = ablage?.lokalerWeg(fuer: lied) {
            neuerWeg = datei
        } else if verbindung == .keine {
            // Ohne Netz gar nicht erst versuchen — der Abruf scheiterte
            // erst nach einer Weile, und so lange stünde alles.
            return nil
        } else if let w = quelle?.abspielweg(lied, sitzung: UUID().uuidString,
                                             hoechstens: einstellungen?.hoechstens(bei: verbindung)) {
            neuerWeg = w
        } else {
            return nil
        }
        return itemAnlegen(eintrag, weg: neuerWeg)
    }

    /// Das Item zu einem Abspielweg. Liegt die genaue Fassung einer
    /// gestreamten FLAC-Datei schon da (``Genaulager``), kommt das Item aus
    /// ihr; `wege` behält den Stream — für Plakette und Meldungen an den
    /// Server bleibt es dasselbe Lied auf demselben Weg.
    private func itemAnlegen(_ eintrag: Warteschlange.Eintrag, weg neuerWeg: Abspielweg) -> AVPlayerItem {
        let genauDatei = Genaufassung.betrifft(neuerWeg) ? genau.datei(fuer: eintrag.lied.id) : nil
        var optionen: [String: Any] = [:]
        if genauDatei == nil, let mime = neuerWeg.mime, !neuerWeg.adresse.isFileURL {
            optionen[AVURLAssetOverrideMIMETypeKey] = mime
        }
        // **FLAC springt sonst an die falsche Stelle** (25.09.: von
        // Sonos zurück bei 58 s, zu hören war etwa 25 s, `currentTime` sagte
        // 58). AVFoundation schätzt in FLAC die Byte-Stelle über die Bitrate
        // und meldet trotzdem das Ziel — gemessen und begründet an
        // ``Abspielregel/genauerZugriff(_:startMitten:)``.
        let genauerZugriff = genauDatei != nil
            || Abspielregel.genauerZugriff(neuerWeg, startMitten: startstellen[eintrag.id] != nil)
        if genauerZugriff {
            optionen[AVURLAssetPreferPreciseDurationAndTimingKey] = true
        }
        let asset = AVURLAsset(url: genauDatei ?? neuerWeg.adresse, options: optionen)
        let item = AVPlayerItem(asset: asset)
        let kennung = ObjectIdentifier(item)
        kennungen[kennung] = eintrag.id
        wege[eintrag.id] = neuerWeg
        if genauerZugriff { praezise.insert(kennung) }
        itemBeobachtungen[kennung] = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard let self, let item else { return }
                self.itemZustand(item, status: status)
            }
        return item
    }

    private func itemZustand(_ item: AVPlayerItem, status: AVPlayerItem.Status) {
        guard let id = kennungen[ObjectIdentifier(item)] else { return }
        switch status {
        case .readyToPlay:
            tapAnlegen(item, eintrag: id)
            let losDanach = losNachSprung == id
            if losDanach { losNachSprung = nil }
            if let stelle = startstellen.removeValue(forKey: id), item === player.currentItem {
                // **Erst wenn der Sprung sitzt, spielen** (``fernBeenden``): ein
                // `play()` direkt hinter dem Sprung ließ die Anzeige an der
                // richtigen Stelle, den Ton aber woanders (Test 25.09.).
                springe(auf: stelle) { [weak self] _ in
                    guard let self, let jetzt = self.player.currentItem,
                          self.kennungen[ObjectIdentifier(jetzt)] == id else { return }
                    if losDanach, self.spielt { self.player.play() }
                }
            } else if losDanach, spielt, item === player.currentItem {
                player.play()
            }
            if item === player.currentItem, dauer == nil {
                let d = item.duration.seconds
                if d.isFinite, d > 0 { dauer = d }
            }
            if item === player.currentItem {
                beginnMelden()
                einwechselnPruefen()
            }
        case .failed:
            itemGescheitert(item, grund: item.error)
        default:
            break
        }
    }

    // MARK: - Wechsel

    /// **Welches Lied läuft — am Player abgelesen.**
    private func aktuellesAbgleichen() {
        guard let item = player.currentItem, let id = kennungen[ObjectIdentifier(item)] else {
            if player.currentItem == nil, schlange.aktuell != nil, angezeigterEintrag != nil, !eigenerWechsel {
                // Der Player ist leer gelaufen. Steht in der Schlange noch
                // etwas (sein Vorladen war gescheitert), geht es damit weiter;
                // sonst ist die Schlange zu Ende.
                if schlange.naechster != nil {
                    endeMelden(bisZumEnde: true)
                    schlange.weiter()
                    allesNeuLaden()
                    if spielt { player.play() }
                } else {
                    schlangeZuEnde()
                }
            }
            eigenerWechsel = false
            return
        }
        if angezeigterEintrag != id {
            // Ein Tausch im vorigen Lied gilt nicht mehr.
            if let w = wechsel, item !== w.alt, item !== w.neu { wechselAbbrechen() }
            // Ein Sprung im vorigen Lied gilt nicht mehr.
            sprungziel = nil
            sprungnummer += 1
            // Das vorige Lied endet — bis zum Ende, wenn nicht wir gesprungen sind.
            endeMelden(bisZumEnde: !eigenerWechsel)
            if schlange.aktuell?.id != id { schlange.springe(zu: id) }
            angezeigterEintrag = id
            gescheitert.remove(id)
            let lied = schlange.aktuell?.lied
            weg = wege[id]
            dauer = lied?.dauer ?? {
                let d = item.duration.seconds
                return d.isFinite && d > 0 ? d : nil
            }()
            position = max(0, item.currentTime().seconds.isFinite ? item.currentTime().seconds : 0)
            uhrStellen(position)
            hoerzeit = Hoerzeit()
            hoerzeit.gesprungen(auf: position)
            if let lied, let weg { meldestand = Meldestand(eintrag: id, lied: lied, weg: weg) }
            // Was aus dem Player gefallen ist, vergessen.
            let liegend = Set(player.items().map(ObjectIdentifier.init))
            for k in kennungen.keys where !liegend.contains(k) {
                kennungen[k] = nil
                itemBeobachtungen[k] = nil
                tapkennungen[k] = nil
                praezise.remove(k)
                verrutscht.remove(k)
            }
            wege = wege.filter { eintrag in kennungen.values.contains(eintrag.key) }
            lautstaerkeSetzen()
            naechstenAbgleichen()
            jetztLaeuftSetzen()
            geaendert?()
            glutLaden()
            if player.timeControlStatus == .playing { beginnMelden() }
        }
        eigenerWechsel = false
    }

    /// Das letzte Lied ist durch: stehen bleiben, das Lied von vorn bereit.
    private func schlangeZuEnde() {
        endeMelden(bisZumEnde: true)
        spielt = false
        wartenMelden(false)
        angezeigterEintrag = nil
        position = 0
        uhrStellen(position)
        // Leer machen, bevor das Lied wieder hineinkommt — sonst stünde es
        // hinter einem durchgelaufenen Rest, spielte bei 0 s los und zählte doppelt.
        player.removeAllItems()
        kennungen = [:]
        tapkennungen = [:]
        genauVergessen()
        itemBeobachtungen = [:]
        guard let eintrag = schlange.aktuell, let item = macheItem(eintrag) else { return }
        player.insert(item, after: nil)
        player.pause()
        eigenerWechsel = true
        aktuellesAbgleichen()
    }

    private func liedZuEnde(_ objekt: AnyObject?) {
        guard let item = objekt as? AVPlayerItem, item === player.currentItem else { return }
        fehlschlaege = 0
        guard schlange.wiederholtLaufendes, let id = kennungen[ObjectIdentifier(item)] else { return }
        // **Dasselbe Lied noch einmal**: dem Server ist es zu Ende gehört
        // und beginnt neu — mit eigenem Beginn und eigenem Scrobble.
        endeMelden(bisZumEnde: true)
        if let lied = schlange.aktuell?.lied, let weg = wege[id] {
            meldestand = Meldestand(eintrag: id, lied: lied, weg: weg)
        }
        hoerzeit = Hoerzeit()
        springe(auf: 0)
        if spielt { player.play() }
        beginnMelden()
    }

    private func itemGescheitert(_ objekt: AnyObject?, grund: Error?) {
        guard let item = objekt as? AVPlayerItem, let id = kennungen[ObjectIdentifier(item)] else { return }
        // Ein vorgeladenes Lied, das scheitert, stört erst, wenn es dran ist:
        // heraus damit, und kein neuer Versuch, bevor es an der Reihe ist.
        guard item === player.currentItem else {
            gescheitert.insert(id)
            raus(item)
            return
        }
        fehlschlaege += 1
        fehler = String(localized: "Ein Lied ließ sich nicht abspielen.")
        if fehlschlaege < 3, schlange.naechster != nil {
            endeMelden(bisZumEnde: false)
            schlange.weiter()
            allesNeuLaden()
            if spielt { player.play() }
        } else {
            pausieren()
        }
    }

    // MARK: - Genaue Fassung (``Genaufassung``)

    /// Beim Leeren des Players: kein Tausch, kein wartender Sprung mehr.
    private func genauVergessen() {
        wechselAbbrechen()
        praezise = []
        verrutscht = []
    }

    private func wechselAbbrechen() {
        wartenderSprung = nil
        guard let w = wechsel else { return }
        wechsel = nil
        w.abbrechen()
        vergessen(player.currentItem === w.neu ? w.alt : w.neu)
    }

    /// **Die genaue Fassung laden, wo sie fehlt** — für das laufende und das
    /// nächste Lied, nur im WLAN. Was keins von beiden mehr braucht, fällt;
    /// im Mobilfunk bricht das Laden ab, was schon da ist, bleibt.
    private func genauAbgleichen() {
        guard fern == nil else {
            genau.behalten([], ladenErlaubt: false)
            return
        }
        let liegend = player.items()
        var behalten = Set<String>()
        for eintrag in [schlange.aktuell, schlange.naechster].compactMap({ $0 }) {
            guard let item = liegend.first(where: { kennungen[ObjectIdentifier($0)] == eintrag.id }),
                  let weg = wege[eintrag.id], Genaufassung.betrifft(weg) else { continue }
            behalten.insert(eintrag.lied.id)
            if Genaufassung.nachladen(weg, schonGenau: praezise.contains(ObjectIdentifier(item)),
                                      verbindung: verbindung, sparsam: sparsam) {
                genau.laden(eintrag.lied.id, adresse: weg.adresse)
            }
        }
        genau.behalten(behalten, ladenErlaubt: Genaufassung.darfLaden(verbindung, sparsam: sparsam))
        einwechselnPruefen()
    }

    /// Eine Datei ist fertig: ein wartender Sprung landet jetzt genau,
    /// sonst wird getauscht, wo es passt.
    private func genauDa(_ lied: String) {
        if let w = wartenderSprung, w.lied == lied {
            wartenderSprung = nil
            wartenMelden(false)
            if w.nummer == sprungnummer, let item = player.currentItem, let eintrag = schlange.aktuell,
               eintrag.lied.id == lied, kennungen[ObjectIdentifier(item)] == eintrag.id, let weg = wege[eintrag.id] {
                sprungTausch(eintrag, weg: weg, alt: item, ziel: w.ziel, nummer: w.nummer)
                return
            }
        }
        einwechselnPruefen()
    }

    /// **Wo die genaue Fassung da ist, einwechseln.** Das nächste Lied wird
    /// in der Schlange ersetzt, bevor es dran ist — sein Übergang bleibt
    /// lückenlos. Das laufende nach ``Genaufassung/einwechseln(stelle:dauer:springt:bereit:laeuft:verrutscht:)``.
    private func einwechselnPruefen() {
        guard fern == nil, wechsel == nil, wartenderSprung == nil else { return }
        let liegend = player.items()
        guard let erstes = liegend.first else { return }
        let jetzt = player.currentTime().seconds
        let stelle = jetzt.isFinite ? jetzt : position
        let endeNah = Genaufassung.einwechseln(stelle: stelle, dauer: dauer, springt: false, bereit: true,
                                               laeuft: false, verrutscht: false) == .nicht
        if !endeNah, liegend.count >= 2, let naechster = schlange.naechster,
           kennungen[ObjectIdentifier(liegend[1])] == naechster.id,
           !praezise.contains(ObjectIdentifier(liegend[1])),
           let weg = wege[naechster.id], Genaufassung.betrifft(weg), genau.datei(fuer: naechster.lied.id) != nil {
            raus(liegend[1])
            player.insert(itemAnlegen(naechster, weg: weg), after: erstes)
        }
        guard let eintrag = schlange.aktuell, kennungen[ObjectIdentifier(erstes)] == eintrag.id,
              !praezise.contains(ObjectIdentifier(erstes)),
              let weg = wege[eintrag.id], Genaufassung.betrifft(weg),
              genau.datei(fuer: eintrag.lied.id) != nil else { return }
        let entscheid = Genaufassung.einwechseln(
            stelle: stelle, dauer: dauer, springt: sprungziel != nil, bereit: erstes.status == .readyToPlay,
            laeuft: player.timeControlStatus == .playing, verrutscht: verrutscht.contains(ObjectIdentifier(erstes)))
        guard entscheid == .jetzt else { return }
        wechselStarten(eintrag, weg: weg, alt: erstes, art: .mitlaufen)
    }

    /// **Ein Sprung in einem gestreamten FLAC-Item.** Ist die genaue Fassung
    /// da, wird mit dem Sprung getauscht — er landet genau und dauert kaum
    /// länger. Ist sie gleich da, wartet er darauf. Sonst `false`: dann
    /// springt es im Stream, ungenau wie bisher.
    private func genauSpringen(auf ziel: TimeInterval, nummer: Int,
                               danach: (@MainActor @Sendable (Bool) -> Void)?) -> Bool {
        guard let item = player.currentItem, !praezise.contains(ObjectIdentifier(item)),
              let eintrag = schlange.aktuell, kennungen[ObjectIdentifier(item)] == eintrag.id,
              let weg = wege[eintrag.id], Genaufassung.betrifft(weg) else { return false }
        wechselAbbrechen()
        if genau.datei(fuer: eintrag.lied.id) != nil {
            sprungTausch(eintrag, weg: weg, alt: item, ziel: ziel, nummer: nummer, danach: danach)
            return true
        }
        guard Genaufassung.sprungAbwarten(restzeit: genau.restzeit(fuer: eintrag.lied.id)) else { return false }
        wartenderSprung = (nummer, ziel, eintrag.lied.id)
        wartenMelden(spielt)
        Task { [weak self] in
            // Kommt die Datei doch nicht rechtzeitig: springen wie bisher.
            try? await Task.sleep(for: .seconds(Genaufassung.sprungwartezeit + 0.5))
            guard let self, let w = self.wartenderSprung, w.nummer == nummer else { return }
            self.wartenderSprung = nil
            self.wartenMelden(false)
            self.stellen(auf: ziel, nummer: nummer, danach: danach)
        }
        return true
    }

    private func sprungTausch(_ eintrag: Warteschlange.Eintrag, weg: Abspielweg, alt: AVPlayerItem,
                              ziel: TimeInterval, nummer: Int,
                              danach: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        wechselStarten(eintrag, weg: weg, alt: alt, art: .sprung(ziel)) { [weak self] ausgang in
            guard let self else { return }
            guard ausgang == .getauscht else {
                // Die Datei taugt nicht: im Stream springen, wie bisher.
                if self.sprungnummer == nummer, self.player.currentItem === alt {
                    self.stellen(auf: ziel, nummer: nummer, danach: danach)
                }
                return
            }
            danach?(true)
            guard self.sprungnummer == nummer else { return }
            self.sprungziel = nil
            self.fortschrittMelden()
            self.jetztLaeuftZeit()
        }
    }

    private func wechselStarten(_ eintrag: Warteschlange.Eintrag, weg: Abspielweg, alt: AVPlayerItem,
                                art: Genauwechsel.Art, danach: ((Genauwechsel.Ausgang) -> Void)? = nil) {
        let neu = itemAnlegen(eintrag, weg: weg)
        let w = Genauwechsel(player: player, alt: alt, neu: neu, art: art)
        wechsel = w
        w.fertig = { [weak self, weak w] ausgang in
            guard let self, let w, self.wechsel === w else { return }
            self.wechsel = nil
            self.vergessen(ausgang == .getauscht ? alt : neu)
            Protokoll.schreib("[Genau] \(eintrag.lied.id): \(ausgang == .getauscht ? "eingewechselt" : "abgebrochen")"
                              + (art == .mitlaufen ? "" : " mit Sprung"))
            danach?(ausgang)
            self.jetztLaeuftZeit()
            self.pegelAbgleichen()
        }
        w.starten()
    }

    // MARK: - Lauf und Zeit

    private func laufzustandGewechselt() {
        defer {
            let s = player.currentTime().seconds
            if sprungziel == nil { uhrStellen(s.isFinite ? s : position) }
        }
        switch player.timeControlStatus {
        case .playing:
            wartenMelden(false)
            fehlschlaege = 0
            beginnMelden()
        case .waitingToPlayAtSpecifiedRate:
            wartenMelden(spielt)
        case .paused:
            wartenMelden(false)
        @unknown default:
            wartenMelden(false)
        }
        jetztLaeuftZeit()
        pegelAbgleichen()
        // Angehalten oder wartend: jetzt tauscht es sich ungehört.
        einwechselnPruefen()
    }

    /// **Warten zeigt sich erst nach der Schwelle** (``Ladeanzeige``). Hört
    /// das Warten vorher auf, hat niemand etwas gesehen; sonst schaltet eine
    /// Nachfrage zur fälligen Zeit die Anzeige ein.
    private func wartenMelden(_ wartet: Bool) {
        let jetzt = CACurrentMediaTime()
        ladeanzeige.melden(wartet: wartet, jetzt: jetzt)
        ladepruefung?.cancel()
        ladepruefung = nil
        if let faellig = ladeanzeige.faellig, faellig > jetzt {
            ladepruefung = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(faellig - jetzt))
                guard let self, !Task.isCancelled else { return }
                let an = ladeanzeige.sichtbar(jetzt: CACurrentMediaTime())
                if puffert != an {
                    puffert = an
                    jetztLaeuftZeit()
                }
            }
        }
        let an = ladeanzeige.sichtbar(jetzt: jetzt)
        if puffert != an { puffert = an }
    }

    private func takt(_ zeit: CMTime) {
        guard player.currentItem != nil, sprungziel == nil else { return }
        let s = zeit.seconds
        guard s.isFinite else { return }
        position = s
        uhrStellen(position)
        if dauer == nil, let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
            dauer = d
            jetztLaeuftZeit()
        }
        hoerzeit.messen(s, laeuft: player.timeControlStatus == .playing)
        gehoertPruefen()
        pegelAbgleichen()
    }

    // MARK: - Pegel

    /// Ob der Ton gerade über AirPlay geht — dann bleibt der Pegel beim Muster.
    @ObservationIgnored private var ausgabeAirPlay = false

    /// **Den Tap anlegen, sobald das Item bereit ist** — dann gibt es seine
    /// Tonspur ohne Warten (`AVPlayerItem.tracks`). Nur für Lieder, die als
    /// Datei kommen: eine umgewandelte Folge (HLS) hat keine Tonspur, an der
    /// ein Tap hängen könnte, und dort bleibt es beim Muster.
    private func tapAnlegen(_ item: AVPlayerItem, eintrag: UUID) {
        guard item.audioMix == nil, let weg = wege[eintrag], weg.art == .direkt,
              weg.adresse.pathExtension.lowercased() != "m3u8",
              let spur = item.tracks.lazy.compactMap(\.assetTrack).first(where: { $0.mediaType == .audio }),
              let tap = Pegeltap.machen(kennung: naechsteTapkennung) else { return }
        tapkennungen[ObjectIdentifier(item)] = naechsteTapkennung
        naechsteTapkennung &+= 1
        if naechsteTapkennung == 0 { naechsteTapkennung = 1 }
        let parameter = AVMutableAudioMixInputParameters(track: spur)
        parameter.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameter]
        item.audioMix = mix
        pegelAbgleichen()
    }

    /// Echte Bänder nur, wenn hier gespielt wird, das Lied einen Tap hat und
    /// der Ton nicht über AirPlay geht. Sonst das Muster.
    ///
    /// **Nur der Tap des laufenden Items schreibt.** Vorgeladene Items tragen
    /// ihren Tap schon und rechnen mit — ohne diese Zuordnung schlug der
    /// Pegel kurz zum nächsten Lied aus. Die Kennung wird hier gesetzt und
    /// im Tonfaden nur atomar gelesen (``Pegelleitung/aktiv``).
    private func pegelAbgleichen() {
        let kennung = player.currentItem.flatMap { tapkennungen[ObjectIdentifier($0)] } ?? 0
        if Pegelleitung.aktiv.load(ordering: .relaxed) != kennung {
            Pegelleitung.aktiv.store(kennung, ordering: .relaxed)
        }
        let echt = fern == nil && spielt && !ausgabeAirPlay && player.currentItem?.audioMix != nil
        let quelle = Pegelquelle.geteilt
        if quelle.echt != echt { quelle.echt = echt }
    }

    // MARK: - Meldungen an den Server (`VERHALTEN.md` C1–C4)

    /// C1: erst, wenn das Lied wirklich läuft.
    private func beginnMelden() {
        guard var m = meldestand, m.beginn == nil,
              player.timeControlStatus == .playing,
              player.currentItem?.status == .readyToPlay,
              let item = player.currentItem, kennungen[ObjectIdentifier(item)] == m.eintrag
        else { return }
        m.beginn = Date()
        meldestand = m
        senden(.beginn(stand(m, position: position)))
        meldetakt?.cancel()
        meldetakt = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.fortschrittMelden()
            }
        }
    }

    /// C2: alle zehn Sekunden und bei jeder Zustandsänderung.
    private func fortschrittMelden() {
        guard let m = meldestand, m.beginn != nil else { return }
        senden(.fortschritt(stand(m, position: position)))
    }

    /// C3/C4: genau einmal je Lied, mit der Stelle vor dem Wechsel.
    private func endeMelden(bisZumEnde: Bool) {
        meldetakt?.cancel()
        meldetakt = nil
        guard let m = meldestand else { return }
        meldestand = nil
        guard m.beginn != nil else { return }
        let stelle = bisZumEnde ? (m.lied.dauer ?? dauer ?? position) : position
        senden(.ende(stand(m, position: stelle)))
    }

    /// Die Hälfte oder vier Minuten gehört — einmal je Wiedergabe.
    private func gehoertPruefen() {
        guard var m = meldestand, let beginn = m.beginn, !m.gehoert,
              Scrobbleregel.erreicht(gehoert: hoerzeit.gehoert, dauer: m.lied.dauer ?? dauer)
        else { return }
        m.gehoert = true
        meldestand = m
        let nachtrag = Nachtrag(liedID: m.lied.id, titel: m.lied.titel, zeit: beginn)
        // Ohne Netz gleich merken; sonst senden und bei einem Fehler merken.
        guard verbindung != .keine, let quelle else {
            nachtragen?(nachtrag)
            return
        }
        let lied = m.lied
        Task { [weak self] in
            do {
                try await quelle.scrobbeln(lied, beginn: beginn, nachtraeglich: false)
            } catch {
                self?.nachtragen?(nachtrag)
            }
        }
    }

    private func stand(_ m: Meldestand, position: TimeInterval) -> Wiedergabestand {
        Wiedergabestand(lied: m.lied, position: position, pausiert: !spielt, art: m.weg.art,
                        sitzung: m.weg.sitzung, gemischt: schlange.gemischt,
                        schlange: schlange.eintraege.map(\.lied.id), index: schlange.position,
                        wiederholung: schlange.wiederholung,
                        lautstaerke: Int((fernLautstaerke * 100).rounded()), stumm: stumm)
    }

    /// **Der Reihe nach.** Jede Meldung einzeln abgeschickt, liefe „Stopped"
    /// des einen Liedes womöglich vor „Playing" desselben beim Server ein;
    /// ein einziger Verbraucher hält die Reihenfolge.
    private func senden(_ meldung: Wiedergabemeldung) {
        guard let quelle else { return }
        meldekanal.yield((quelle, meldung))
    }

    @ObservationIgnored private lazy var meldekanal: AsyncStream<(any Musikquelle, Wiedergabemeldung)>.Continuation = {
        let (strom, kanal) = AsyncStream<(any Musikquelle, Wiedergabemeldung)>.makeStream()
        meldeverbraucher = Task.detached(priority: .utility) {
            for await (quelle, meldung) in strom { await quelle.melde(meldung) }
        }
        return kanal
    }()
    @ObservationIgnored private var meldeverbraucher: Task<Void, Never>?

    // MARK: - Unterbrechung und Ausgabe

    /// Ein Anruf, ein Wecker: anhalten. Sagt das System danach „weiter",
    /// und lief es vorher, geht es weiter — so erwartet es jeder.
    private func unterbrechung(_ info: [AnyHashable: Any]?) {
        // Ein Anruf hier hält die Musik auf dem Fernseher nicht an.
        guard fern == nil else { return }
        guard let roh = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let art = AVAudioSession.InterruptionType(rawValue: roh) else { return }
        switch art {
        case .began:
            spielteVorUnterbrechung = spielt
            pausieren()
        case .ended:
            let optionen = AVAudioSession.InterruptionOptions(
                rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            if optionen.contains(.shouldResume), spielteVorUnterbrechung {
                abspielen()
            }
            spielteVorUnterbrechung = false
        @unknown default:
            break
        }
    }

    /// Kopfhörer ab: anhalten, damit die Musik nicht aus dem Lautsprecher
    /// weiterläuft.
    private func ausgabeGewechselt(_ info: [AnyHashable: Any]?) {
        if fern == nil, let roh = info?[AVAudioSessionRouteChangeReasonKey] as? UInt,
           AVAudioSession.RouteChangeReason(rawValue: roh) == .oldDeviceUnavailable {
            pausieren()
        }
        ausgabeAktualisieren()
    }

    func ausgabeAktualisieren() {
        let ausgaenge = AVAudioSession.sharedInstance().currentRoute.outputs
        ausgabeAirPlay = ausgaenge.contains { $0.portType == .airPlay }
        defer { pegelAbgleichen() }
        guard let erster = ausgaenge.first else {
            ausgabename = UIDevice.current.model
            return
        }
        switch erster.portType {
        case .builtInSpeaker, .builtInReceiver:
            ausgabename = UIDevice.current.model
        default:
            ausgabename = erster.portName
        }
    }

    /// Die Mediendienste sind neu gestartet: alle AV-Gegenstände sind
    /// ungültig. Neuer Player, das laufende Lied an derselben Stelle, angehalten.
    private func dienstNeuGestartet() {
        let stelle = position
        if let zeitbeobachter { player.removeTimeObserver(zeitbeobachter) }
        zeitbeobachter = nil
        beobachtungen.removeAll()
        itemBeobachtungen = [:]
        kennungen = [:]
        tapkennungen = [:]
        genauVergessen()
        player = AVQueuePlayer()
        playerEinrichten()
        systemEinrichten()
        spielt = false
        angezeigterEintrag = nil
        if let aktuell = schlange.aktuell { startstellen[aktuell.id] = stelle }
        allesNeuLaden()
        ausgabeAktualisieren()
    }

    // MARK: - Auf einem anderen Gerät (Connect)

    /// **Hier aufhören, drüben zeigen.** Das laufende Lied endet für den
    /// Server (sonst stünde diese Sitzung weiter als „läuft" da, und das
    /// andere Gerät böte an, sie zu übernehmen), der Player wird leer — die
    /// Stelle kommt ab jetzt von drüben.
    ///
    /// Die Tonsitzung wird freigegeben: hier spielt nichts mehr, und eine
    /// andere App soll wieder spielen dürfen.
    func fernBeginnen(_ anzeige: Fernanzeige) {
        guard fern == nil else {
            fern = anzeige
            return
        }
        endeMelden(bisZumEnde: false)
        player.pause()
        player.removeAllItems()
        kennungen = [:]
        tapkennungen = [:]
        genauVergessen()
        itemBeobachtungen = [:]
        wege = [:]
        startstellen = [:]
        gescheitert = []
        genau.behalten([], ladenErlaubt: false)
        angezeigterEintrag = nil
        sprungziel = nil
        sprungnummer += 1
        fern = anzeige
        spielt = false
        wartenMelden(false)
        weg = nil
        fernLied = nil
        pegelAbgleichen()
        // **Bei Sonos bleibt die Tonsitzung an** — wie bei jeder angehaltenen
        // Musik-App. Sonst ist diese App nicht mehr die, die gerade spielt,
        // und Sperrbildschirm und Dynamic Island zeigen nichts, sobald sie im
        // Hintergrund ist (Test 25.09.). Bei Connect spielt drüben ein
        // eigenes Swiftly, das seine eigene Anzeige hat.
        if anzeige.art != .sonos {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Welches Lied die Anzeige zuletzt von drüben bekam — Glut und
    /// Sperrbildschirm folgen nur einem Wechsel.
    @ObservationIgnored private var fernLied: String?

    /// **Den Stand des anderen Geräts zeigen.** `lieder` ist die Schlange
    /// dort, soweit geladen, `index` die Stelle darin; ohne Lieder steht nur
    /// das laufende da.
    func fernSpiegeln(_ stand: Fernstand, lieder: [Lied]?, index: Int?) {
        guard fern?.sitzungID == stand.sitzungID else { return }
        if fern?.name != stand.geraetename { fern?.name = stand.geraetename }
        let folge: [Lied]
        let an: Int?
        if let lieder, !lieder.isEmpty {
            folge = lieder
            an = index
        } else if let lied = stand.lied {
            folge = [lied]
            an = 0
        } else {
            // **Kein Lied drüben heißt nicht: nichts zeigen.** Eine leere
            // Schlange nähme den Mini-Player weg und schlösse das Blatt.
            folge = schlange.eintraege.map(\.lied)
            an = schlange.position
        }
        var neu = schlange
        neu.spiegeln(folge, aktuell: an, gemischt: stand.gemischt, wiederholung: stand.wiederholung)
        if neu != schlange { schlange = neu }
        fernLauf(stand)
    }

    /// **Lauf, Stelle und Dauer von drüben — die Schlange bleibt.** Bei Sonos
    /// führt die Schlange hier; der Lautsprecher sagt nur, ob und wo er spielt.
    func fernLauf(_ stand: Fernstand) {
        guard fern?.sitzungID == stand.sitzungID else { return }
        if fern?.name != stand.geraetename { fern?.name = stand.geraetename }
        let laeuft = !stand.angehalten && stand.lied != nil
        if spielt != laeuft { spielt = laeuft }
        if dauer != stand.dauer { dauer = stand.dauer }
        fernZeit(stand.stelle())
        // Läuft oder steht es drüben anders als eben: die Anzeige mitnehmen.
        if (uhr.rate > 0) != laeuft { uhrStellen(stand.stelle()) }
        if fernLied != aktuell?.id {
            fernLied = aktuell?.id
            jetzt.modiSetzen(gemischt: schlange.gemischt, wiederholung: schlange.wiederholung)
            jetztLaeuftSetzen()
            glutLaden()
        } else {
            jetztLaeuftZeit()
        }
    }

    /// **Sonos ist von selbst ins nächste Lied gegangen** — die Schlange
    /// hier rückt auf diesen Eintrag nach. Bei „ein Lied wiederholen" ist es
    /// derselbe; dann beginnt nur die Stelle von vorn.
    func sonosWeiter(zu eintrag: UUID) {
        guard sonosFuehrt else { return }
        if schlange.aktuell?.id != eintrag { schlange.springe(zu: eintrag) }
        position = 0
        uhrStellen(position)
        dauer = aktuell?.dauer
        fernLied = aktuell?.id
        jetztLaeuftSetzen()
        glutLaden()
        geaendert?()
    }

    /// Die weitergerechnete Stelle von drüben, im Takt der Anzeige.
    func fernZeit(_ stelle: TimeInterval) {
        guard fern != nil, abs(stelle - position) >= 0.05 else { return }
        position = stelle
        uhrStellen(position)
    }

    /// **Zurück auf dieses Gerät.** Mit `spielen` ist das „Hier
    /// weiterhören": dieselbe Schlange ab derselben Stelle. Ohne — das Gerät
    /// ist verschwunden — steht sie angehalten bereit wie nach einem Neustart.
    ///
    /// `lieder` sind frisch vom Server geholt, mit Dateiangaben; die aus der
    /// Sitzung drüben reichen zum Anzeigen, nicht zum Abspielen.
    func fernBeenden(lieder: [Lied]?, ab: Int, stelle: TimeInterval, spielen: Bool) {
        guard fern != nil else { return }
        fern = nil
        fernLied = nil
        if let lieder, !lieder.isEmpty {
            var neu = Warteschlange()
            neu.spiegeln(lieder, aktuell: ab, gemischt: schlange.gemischt, wiederholung: schlange.wiederholung)
            schlange = neu
        }
        guard let eintrag = schlange.aktuell else {
            beenden()
            return
        }
        fehler = nil
        fehlschlaege = 0
        gescheitert = []
        if stelle > 1, stelle < (eintrag.lied.dauer ?? .infinity) - 3 { startstellen[eintrag.id] = stelle }
        let start = startstellen[eintrag.id]
        spielt = spielen
        if spielen { sitzungAktivieren() }
        allesNeuLaden()
        Protokoll.schreib("[Übergabe] zurück aufs iPhone: Stelle \(String(format: "%.1f", stelle)) s, "
                          + (wege[eintrag.id].map { "\($0.art.rawValue)" } ?? "kein Abspielweg"))
        // **Erst an die Stelle, dann los.** Sonst spielte das Lied von 0:00 an,
        // bis es bereit ist und springen kann — und die Anzeige stünde so
        // lange auf 0:00, weil ``aktuellesAbgleichen()`` die Stelle vom
        // frischen Item nimmt. Also danach setzen, und spielen erst beim Sprung
        // (``itemZustand(_:status:)``).
        position = start ?? 0
        uhrStellen(position)
        if spielen, start != nil {
            losNachSprung = eintrag.id
            // Eine FLAC-Datei vom Server lädt dafür erst ganz
            // (``Abspielregel/genauerZugriff(_:startMitten:)``) — so lange
            // zeigt sich das Warten wie jedes andere.
            wartenMelden(true)
        } else if spielen {
            player.play()
        } else {
            player.pause()
        }
        jetzt.modiSetzen(gemischt: schlange.gemischt, wiederholung: schlange.wiederholung)
        jetztLaeuftSetzen()
        geaendert?()
    }

    /// Die gezeigte Schlange als Befehl, drüben neu anzufangen — wenn das
    /// Gerät selbst keine mehr kennt.
    func fernNeuanfang() -> Fernaktion? {
        guard let ab = schlange.position, !schlange.istLeer else { return nil }
        return .spielen(ids: schlange.eintraege.map(\.lied.id), ab: ab, stelle: position)
    }

    /// **Umstellen geht nur hier.** Jellyfin kennt keinen Befehl, der eine
    /// fremde Schlange umsortiert oder kürzt; sie neu zu schicken, finge das
    /// laufende Lied drüben von vorn an.
    private func fernUmstellbar() -> Bool {
        guard let fern, fern.art != .sonos else { return true }
        fernHinweis?(String(localized: "Die Schlange auf \(fern.name) lässt sich von hier nicht umstellen."))
        return false
    }

    // MARK: - Lautheit

    /// **Jedes Lied gleich laut** (``Lautheitsregel``): albumweise, wenn ein
    /// Album in seiner Folge läuft, sonst liedweise. Gesetzt beim Wechsel —
    /// iOS kennt keine Lautheits-Einheit im Player, also trägt der Player die
    /// Lautstärke selbst, wie bei Finamp.
    func lautstaerkeSetzen() {
        let fernfaktor = Float(stumm ? 0 : fernLautstaerke)
        guard einstellungen?.lautheitAngleichen ?? true else {
            player.volume = fernfaktor
            return
        }
        let albumweise = herkunft?.art == .album && !schlange.gemischt
        player.volume = Lautheitsregel.lautstaerke(aktuell?.lautheit, albumweise: albumweise) * fernfaktor
    }

    /// `SetVolume` von einem anderen Gerät. iOS lässt eine App die
    /// Systemlautstärke nicht setzen; es ist die des Players, auf die
    /// Lautheit obendrauf.
    func lautstaerkeVonFern(_ prozent: Int) {
        fernLautstaerke = Double(min(max(prozent, 0), 100)) / 100
        lautstaerkeSetzen()
        fortschrittMelden()
    }

    /// `Mute`, `Unmute`, `ToggleMute` — `nil` schaltet um.
    func stummVonFern(_ an: Bool?) {
        stumm = an ?? !stumm
        lautstaerkeSetzen()
        fortschrittMelden()
    }

    // MARK: - Sperrbildschirm und Glut

    private func jetztLaeuftSetzen() {
        guard let lied = aktuell else {
            jetzt.leeren()
            return
        }
        jetzt.setzen(lied: lied, dauer: dauer, position: position, laeuft: spielt)
        guard let bild = lied.bild, let url = ablage?.lokalesBild(bild)
                ?? quelle?.bildadresse(bild, kante: 600) else { return }
        let fuer = lied.id
        Task { [weak self] in
            guard let roh = await Bildlager.geteilt.rohbildLaden(url),
                  let self, self.aktuell?.id == fuer else { return }
            self.jetzt.bild(UIImage(cgImage: roh))
        }
    }

    private func jetztLaeuftZeit() {
        jetzt.zeit(position: position, dauer: dauer, laeuft: spielt && !puffert)
    }

    private func glutLaden() {
        guard let bild = aktuell?.bild,
              let url = ablage?.lokalesBild(bild) ?? quelle?.bildadresse(bild, kante: 600) else {
            glut = nil
            return
        }
        let fuer = aktuell?.id
        Task { [weak self] in
            guard let roh = await Bildlager.geteilt.rohbildLaden(url) else { return }
            let kiste = Bildkiste(bild: roh)
            let neu = await Task.detached(priority: .utility) { Glutrechner.glut(kiste) }.value
            guard let self, self.aktuell?.id == fuer else { return }
            withAnimation(.easeInOut(duration: 0.4)) { self.glut = neu }
        }
    }
}

/// Rechnet die Glut aus einem verkleinerten Abzug der Hülle.
enum Glutrechner {
    static func glut(_ kiste: Bildkiste) -> Huellenton.Glut? {
        let kante = 24
        var punkte = [UInt8](repeating: 0, count: kante * kante * 4)
        guard let raum = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let gezeichnet = punkte.withUnsafeMutableBytes { speicher -> Bool in
            guard let z = CGContext(data: speicher.baseAddress, width: kante, height: kante,
                                    bitsPerComponent: 8, bytesPerRow: kante * 4, space: raum,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            z.interpolationQuality = .medium
            z.draw(kiste.bild, in: CGRect(x: 0, y: 0, width: kante, height: kante))
            return true
        }
        guard gezeichnet else { return nil }
        return Huellenton.glut(rgba: punkte)
    }
}

/// **Wohin die Wiedergabe gerade geht**, wenn nicht hierher: das Gerät für
/// den Hinweis „Läuft auf ‹Gerät›" und das Zeichen dazu.
struct Fernanzeige: Equatable {
    /// Connect (eine Jellyfin-Sitzung, deren Schlange wir spiegeln) oder
    /// Sonos (unsere Schlange, der Lautsprecher spielt nur).
    enum Art: Equatable { case connect, sonos }

    let sitzungID: String
    var name: String
    /// SF-Symbol nach ``Musiksitzung/geraeteart``.
    var zeichen: String
    var art: Art = .connect
}

// MARK: - Der Tap

/// **Die Leitung vom Tonfaden zur Oberfläche** — zwei atomare Werte, keine
/// Sperre. Der Tap schreibt die Bänder (``Pegelanalyse/packen(_:)``), die
/// ``Pegelquelle`` liest sie im Takt der Anzeige; ob überhaupt gerechnet
/// wird, sagt `gefragt`.
enum Pegelleitung {
    static let wert = Atomic<UInt64>(0)
    static let gefragt = Atomic<Bool>(false)
    /// Die Kennung des Taps am laufenden Item; 0 heißt keiner.
    static let aktiv = Atomic<UInt64>(0)

    /// Legt alle an, bevor der Tonfaden sie zum ersten Mal braucht.
    static func vorbereiten() {
        _ = wert.load(ordering: .relaxed)
        _ = gefragt.load(ordering: .relaxed)
        _ = aktiv.load(ordering: .relaxed)
    }
}

/// Was ein Tap zwischen seinen Rückrufen behält — einmal angelegt, im
/// Tonfaden nur gelesen und beschrieben, nie neu angefordert.
private struct Tapzustand {
    /// Welches Item — nur der Tap des laufenden schreibt.
    var kennung: UInt64 = 0
    var analyse = Pegelanalyse(abtastrate: 44_100)
    var verschraenkt = false
    var kanaele = 0
    var tauglich = false
}

/// **`MTAudioProcessingTap` am `AVPlayerItem`**, für den Pegel.
///
/// `process` läuft auf dem Echtzeitfaden des Tons. Dort geschieht nur:
/// die Proben holen (sonst bliebe es still), nachsehen, ob jemand hinsieht,
/// die Bänder rechnen und eine Zahl atomar schreiben. Keine Anforderung von
/// Speicher, keine Sperre, kein Sprung auf den Hauptlauf, kein Zählen von
/// Verweisen — der Zustand liegt in selbst verwaltetem Speicher, den `init`
/// anlegt und `finalize` freigibt.
enum Pegeltap {

    /// `kennung` (nie 0) kommt als `clientInfo` herein — eine Zahl im Zeiger,
    /// kein Verweis, den jemand zählen müsste.
    static func machen(kennung: UInt64) -> MTAudioProcessingTap? {
        var rueckrufe = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(bitPattern: UInt(kennung)),
            init: { _, info, speicher in
                let zustand = UnsafeMutablePointer<Tapzustand>.allocate(capacity: 1)
                zustand.initialize(to: Tapzustand(kennung: UInt64(UInt(bitPattern: info))))
                speicher.pointee = UnsafeMutableRawPointer(zustand)
            },
            finalize: { tap in
                let zustand = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: Tapzustand.self)
                zustand.deinitialize(count: 1)
                zustand.deallocate()
            },
            prepare: { tap, _, format in
                // Nicht im Echtzeitfaden: hier darf neu angelegt werden.
                let zustand = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: Tapzustand.self)
                let f = format.pointee
                zustand.pointee.analyse = Pegelanalyse(abtastrate: f.mSampleRate)
                zustand.pointee.verschraenkt = f.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
                zustand.pointee.kanaele = Int(f.mChannelsPerFrame)
                zustand.pointee.tauglich = f.mFormatID == kAudioFormatLinearPCM
                    && f.mFormatFlags & kAudioFormatFlagIsFloat != 0 && f.mBitsPerChannel == 32
            },
            unprepare: nil,
            process: { tap, anzahl, _, liste, anzahlAus, flagsAus in
                guard MTAudioProcessingTapGetSourceAudio(tap, anzahl, liste, flagsAus, nil, anzahlAus) == noErr,
                      Pegelleitung.gefragt.load(ordering: .relaxed) else { return }
                let zustand = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: Tapzustand.self)
                guard zustand.pointee.tauglich,
                      zustand.pointee.kennung == Pegelleitung.aktiv.load(ordering: .relaxed) else { return }
                let puffer = UnsafeMutableAudioBufferListPointer(liste)
                let n = Int(anzahlAus.pointee)
                guard n > 0, puffer.count > 0, let erster = puffer[0].mData else { return }
                let a = UnsafePointer(erster.assumingMemoryBound(to: Float.self))
                if zustand.pointee.verschraenkt {
                    let k = max(zustand.pointee.kanaele, 1)
                    zustand.pointee.analyse.aufnehmen(a, k > 1 ? a + 1 : nil, anzahl: n, schritt: k)
                } else {
                    let b = puffer.count > 1 ? puffer[1].mData.map { UnsafePointer($0.assumingMemoryBound(to: Float.self)) } : nil
                    zustand.pointee.analyse.aufnehmen(a, b, anzahl: n)
                }
                let baender = zustand.pointee.analyse.abschliessen()
                Pegelleitung.wert.store(Pegelanalyse.packen(baender), ordering: .relaxed)
            })
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &rueckrufe,
                                                kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        return status == noErr ? tap : nil
    }
}
