import Foundation
import JellyfinKit
import MusikKit
import SwiftUI
import UIKit

/// **Sonos: Lautsprecher finden, hinschicken, steuern, gruppieren, lauter
/// und leiser** — mit Jellyfin wie mit Navidrome.
///
/// Der Lautsprecher holt die Musik selbst beim Server; das iPhone steuert
/// nur. Die Schlange bleibt hier (``Spieler/schlangeIstEigen``) und liegt
/// als Kopie in der Sonos-Warteschlange (``Sonossteuerung``): so spielt er
/// sie selbst durch, auch mit gesperrtem iPhone. Was sich hier ändert, wird
/// dort hinter dem laufenden Lied angeglichen; die Abfrage liest zurück,
/// wo er steht. Der Stand drüben läuft als ``Fernstand`` wie bei
/// Connect — dieselbe weiche Stelle, dieselben Regeln für eigene Befehle.
///
/// **Wann gefragt wird.** Gesucht (Bonjour) und die Gruppen geholt wird nur,
/// solange das Blatt „Abspielen auf" oder das Lautstärke-Blatt offen ist.
/// Der Stand des gewählten Lautsprechers kommt jede Sekunde, solange die
/// App vorn ist. Keine Event-Abos: dafür bräuchte das iPhone einen eigenen
/// HTTP-Server.
@MainActor
@Observable
final class Sonosmodell {

    /// Die Gruppen im Haushalt, nach Namen. Leer, solange keiner gefunden ist.
    private(set) var gruppen: [SonosGruppe] = []
    /// Die Lautstärke je Lautsprecher, 0 bis 100 — alle, solange ein Blatt
    /// offen ist, sonst die der gewählten Gruppe.
    private(set) var lautstaerken: [String: Int] = [:]
    /// Das Bild je Lautsprecher, aus seinem Modell (``SonosTopologie/zeichen(modell:)``).
    private(set) var bilder: [String: String] = [:]
    /// Die gewählte Gruppe, wenn die Wiedergabe auf Sonos läuft.
    ///
    /// Jede Änderung — Abfrage, eigener Befehl, Loslassen — stellt die
    /// ``stille`` nach: an, solange der Stand drüben läuft, sonst aus.
    private(set) var ziel: Ziel? {
        didSet { stille.setzen(ziel?.stand.laeuft ?? false) }
    }
    /// Ob gerade umgeschaltet oder gruppiert wird — ein zweiter Tipp wartet.
    private(set) var beschaeftigt = false
    /// **Haken oder Plus, schon angetippt**, aber noch nicht von Sonos
    /// bestätigt: Lautsprecher → soll drin sein. So wandert die Zeile sofort.
    private(set) var vorgemerkt: [String: Bool] = [:]

    /// Das Blatt „Abspielen auf" ist offen: suchen und die Gruppen holen.
    var blattOffen = false {
        didSet { if blattOffen != oldValue { takten() } }
    }
    /// **Das Lautstärke-Blatt** — die Tasten am iPhone öffnen es, solange
    /// Sonos spielt.
    var lautstaerkeOffen = false {
        didSet { if lautstaerkeOffen != oldValue { takten() } }
    }

    struct Ziel {
        var gruppe: SonosGruppe
        var stand: Fernstand
        let steuerung: Sonossteuerung
        var sitzungID: String { "sonos:" + steuerung.koordinator.id }
    }

    /// Die Lautstärketasten am iPhone, solange Sonos das Ziel ist.
    let tasten = Lautstaerketasten()
    /// **Stille, solange Sonos spielt** — Sperrbildschirm und Dynamic Island
    /// zeigen die App dann als laufend (``Sonosstille``).
    let stille = Sonosstille()

    /// **Wie oft gefragt wird:** jede Sekunde, solange die App vorn ist;
    /// im Hintergrund (wach nur durch die ``stille``) alle 5 s — genug für
    /// einen Liedwechsel auf dem Sperrbildschirm, sparsam mit Akku und Netz.
    static let abfragetakt: (vorn: Duration, hinten: Duration) = (.seconds(1), .seconds(5))

    /// **Eine Taste, eine Stufe** — wie viel ein Druck auf Lauter oder
    /// Leiser am Lautsprecher ändert, und ebenso ein Tipp auf Plus und Minus.
    static let stufe = 4

    @ObservationIgnored private weak var modell: Musikmodell?
    @ObservationIgnored private var quelle: (any Musikquelle)?
    @ObservationIgnored private var imVordergrund = true
    @ObservationIgnored private var suche: Task<Void, Never>?
    @ObservationIgnored private var gefunden = Set<URL>()
    @ObservationIgnored private var topologietakt: Task<Void, Never>?
    @ObservationIgnored private var lauf: Task<Void, Never>?
    @ObservationIgnored private var zeiger: Task<Void, Never>?
    @ObservationIgnored private var folge = Fernbefehlsfolge()
    @ObservationIgnored private var sender: Task<Void, Never>?
    @ObservationIgnored private var anlauf = Sonosanlauf()
    /// Nach einem Befehl: Abfragen, die vorher begannen, zählen nicht.
    @ObservationIgnored private var ruheBis = Date.distantPast
    @ObservationIgnored private var fremdGesehen = 0
    @ObservationIgnored private var fehlschlaege = 0
    @ObservationIgnored private var clients: [String: SonosClient] = [:]
    /// Je Lautsprecher (oder „gruppe"): die letzte Lautstärke unterwegs —
    /// die neueste gewinnt.
    @ObservationIgnored private var lautstaerkeauftraege: [String: Task<Void, Never>] = [:]
    /// Bis wann ein Regler gerade von Hand gezogen wurde — so lange
    /// überschreibt keine Abfrage seinen Wert.
    @ObservationIgnored private var handBis: [String: Date] = [:]
    /// Schließt das Lautstärke-Blatt, wenn nach einem Tastendruck nichts mehr kommt.
    @ObservationIgnored private var schliesser: Task<Void, Never>?

    private var spieler: Spieler? { modell?.spieler }

    // MARK: - Anmelden und Abmelden

    func starten(_ quelle: any Musikquelle, modell: Musikmodell) {
        beenden()
        self.quelle = quelle
        self.modell = modell
        modell.spieler.sonossteuern = { [weak self] aktion in self?.senden(aktion) }
        modell.spieler.sonosSchlangeGeaendert = { [weak self] in self?.naechstesNachziehen() }
        stille.gewechselt = { [weak self] in self?.takten() }
        tasten.gedrueckt = { [weak self] richtung in
            guard let self, self.ziel != nil else { return }
            self.stufe(richtung)
            // Aufgemacht von der Taste: nach ein paar Sekunden ohne Druck
            // geht es von selbst wieder zu.
            let warOffen = self.lautstaerkeOffen
            self.lautstaerkeOffen = true
            if !warOffen || self.schliesser != nil { self.spaeterSchliessen() }
        }
    }

    /// **Beim Abmelden hört alles auf** — Suche, Takt, Befehle. Spielte
    /// Sonos, hält er an: die Adresse, die er hat, gilt ohne Anmeldung nicht mehr.
    func beenden() {
        if let z = ziel { Task { try? await z.steuerung.pausieren() } }
        ziel = nil
        stille.setzen(false)
        suche?.cancel(); suche = nil
        topologietakt?.cancel(); topologietakt = nil
        lauf?.cancel(); lauf = nil
        zeiger?.cancel(); zeiger = nil
        sender?.cancel(); sender = nil
        lautstaerkeauftraege.values.forEach { $0.cancel() }
        lautstaerkeauftraege = [:]
        folge = Fernbefehlsfolge()
        tasten.aus()
        spieler?.sonossteuern = nil
        spieler?.sonosSchlangeGeaendert = nil
        quelle = nil
        gruppen = []
        lautstaerken = [:]
        blattOffen = false
        lautstaerkeOffen = false
    }

    // MARK: - Vordergrund und Hintergrund

    func vordergrund() {
        imVordergrund = true
        tastenAbgleichen()
        // Lief die Abfrage im Hintergrund im 5-s-Takt weiter, jetzt gleich
        // neu im Sekundentakt — statt die angefangene Pause auszusitzen.
        lauf?.cancel(); lauf = nil
        takten()
    }

    /// **Die Tasten abfangen, solange Sonos das Ziel ist und die App vorn**
    /// — immer, ohne Schalter (25.09.: besser als bei Spotify).
    private func tastenAbgleichen() {
        if imVordergrund, ziel != nil { tasten.an() } else { tasten.aus() }
    }

    /// **Die Anzeige des Systems nur verstecken, solange unser Blatt offen
    /// ist.** Der erste Druck zeigt sie also noch (und öffnet das Blatt),
    /// danach steht unser Blatt an ihrer Stelle. Die Tasten selbst bleiben,
    /// was sie sind (``Lautstaerketasten``).
    var anzeigeVerstecken: Bool { tasten.aktiv && lautstaerkeOffen }

    /// **Im Hintergrund fragt es nur weiter, solange Sonos spielt** — dann
    /// hält die ``stille`` die App wach, und die Abfrage läuft alle 5 s
    /// (``abfragetakt``): ein Liedwechsel oder eine Pause aus der Sonos-App
    /// kommen so auf dem Sperrbildschirm an. Steht Sonos, hält iOS die App an;
    /// der nächste Befehl vom Sperrbildschirm (``abarbeiten()``) oder das
    /// Öffnen holen den Stand nach.
    ///
    /// Beim Gang in den Hintergrund wird einmal frisch gefragt; dann stehen
    /// Lied, Hülle, Dauer, Stelle und Rate in `MPNowPlayingInfoCenter`, und
    /// iOS rechnet die Stelle selbst weiter.
    ///
    /// Die Stille ist eine bewusste Entscheidung (25.09.), wie bei Spotify —
    /// App Review kann sie nach 2.5.4 hinterfragen (``Sonosstille``).
    func hintergrund() {
        imVordergrund = false
        tasten.aus()
        takten()
        guard ziel != nil else { return }
        let aufschub = UIApplication.shared.beginBackgroundTask(withName: "Sonos-Stand")
        Task { [weak self] in
            await self?.abfragen()
            UIApplication.shared.endBackgroundTask(aufschub)
        }
    }

    // MARK: - Takt

    private func takten() {
        let sichtbar = imVordergrund && quelle != nil && (blattOffen || lautstaerkeOffen)
        if sichtbar {
            if suche == nil { sucheStarten() }
            if topologietakt == nil {
                topologietakt = Task { [weak self] in
                    while !Task.isCancelled {
                        await self?.topologieHolen()
                        try? await Task.sleep(for: .seconds(2.5))
                    }
                }
            }
        } else {
            suche?.cancel(); suche = nil
            topologietakt?.cancel(); topologietakt = nil
        }
        // Vorn immer, hinten nur, solange die Stille die App wach hält.
        let fragen = ziel != nil && (imVordergrund || stille.an)
        if fragen {
            if lauf == nil {
                lauf = Task { [weak self] in
                    while !Task.isCancelled {
                        await self?.abfragen()
                        let vorn = self?.imVordergrund ?? true
                        try? await Task.sleep(for: vorn ? Self.abfragetakt.vorn : Self.abfragetakt.hinten)
                    }
                }
            }
        } else {
            lauf?.cancel(); lauf = nil
        }
        // Die Anzeige zwischen zwei Abfragen braucht nur, wer hinsieht.
        if imVordergrund && ziel != nil {
            if zeiger == nil {
                // Die Stelle drüben läuft zwischen zwei Abfragen weiter.
                zeiger = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard let self, let z = self.ziel else { return }
                        self.spieler?.fernZeit(z.stand.stelle())
                    }
                }
            }
        } else {
            zeiger?.cancel(); zeiger = nil
        }
    }

    // MARK: - Finden

    /// **Bonjour, bis das Blatt zugeht.** Jeder neue Fund holt die Gruppen
    /// sofort — ein Lautsprecher kennt alle.
    private func sucheStarten() {
        suche = Task { [weak self] in
            for await basis in SonosSuche.basen() {
                guard let self, !Task.isCancelled else { return }
                if self.gefunden.insert(basis).inserted {
                    await self.topologieHolen()
                }
            }
        }
    }

    private func client(_ l: SonosLautsprecher) -> SonosClient {
        if let c = clients[l.id], c.basis == l.basis { return c }
        let c = SonosClient(basis: l.basis)
        clients[l.id] = c
        return c
    }

    @ObservationIgnored private var holtGerade = false

    /// Die Gruppen von irgendeinem Lautsprecher, der antwortet — der
    /// gewählte zuerst, dann die gefundenen.
    private func topologieHolen() async {
        guard !holtGerade else { return }
        holtGerade = true
        defer { holtGerade = false }
        var basen = gefunden.sorted { $0.absoluteString < $1.absoluteString }
        if let z = ziel { basen.insert(z.steuerung.koordinator.basis, at: 0) }
        for basis in basen {
            guard !Task.isCancelled else { return }
            guard let neu = try? await SonosClient(basis: basis).gruppen(), !neu.isEmpty else { continue }
            if neu != gruppen { gruppen = neu }
            for l in SonosTopologie.lautsprecher(neu) { gefunden.insert(l.basis) }
            gruppeAbgleichen()
            await lautstaerkenHolen()
            return
        }
    }

    /// Hat sich die gewählte Gruppe geändert (in der Sonos-App gruppiert),
    /// folgen Name und Mitglieder.
    private func gruppeAbgleichen() {
        guard var z = ziel,
              let neu = gruppen.first(where: { $0.koordinator.id == z.steuerung.koordinator.id }),
              neu != z.gruppe else { return }
        z.gruppe = neu
        ziel = z
        spieler?.fernBeginnen(Fernanzeige(sitzungID: z.sitzungID, name: neu.name,
                                          zeichen: Self.zeichen(neu), art: .sonos))
    }

    private func lautstaerkenHolen() async {
        let jetzt = Date()
        let sichtbar = blattOffen || lautstaerkeOffen
        let welche = sichtbar ? SonosTopologie.lautsprecher(gruppen) : (ziel?.gruppe.mitglieder ?? [])
        for l in welche where bilder[l.id] == nil {
            // Einmal je Lautsprecher: das Modell steht in seiner Beschreibung.
            bilder[l.id] = SonosTopologie.zeichen(modell: try? await client(l).beschreibung().modell)
        }
        for l in welche {
            guard (handBis[l.id] ?? .distantPast) < jetzt,
                  let wert = try? await client(l).lautstaerke() else { continue }
            if lautstaerken[l.id] != wert { lautstaerken[l.id] = wert }
        }
    }

    /// Die Kennung in ``Spieler/fern`` — steht dort, sobald der Tipp auf die
    /// Gruppe angekommen ist, noch vor der Antwort des Lautsprechers.
    static func sitzungID(_ g: SonosGruppe) -> String { "sonos:" + g.koordinator.id }

    /// Ob `l` in der Gruppe ist — mit dem, was gerade angetippt wurde.
    func drin(_ l: SonosLautsprecher, in g: SonosGruppe) -> Bool {
        vorgemerkt[l.id] ?? g.enthaelt(l.id)
    }

    static func zeichen(_ g: SonosGruppe) -> String {
        g.mitglieder.count > 1 ? "hifispeaker.2" : "hifispeaker"
    }

    // MARK: - Hinschicken

    /// **Ein Tipp auf eine Gruppe im Blatt.** Das Blatt bleibt offen: darunter
    /// stehen jetzt Lautstärke und Gruppieren.
    private func verbinden(_ g: SonosGruppe) async {
        guard let quelle, let modell, let spieler = self.spieler, !beschaeftigt else { return }
        guard quelle.sonosMoeglich else {
            modell.hinweis = String(localized: "Mit dieser Navidrome-Anmeldung geht Sonos nicht. Der Server will dein Passwort in jeder Adresse, und die zeigt die Sonos-App offen an.")
            return
        }
        beschaeftigt = true
        defer { beschaeftigt = false }
        modell.angebot = nil

        // Woher die Musik kommt: ein Connect-Gerät gibt seine Schlange her,
        // eine andere Sonos-Gruppe hält an, sonst dieses iPhone.
        var spielte = spieler.spielt
        var stelle = spieler.stelle()
        if spieler.fern?.art == .connect {
            guard let vorher = await modell.fern.abgeben() else { return }
            spielte = vorher.spielte
            stelle = vorher.stelle
        } else if let alt = ziel {
            spielte = !alt.stand.angehalten
            stelle = alt.stand.stelle()
            loslassen(anhalten: true)
        }
        guard spieler.schlange.aktuell != nil else {
            modell.hinweis = String(localized: "Spiel zuerst etwas, dann geht es auf \(g.name) weiter.")
            return
        }
        guard let plan = plan() else {
            modell.hinweis = String(localized: "\(g.name) hat nicht reagiert.")
            return
        }
        let steuerung = Sonossteuerung(koordinator: g.koordinator)
        let anzeige = Fernanzeige(sitzungID: Self.sitzungID(g), name: g.name,
                                  zeichen: Self.zeichen(g), art: .sonos)
        Spur.sag("[Sonos] \(g.name): übernehmen, \(spielte ? "spielt" : "angehalten")")
        // Hier sofort still — wie bei Spotify, nicht erst, wenn Sonos antwortet.
        spieler.fernBeginnen(anzeige)
        do {
            try await steuerung.uebernehmen(plan.spuren, ab: plan.ab, stelle: stelle, spielen: spielte,
                                            wiederholung: spieler.schlange.wiederholung)
            if !(await steuerung.mitWarteschlange) { Spur.sag("[Sonos] \(g.name): ohne Warteschlange, einzeln") }
        } catch {
            Spur.sag("[Sonos] \(g.name): laden gescheitert, \(Self.beschreibung(error))")
            spieler.fernBeenden(lieder: nil, ab: 0, stelle: stelle, spielen: spielte)
            modell.hinweis = Self.meldung(error, name: g.name)
            return
        }
        guard self.quelle === quelle else { return }
        ziel = Ziel(gruppe: g, stand: frischerStand(anzeige.sitzungID, name: g.name, stelle: stelle, laeuft: spielte),
                    steuerung: steuerung)
        folge = Fernbefehlsfolge()
        fremdGesehen = 0
        fehlschlaege = 0
        if spielte { anlauf.gestartet() } else { anlauf.beenden() }
        ruheBis = Date().addingTimeInterval(1)
        if let z = ziel { spieler.fernLauf(z.stand) }
        tastenAbgleichen()
        takten()
        await lautstaerkenHolen()
    }

    /// Ein Stand, wie er sein soll — bevor die erste Abfrage kommt.
    private func frischerStand(_ id: String, name: String, stelle: TimeInterval, laeuft: Bool) -> Fernstand {
        let schlange = spieler?.schlange ?? Warteschlange()
        let lage = SonosLage(zustand: laeuft ? .spielt : .pausiert, spur: nil, geladen: nil,
                             naechstesGeladen: nil, stelle: stelle, dauer: nil)
        return Fernstand(Sonosfolge.sitzung(id: id, name: name, schlange: schlange, lage: lage,
                                            unser: true, abgefragt: Date()))
    }

    // MARK: - Befehle

    /// **Ein Knopf am Lautsprecher** — der Stand folgt sofort, die Befehle
    /// gehen der Reihe nach (``Fernbefehlsfolge``), wie bei Connect.
    private func senden(_ aktion: Fernaktion) {
        guard var z = ziel, let spieler else { return }
        guard let gewollt = z.stand.aufloesen(aktion) ?? spieler.fernNeuanfang() else { return }
        if case let .spielen(_, _, stelle) = gewollt {
            // Ein Lied (neu) laden: der Stand fängt neu an — spielend, wenn
            // Abspielen gedrückt war oder es eben spielte.
            let los: Bool
            switch aktion {
            case .weiter, .umschalten: los = true
            default: los = !z.stand.angehalten && !z.stand.gestoppt
            }
            z.stand = frischerStand(z.sitzungID, name: z.gruppe.name, stelle: stelle, laeuft: los)
        }
        let nummer = z.stand.vormerken(gewollt)
        ziel = z
        folge.einreihen(gewollt, nummer: nummer)
        spieler.fernLauf(z.stand)
        abarbeiten()
    }

    private func abarbeiten() {
        guard sender == nil else { return }
        // Vom Sperrbildschirm, mit der App im Hintergrund: iOS weckt sie für
        // den Befehl nur kurz. Etwas Zeit erbitten, bis er drüben ist, und
        // danach frisch fragen — so stimmen dort auch Lied und Stelle wieder.
        let aufschub = imVordergrund ? nil : UIApplication.shared.beginBackgroundTask(withName: "Sonos-Befehl")
        sender = Task { [weak self] in
            await self?.folgeSenden()
            self?.sender = nil
            guard let aufschub else { return }
            try? await Task.sleep(for: .seconds(1.1))
            await self?.abfragen()
            UIApplication.shared.endBackgroundTask(aufschub)
        }
    }

    private func folgeSenden() async {
        while let z = ziel, let befehl = folge.naechster() {
            // Erst fertig angleichen, dann springen — beides ändert, was drüben liegt.
            await nachzieher?.value
            do {
                try await ausfuehren(befehl.aktion, z)
            } catch {
                if !Task.isCancelled {
                    Spur.sag("[Sonos] \(z.gruppe.name): Befehl gescheitert, \(Self.beschreibung(error))")
                    modell?.hinweis = Self.meldung(error, name: z.gruppe.name)
                }
            }
            let erledigt = folge.fertig() ?? befehl
            ruheBis = Date().addingTimeInterval(1)
            guard var frisch = ziel, frisch.sitzungID == z.sitzungID else { continue }
            frisch.stand.erledigt(erledigt.nummer)
            ziel = frisch
        }
        naechstesNachziehen()
    }

    private func ausfuehren(_ aktion: Fernaktion, _ z: Ziel) async throws {
        switch aktion {
        case .pause:
            anlauf.beenden()
            try await z.steuerung.pausieren()
        case .weiter, .umschalten:
            anlauf.gestartet()
            try await z.steuerung.abspielen()
        case let .springen(s):
            try await z.steuerung.springen(s)
        case .stopp:
            anlauf.beenden()
            try await z.steuerung.stoppen()
        case let .spielen(_, _, stelle):
            // Die Schlange hier sagt, welches Lied — die Kennungen im Befehl
            // sind für Connect.
            // Liegt das Lied in der Sonos-Warteschlange, nur dorthin springen.
            guard let spieler, let eintrag = spieler.schlange.aktuell else { return }
            let los = !(ziel?.stand.angehalten ?? true)
            if try await !z.steuerung.springen(zu: eintrag.id, stelle: stelle, spielen: los) {
                guard let plan = plan() else { return }
                try await z.steuerung.uebernehmen(plan.spuren, ab: plan.ab, stelle: stelle, spielen: los,
                                                  wiederholung: spieler.schlange.wiederholung)
            }
            if los { anlauf.gestartet() }
        case .naechstes, .voriges, .wiederholung, .mischen, .alsNaechstes, .hintenAn:
            // Macht die Schlange hier (``Spieler``); ein Befehl dafür kommt nicht.
            break
        }
    }

    /// Der Ausschnitt der Schlange für die Sonos-Warteschlange, als Spuren.
    private func plan() -> (spuren: [Sonosspur], ab: Int)? {
        guard let quelle, let spieler else { return nil }
        let (eintraege, ab) = Sonosfolge.fenster(spieler.schlange)
        let spuren = eintraege.compactMap { Sonosspur.aus($0, quelle: quelle) }
        guard !spuren.isEmpty, spuren.count == eintraege.count else { return nil }
        return (spuren, ab)
    }

    /// Die Angleichungen der Warteschlange, eine nach der anderen.
    @ObservationIgnored private var nachzieher: Task<Void, Never>?
    /// Wie viele Angleichungen noch laufen — solange fragt der Takt nicht.
    @ObservationIgnored private var nachziehend = 0

    /// **Die Sonos-Warteschlange angleichen** — nach einer Änderung der
    /// Schlange hier, und nachdem er weitergespielt hat (hinten nachfüllen).
    /// Läuft gerade ein Befehl, zieht der am Ende nach.
    private func naechstesNachziehen() {
        guard let z = ziel, sender == nil, let quelle, let spieler, let aktuell = spieler.schlange.aktuell,
              let plan = plan() else { return }
        let kommende = Array(plan.spuren[(plan.ab + 1)...])
        let naechste = Sonosfolge.naechster(spieler.schlange).flatMap { Sonosspur.aus($0, quelle: quelle) }
        let wiederholung = spieler.schlange.wiederholung
        let vorher = nachzieher
        nachziehend += 1
        nachzieher = Task { [weak self] in
            await vorher?.value
            do {
                try await z.steuerung.nachziehen(aktuell: aktuell.id, kommende: kommende, naechste: naechste,
                                                 wiederholung: wiederholung)
            } catch {
                Spur.sag("[Sonos] Warteschlange nicht angeglichen: \(Self.beschreibung(error))")
            }
            self?.nachziehend -= 1
        }
    }

    // MARK: - Abfragen

    @ObservationIgnored private var fragtGerade = false

    private func abfragen() async {
        // Während gruppiert wird, steht drüben kurz Unfertiges — eine leere
        // Warteschlange hieß einmal „weiter zum ersten Lied" (Test 25.09.).
        guard let z = ziel, let spieler, !fragtGerade, sender == nil, folge.leer, nachziehend == 0,
              !beschaeftigt, Date() >= ruheBis else { return }
        // Hat jemand anderes die Wiedergabe genommen (Connect schickt uns
        // etwas), lässt Sonos los.
        guard spieler.fern?.sitzungID == z.sitzungID else {
            loslassen(anhalten: true)
            return
        }
        fragtGerade = true
        defer { fragtGerade = false }
        let begonnen = Date()
        let marke = z.stand.marke()
        let a: Sonosabfrage
        do {
            a = try await z.steuerung.abfragen()
        } catch {
            if error is CancellationError { return }
            fehlschlaege += 1
            if fehlschlaege >= Fernstand.geduld {
                verloren(String(localized: "\(z.gruppe.name) ist nicht mehr da. Die Musik steht hier bereit."))
            }
            return
        }
        fehlschlaege = 0
        // Ein Befehl kam dazwischen: diese Antwort kennt ihn nicht.
        guard let jetzt = ziel, jetzt.sitzungID == z.sitzungID, sender == nil, begonnen >= ruheBis else { return }
        switch a.befund {
        case .weiter:
            fremdGesehen = 0
            if let e = a.eintrag { spieler.sonosWeiter(zu: e) }
            naechstesNachziehen()
        case .fremd:
            fremdGesehen += 1
            // Zweimal hintereinander, damit ein Übergang nicht zählt.
            if fremdGesehen >= 2 {
                verloren(String(localized: "Auf \(z.gruppe.name) läuft jetzt etwas anderes. Deine Musik steht hier bereit."))
                return
            }
        case .gleich, .leer:
            fremdGesehen = 0
        }
        let unser = a.befund == .gleich || a.befund == .weiter
        let sitzung = Sonosfolge.sitzung(id: jetzt.sitzungID, name: jetzt.gruppe.name, schlange: spieler.schlange,
                                         lage: a.lage, unser: unser, abgefragt: Date())
        var stand = jetzt.stand
        _ = stand.abgleichen([sitzung], marke: marke)
        ziel?.stand = stand
        spieler.fernLauf(stand)
        if anlauf.gescheitert(a.lage) {
            Spur.sag("[Sonos] \(jetzt.gruppe.name): spielt nach \(Int(Sonosanlauf.frist)) s nicht")
            modell?.hinweis = String(localized: "\(jetzt.gruppe.name) kommt nicht an deinen Server. Der Lautsprecher holt die Musik selbst, der Server muss also in seinem Netz erreichbar sein.")
        }
    }

    /// Sonos ist weg oder spielt etwas anderes: die Schlange steht hier
    /// angehalten bereit, an der Stelle von drüben.
    private func verloren(_ text: String) {
        guard let z = ziel, let spieler else { return }
        Spur.sag("[Sonos] \(z.gruppe.name): losgelassen")
        let stelle = z.stand.stelle()
        loslassen(anhalten: false)
        spieler.fernBeenden(lieder: nil, ab: 0, stelle: stelle, spielen: false)
        modell?.hinweis = text
    }

    /// Nicht mehr fragen, nichts mehr schicken. `anhalten`: Sonos hält an.
    private func loslassen(anhalten: Bool) {
        guard let z = ziel else { return }
        if anhalten { Task { try? await z.steuerung.pausieren() } }
        ziel = nil
        sender?.cancel(); sender = nil
        folge = Fernbefehlsfolge()
        anlauf.beenden()
        tasten.aus()
        offenHalten()
        lautstaerkeOffen = false
        takten()
    }

    // MARK: - Zurück

    /// **„Dieses iPhone"**: Sonos hält an, hier geht es mit demselben Lied
    /// an derselben Stelle weiter — und im selben Zustand: stand es drüben
    /// auf Pause, steht es hier auf Pause.
    ///
    /// Vorher (Test am 25.09.) spielte es hier immer los und stand bei 0:00:
    /// `spielen` war fest `true`, und die Stelle ging beim Laden verloren
    /// (``Spieler/fernBeenden(lieder:ab:stelle:spielen:)``).
    func hierWeiterhoeren() async {
        guard let z = ziel, let spieler else { return }
        let (stelle, lief, nochAnhalten) = await zurueckgeben(z)
        guard ziel?.sitzungID == z.sitzungID else { return }
        Spur.sag("[Sonos] \(z.gruppe.name): zurück aufs iPhone bei \(Int(stelle)) s, \(lief ? "spielt" : "angehalten")")
        loslassen(anhalten: nochAnhalten)
        spieler.fernBeenden(lieder: nil, ab: 0, stelle: stelle, spielen: lief)
    }

    /// **Für ein Connect-Gerät**: Sonos hält an, die Schlange steht hier
    /// angehalten bereit. Zurück kommt, ob Sonos eben spielte und wo.
    func abgeben() async -> (spielte: Bool, stelle: TimeInterval)? {
        guard let z = ziel, let spieler else { return nil }
        let (stelle, lief, nochAnhalten) = await zurueckgeben(z)
        guard ziel?.sitzungID == z.sitzungID else { return nil }
        loslassen(anhalten: nochAnhalten)
        spieler.fernBeenden(lieder: nil, ab: 0, stelle: stelle, spielen: false)
        return (lief, stelle)
    }

    /// **Wo er jetzt ist — frisch gefragt**, nicht der letzte Takt: aus dem
    /// Hintergrund zurück hat er womöglich schon mehrere Lieder weiter
    /// gespielt. Die Schlange hier rückt dabei auf sein Lied, und er hält an
    /// (``Sonossteuerung/zurueckgeben()``). Läuft dort Fremdes, gilt der
    /// gemerkte Stand und das Fremde läuft weiter. Ohne Antwort gilt er auch;
    /// `nochAnhalten`: dann bekommt er die Pause blind hinterher.
    private func zurueckgeben(_ z: Ziel) async -> (stelle: TimeInterval, lief: Bool, nochAnhalten: Bool) {
        let stelle = z.stand.stelle()
        let lief = !z.stand.angehalten && !z.stand.gestoppt
        let r: Sonosrueckgabe?
        do { r = try await z.steuerung.zurueckgeben() } catch { return (stelle, lief, true) }
        guard let r, ziel?.sitzungID == z.sitzungID else { return (stelle, lief, false) }
        if let e = r.eintrag, spieler?.schlange.aktuell?.id != e { spieler?.sonosWeiter(zu: e) }
        return (r.stelle, r.lief, false)
    }

    /// **Pille weggewischt**: nur dieses iPhone löst sich, Sonos spielt das
    /// laufende und das nächste Lied weiter. Zurück kommt „Rückgängig" —
    /// mit der Schlange, die hier stand.
    func lokalLoesen() -> (@MainActor () -> Void)? {
        guard let z = ziel, let spieler, let anzeige = spieler.fern else { return nil }
        let stand = Schlangenstand(schlange: spieler.schlange, stelle: z.stand.stelle(), herkunft: spieler.herkunft)
        loslassen(anhalten: false)
        return { [weak self] in
            guard let self, self.ziel == nil, let spieler = self.spieler, spieler.aktuell == nil else { return }
            spieler.wiederherstellen(stand)
            spieler.fernBeginnen(anzeige)
            self.ziel = z
            self.ruheBis = Date().addingTimeInterval(0.5)
            self.tastenAbgleichen()
            self.takten()
        }
    }

    // MARK: - Lautstärke

    /// Die Lautstärke der gewählten Gruppe: bei einem Lautsprecher seine,
    /// sonst der Durchschnitt, wie Sonos ihn zeigt.
    var gruppenlautstaerke: Int? {
        ziel.flatMap { lautstaerke(von: $0.gruppe) }
    }

    func lautstaerke(von g: SonosGruppe) -> Int? {
        let werte = g.mitglieder.compactMap { lautstaerken[$0.id] }
        guard !werte.isEmpty else { return nil }
        return werte.reduce(0, +) / werte.count
    }

    func lautstaerkeSetzen(_ l: SonosLautsprecher, _ wert: Int) {
        let wert = min(max(wert, 0), 100)
        lautstaerken[l.id] = wert
        handBis[l.id] = Date().addingTimeInterval(2)
        let c = client(l)
        auftrag(l.id) { try await c.lautstaerkeSetzen(wert) }
    }

    /// Die ganze Gruppe — Sonos verteilt es im Verhältnis der Einzelnen.
    func gruppenlautstaerkeSetzen(_ wert: Int) {
        guard let z = ziel else { return }
        gruppenlautstaerkeSetzen(z.gruppe, wert)
    }

    /// Eine beliebige Gruppe im Blatt — nicht nur die, auf der wir spielen.
    func gruppenlautstaerkeSetzen(_ g: SonosGruppe, _ wert: Int) {
        let wert = min(max(wert, 0), 100)
        if g.mitglieder.count == 1 {
            lautstaerkeSetzen(g.koordinator, wert)
            return
        }
        // Vorweg genähert, bis die Abfrage die echten Werte bringt.
        let alt = lautstaerke(von: g) ?? wert
        for l in g.mitglieder {
            let v = lautstaerken[l.id] ?? alt
            lautstaerken[l.id] = alt > 0 ? min(100, max(0, v * wert / alt)) : wert
            handBis[l.id] = Date().addingTimeInterval(2)
        }
        let c = client(g.koordinator)
        auftrag("gruppe:" + g.koordinator.id) { try await c.gruppenlautstaerkeSetzen(wert) }
    }

    private func spaeterSchliessen() {
        schliesser?.cancel()
        schliesser = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            self.schliesser = nil
            self.lautstaerkeOffen = false
        }
    }

    /// Im Blatt angefasst: es bleibt offen, bis man es selbst zumacht.
    func offenHalten() {
        schliesser?.cancel()
        schliesser = nil
    }

    /// Eine Stufe lauter (`+1`) oder leiser (`-1`) — Taste oder Knopf.
    func stufe(_ richtung: Int) {
        guard let v = gruppenlautstaerke else { return }
        gruppenlautstaerkeSetzen(v + richtung * Self.stufe)
    }

    private func auftrag(_ schluessel: String, _ tun: @escaping @Sendable () async throws -> Void) {
        lautstaerkeauftraege[schluessel]?.cancel()
        lautstaerkeauftraege[schluessel] = Task { [weak self] in
            // Ein Regler schickt beim Ziehen viele Werte — nur der letzte zählt.
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            do {
                try await tun()
            } catch {
                if !(error is CancellationError), !Task.isCancelled {
                    Spur.sag("[Sonos] Lautstärke nicht gesetzt: \(Self.beschreibung(error))")
                }
            }
            self?.lautstaerkeauftraege[schluessel] = nil
        }
    }

    // MARK: - Gruppieren

    /// **Haken oder Plus an einem Lautsprecher**: in die gewählte Gruppe
    /// holen oder aus ihr lösen. Geht der Koordinator selbst, spielt die
    /// Gruppe beim nächsten weiter — dann steuern wir den.
    func umschalten(_ l: SonosLautsprecher) {
        guard let z = ziel, !beschaeftigt else { return }
        let drin = z.gruppe.enthaelt(l.id)
        if drin, z.gruppe.mitglieder.count == 1 { return }
        Musikstil.ruck(.leicht)
        vorgemerkt[l.id] = !drin
        Task { await gruppieren(l, dazu: !drin) }
    }

    /// **Tipp auf die Zeile eines Lautsprechers: nur noch dort.** Spielt
    /// seine Gruppe schon unsere Musik, gehen die anderen heraus; sonst löst
    /// er sich aus seiner Gruppe, und die Musik kommt zu ihm allein.
    func alleinSpielen(_ l: SonosLautsprecher) {
        guard !beschaeftigt else { return }
        if let z = ziel, z.gruppe.enthaelt(l.id) {
            guard z.gruppe.mitglieder.count > 1 else { return }
            Musikstil.ruck(.leicht)
            for m in z.gruppe.mitglieder where m.id != l.id { vorgemerkt[m.id] = false }
            Task { await nurNoch(l) }
        } else {
            Task { await alleinVerbinden(l) }
        }
    }

    private func nurNoch(_ l: SonosLautsprecher) async {
        guard let z = ziel else { vorgemerkt = [:]; return }
        beschaeftigt = true
        defer {
            beschaeftigt = false
            vorgemerkt = [:]
        }
        let alt = z.steuerung.koordinator
        do {
            if alt.id != l.id {
                let neu = try await z.steuerung.koordinationUebergeben(an: l)
                koordinatorWechseln(neu, mitglieder: z.gruppe.mitglieder.filter { $0.id != alt.id })
            }
            for m in z.gruppe.mitglieder where m.id != l.id && m.id != alt.id {
                try await client(m).alleinstellen()
            }
        } catch {
            Spur.sag("[Sonos] Allein stellen gescheitert: \(Self.beschreibung(error))")
            modell?.hinweis = String(localized: "\(l.name) ließ sich nicht allein stellen.")
        }
        await neuLesen()
    }

    private func alleinVerbinden(_ l: SonosLautsprecher) async {
        if let g = gruppen.first(where: { $0.enthaelt(l.id) }), g.mitglieder.count > 1 {
            beschaeftigt = true
            try? await client(l).alleinstellen()
            await neuLesen()
            beschaeftigt = false
        }
        guard let g = gruppen.first(where: { $0.koordinator.id == l.id }) else {
            modell?.hinweis = String(localized: "\(l.name) hat nicht reagiert.")
            return
        }
        await verbinden(g)
    }

    /// Sonos braucht einen Moment, bis die neue Gruppe überall bekannt ist.
    /// Holt der Takt gerade, kennt seine Antwort die Änderung womöglich
    /// nicht — dann nach ihm noch einmal, sonst spränge der Haken zurück.
    private func neuLesen() async {
        try? await Task.sleep(for: .milliseconds(400))
        while holtGerade { try? await Task.sleep(for: .milliseconds(50)) }
        await topologieHolen()
    }

    private func gruppieren(_ l: SonosLautsprecher, dazu: Bool) async {
        guard let z = ziel else { vorgemerkt = [:]; return }
        beschaeftigt = true
        defer {
            beschaeftigt = false
            vorgemerkt = [:]
        }
        let koordinator = z.steuerung.koordinator
        do {
            if dazu {
                try await client(l).beitreten(koordinator.id)
            } else if l.id == koordinator.id, let naechster = z.gruppe.mitglieder.first(where: { $0.id != l.id }) {
                // **Der Koordinator geht: vorher die Gruppe übergeben.** Sonst
                // nimmt er die Warteschlange mit, und die übrigen spielen ein
                // anderes Lied (Test 25.09.). So wandern Schlange und Stelle mit.
                do {
                    let neu = try await z.steuerung.koordinationUebergeben(an: naechster)
                    koordinatorWechseln(neu, mitglieder: z.gruppe.mitglieder.filter { $0.id != l.id })
                } catch {
                    Spur.sag("[Sonos] Übergeben abgelehnt (\(Self.beschreibung(error))), neu laden")
                    try await client(l).alleinstellen()
                    await neuLesen()
                    let andere = Set(z.gruppe.mitglieder.map(\.id)).subtracting([l.id])
                    guard let g = gruppen.first(where: { g in g.mitglieder.contains { andere.contains($0.id) } }),
                          let alt = ziel else {
                        verloren(String(localized: "\(z.gruppe.name) ist nicht mehr da. Die Musik steht hier bereit."))
                        return
                    }
                    await uebergeben(an: g, von: alt)
                    return
                }
            } else {
                try await client(l).alleinstellen()
            }
        } catch {
            Spur.sag("[Sonos] Gruppieren gescheitert: \(Self.beschreibung(error))")
            modell?.hinweis = dazu
                ? String(localized: "\(l.name) ließ sich nicht dazuholen.")
                : String(localized: "\(l.name) ließ sich nicht aus der Gruppe nehmen.")
            return
        }
        await neuLesen()
    }

    /// **Ein neuer Koordinator spielt unsere Warteschlange weiter** — nach
    /// ``Sonossteuerung/koordinationUebergeben(an:)``. Stand und Anzeige
    /// ziehen im selben Zug um, sonst hielte die Abfrage die Sitzung für
    /// fremd und ließe los.
    private func koordinatorWechseln(_ steuerung: Sonossteuerung, mitglieder: [SonosLautsprecher]) {
        guard let z = ziel, let spieler else { return }
        let k = steuerung.koordinator
        let g = SonosGruppe(id: z.gruppe.id, koordinator: k, mitglieder: [k] + mitglieder.filter { $0.id != k.id })
        let lief = !z.stand.angehalten && !z.stand.gestoppt
        let stelle = z.stand.stelle()
        let anzeige = Fernanzeige(sitzungID: Self.sitzungID(g), name: g.name, zeichen: Self.zeichen(g), art: .sonos)
        spieler.fernBeginnen(anzeige)
        ziel = Ziel(gruppe: g, stand: frischerStand(anzeige.sitzungID, name: g.name, stelle: stelle, laeuft: lief),
                    steuerung: steuerung)
        ruheBis = Date().addingTimeInterval(1)
        if let neu = ziel { spieler.fernLauf(neu.stand) }
        Spur.sag("[Sonos] Gruppe an \(k.name) übergeben")
    }

    private func uebergeben(an g: SonosGruppe, von alt: Ziel) async {
        guard let spieler, let plan = plan() else { return }
        let lief = !alt.stand.angehalten && !alt.stand.gestoppt
        let stelle = alt.stand.stelle()
        let steuerung = Sonossteuerung(koordinator: g.koordinator)
        let anzeige = Fernanzeige(sitzungID: Self.sitzungID(g), name: g.name,
                                  zeichen: Self.zeichen(g), art: .sonos)
        do {
            try await steuerung.uebernehmen(plan.spuren, ab: plan.ab, stelle: stelle, spielen: lief,
                                            wiederholung: spieler.schlange.wiederholung)
        } catch {
            verloren(Self.meldung(error, name: g.name))
            return
        }
        spieler.fernBeginnen(anzeige)
        ziel = Ziel(gruppe: g, stand: frischerStand(anzeige.sitzungID, name: g.name, stelle: stelle, laeuft: lief),
                    steuerung: steuerung)
        ruheBis = Date().addingTimeInterval(1)
        if let z = ziel { spieler.fernLauf(z.stand) }
        await lautstaerkenHolen()
    }

    // MARK: - Meldungen

    /// Für das Protokoll: nie eine Adresse, nur die Art des Fehlers.
    static func beschreibung(_ fehler: any Error) -> String {
        switch fehler as? SonosFehler {
        case let .abgelehnt(status, upnp)?: "abgelehnt (\(status), UPnP \(upnp.map(String.init) ?? "–"))"
        case .unlesbar?: "Antwort unlesbar"
        case .nichtErreichbar?: "nicht erreichbar"
        case nil: String(describing: type(of: fehler))
        }
    }

    static func meldung(_ fehler: any Error, name: String) -> String {
        if (fehler as? SonosFehler)?.quelleUnerreichbar == true {
            return String(localized: "\(name) kommt nicht an deinen Server. Der Lautsprecher holt die Musik selbst, der Server muss also in seinem Netz erreichbar sein.")
        }
        return String(localized: "\(name) hat nicht reagiert.")
    }
}
