import Foundation
import JellyfinKit
import MusikKit
import SwiftUI

/// **Connect: andere Geräte sehen, hinschicken, steuern, zurückholen** —
/// und selbst steuerbar sein. Nur mit Jellyfin; Navidrome hat keinen Kanal
/// dafür (``Schlangenabgleich``).
///
/// Die Teile, die sich prüfen lassen, liegen in MusikKit: was aus dem
/// Steuerkanal kommt (``Kanalnachricht``), welche Geräte angeboten werden
/// (``Geraeteliste``), was ein Tipp bedeutet (``Uebergabe``), wie der Stand
/// drüben weiterläuft (``Fernstand``). Hier steht nur, wann gefragt, was
/// geschickt und was dem ``Spieler`` gesagt wird.
///
/// **Wann gefragt wird.** Die Geräteliste nur, solange das Blatt offen ist
/// (alle 3 Sekunden) oder die Wiedergabe drüben läuft (alle 2 Sekunden, der
/// Stand muss folgen). Sonst einmal beim Öffnen der App, für „läuft
/// woanders". Einen Weg, Sitzungsänderungen über den Kanal zu bestellen
/// (`SessionsStart`), gibt Jellyfin nur Administratoren; der Takt gilt für
/// jedes Konto.
@MainActor
@Observable
final class Fernmodell {

    /// Die anderen Geräte, was spielt zuerst.
    private(set) var geraete: [Musiksitzung] = []
    /// **Ob die Geräte da sind, noch kommen oder nicht kommen.** Vorher gab
    /// es nur „schon eine Antwort da", und ohne Server standen die
    /// Platzhalter im Blatt für immer (``Abfragewache``: 12 s ohne Antwort
    /// oder drei Fehlschläge in Folge).
    private(set) var wache = Abfragewache()
    /// Warum es gestört ist — für den Störhinweis im Blatt.
    private(set) var stoerung: Stoerung?
    var geraeteGeladen: Bool { wache.lage == .da }
    /// Das Gerät, auf dem die Wiedergabe gerade läuft.
    private(set) var ziel: Fernstand?
    /// Ob eine Übergabe läuft — ein zweiter Tipp startet keine zweite.
    private(set) var beschaeftigt = false
    /// Das Geräteblatt. Offen fragt es im Takt.
    var blattOffen = false {
        didSet {
            guard blattOffen != oldValue else { return }
            blattGeaendert?(blattOffen)
            if blattOffen {
                // Ein neuer Blick bekommt eine neue Frist.
                if wache.lage == .gestoert { wacheSetzen { $0.vonVorn() } }
                wachhundStarten()
            } else {
                wachhund?.cancel(); wachhund = nil
            }
            takten()
        }
    }

    /// Ob es Connect überhaupt gibt — nur bei Jellyfin.
    var verfuegbar: Bool { quelle != nil }

    /// Das Blatt ging auf oder zu — Sonos sucht, solange es offen ist.
    @ObservationIgnored var blattGeaendert: ((Bool) -> Void)?
    /// Sonos, um die Wiedergabe von dort herüberzuholen oder loszulassen.
    @ObservationIgnored weak var sonos: Sonosmodell?

    @ObservationIgnored private var quelle: JellyfinQuelle?
    @ObservationIgnored private weak var modell: Musikmodell?
    @ObservationIgnored private var kanal: Steuerkanal?
    @ObservationIgnored private var abfrage: Task<Void, Never>?
    @ObservationIgnored private var zeiger: Task<Void, Never>?
    /// Die Frist bis „gestört", solange noch keine Antwort kam.
    @ObservationIgnored private var wachhund: Task<Void, Never>?
    @ObservationIgnored private var letzterFehler: (any Error)?
    @ObservationIgnored private var imVordergrund = true
    /// Die Lieder zur Schlange drüben, nach Kennungen — nur neu geholt, wenn
    /// sich die Schlange ändert.
    @ObservationIgnored private var schlangenlieder: (ids: [String], lieder: [Lied])?
    @ObservationIgnored private var laedtSchlange: [String]?
    /// Weggeklickte Angebote, „Sitzung|Lied" — dasselbe kommt nicht wieder.
    @ObservationIgnored private var abgelehnt = Set<String>()
    /// Befehle an das Gerät, einer nach dem anderen.
    @ObservationIgnored private var folge = Fernbefehlsfolge()
    @ObservationIgnored private var sender: Task<Void, Never>?
    /// Seit wann ``ziel`` das jetzige Gerät ist. Eine Abfrage, die vorher
    /// begann, kennt es nicht — ihre Antwort kann älter sein als die frische
    /// Sitzung, mit der verbunden wurde, und setzte die Stelle zurück.
    @ObservationIgnored private var zielSeit = Date.distantPast

    private var spieler: Spieler? { modell?.spieler }

    // MARK: - Anmelden und Abmelden

    func starten(_ quelle: JellyfinQuelle, modell: Musikmodell) {
        beenden()
        self.quelle = quelle
        self.modell = modell
        modell.spieler.fernsteuern = { [weak self] aktion in self?.senden(aktion) }
        modell.spieler.fernHinweis = { [weak modell] text in modell?.hinweis = text }
        Task { [weak self] in
            await self?.kanalOeffnen()
            await self?.nachsehen()
        }
    }

    /// **Alles beendet sich beim Abmelden**: Kanal, Takt, Zeiger — danach
    /// klopft nichts mehr beim Server an.
    func beenden() {
        abfrage?.cancel(); abfrage = nil
        zeiger?.cancel(); zeiger = nil
        sender?.cancel(); sender = nil
        folge = Fernbefehlsfolge()
        let alt = kanal
        kanal = nil
        Task { await alt?.beenden() }
        spieler?.fernsteuern = nil
        spieler?.fernHinweis = nil
        quelle = nil
        ziel = nil
        geraete = []
        wachhund?.cancel(); wachhund = nil
        wache = Abfragewache()
        stoerung = nil
        letzterFehler = nil
        schlangenlieder = nil
        abgelehnt = []
        blattOffen = false
    }

    // MARK: - Vordergrund und Hintergrund

    /// Beim Öffnen: Kanal wieder auf, nachsehen, ob woanders etwas läuft.
    func vordergrund() {
        imVordergrund = true
        guard quelle != nil else { return }
        Task { [weak self] in
            await self?.kanalOeffnen()
            await self?.nachsehen()
        }
        takten()
    }

    /// **Im Hintergrund nur, solange hier Musik läuft.** Ohne Ton hält iOS
    /// die App ohnehin an, und ein Kanal, der dann still abreißt, sähe für
    /// den Server aus wie ein Gerät, das Befehle annimmt.
    func hintergrund() {
        imVordergrund = false
        takten()
        if spieler?.spielt != true { kanalSchliessen() }
    }

    /// Die Wiedergabe hat sich geändert — im Hintergrund ohne Ton geht der
    /// Kanal zu.
    func wiedergabeGeaendert() {
        if !imVordergrund, spieler?.spielt != true { kanalSchliessen() }
    }

    private func kanalSchliessen() {
        let alt = kanal
        kanal = nil
        Task { await alt?.beenden() }
    }

    /// **Fähigkeiten melden, dann zuhören.** Beides: ohne Meldung bleibt die
    /// Sitzung in Jellyfin-Web grau, ohne Kanal kommen die Befehle nie an.
    private func kanalOeffnen() async {
        guard let quelle, kanal == nil else { return }
        do {
            try await quelle.faehigkeitenMelden()
        } catch {
            Spur.sag("[Connect] Fähigkeiten nicht gemeldet: \(error)")
        }
        guard self.quelle === quelle, kanal == nil,
              let neu = try? await quelle.steuerkanal() else { return }
        guard self.quelle === quelle, kanal == nil else { return }
        kanal = neu
        await neu.starten { [weak self] nachricht in
            Task { @MainActor in self?.empfangen(nachricht) }
        }
    }

    // MARK: - Was andere Geräte von uns wollen

    private func empfangen(_ nachricht: Kanalnachricht) {
        guard case let .auftrag(auftrag) = nachricht, let spieler else { return }
        switch auftrag {
        case let .spielen(ids, ab, stelle, wie):
            Task { await spielenAufBefehl(ids, ab: ab, stelle: stelle, wie: wie) }
            return
        default:
            break
        }
        // Steuern wir selbst ein anderes Gerät, spielt hier nichts, das ein
        // Befehl anhalten oder weiterschalten könnte.
        guard spieler.fern == nil else { return }
        switch auftrag {
        case .spielen: break
        case .pause: spieler.pausieren()
        case .weiter: spieler.abspielen()
        case .umschalten: spieler.umschalten()
        case .stopp: spieler.stoppen()
        case .naechstes: spieler.weiter()
        case .voriges: spieler.zurueck()
        case let .springen(s): spieler.springe(auf: s)
        // Dieselben Sprünge wie Jellyfin-Web: 30 vor, 10 zurück.
        case .vor: spieler.springe(auf: spieler.stelle() + 30)
        case .zurueck: spieler.springe(auf: spieler.stelle() - 10)
        case let .lautstaerke(v): spieler.lautstaerkeVonFern(v)
        case let .stumm(an): spieler.stummVonFern(an)
        case let .wiederholung(w): spieler.wiederholen(w)
        case let .mischen(an): spieler.mischen(an)
        }
    }

    /// Jemand schickt uns eine Schlange (Jellyfin-Web: „Abspielen auf …").
    private func spielenAufBefehl(_ ids: [String], ab: Int, stelle: TimeInterval?,
                                  wie: Fernauftrag.Einreihung) async {
        guard let quelle, let modell else { return }
        let lieder: [Lied]
        do {
            lieder = try await quelle.lieder(ids: ids)
        } catch {
            Spur.sag("[Connect] Lieder für Play nicht geholt: \(error)")
            return
        }
        guard !lieder.isEmpty, self.quelle === quelle else { return }
        let start = Uebergabe.index(von: ab, in: ids, gefunden: lieder)
        let spieler = modell.spieler
        switch wie {
        case .jetzt, .gemischt, .mix:
            // Wer uns etwas schickt, will es hier hören — auch wenn wir
            // gerade ein anderes Gerät steuern.
            if spieler.fern?.art == .sonos {
                _ = await sonos?.abgeben()
            } else if spieler.fern != nil {
                spieler.fernBeenden(lieder: nil, ab: 0, stelle: 0, spielen: false)
                ziel = nil
                takten()
            }
            switch wie {
            case .mix: await modell.sofortmix(.lied(lieder[start]))
            case .gemischt: modell.spielen(lieder, ab: nil, mischen: true, herkunft: nil)
            default: modell.spielen(lieder, ab: start, herkunft: nil, stelle: stelle)
            }
        case .alsNaechstes:
            guard spieler.fern == nil else { return }
            spieler.alsNaechstes(lieder)
        case .hintenAn:
            guard spieler.fern == nil else { return }
            spieler.hintenAn(lieder)
        }
    }

    // MARK: - Geräte fragen

    /// **Im Takt fragen, solange es jemand sieht.** Offen: alle 3 Sekunden;
    /// läuft es drüben: alle 2 — der Stand im Blatt soll folgen.
    ///
    /// **Gestört ruht der Takt fürs Blatt**, bis „Erneut versuchen" kommt —
    /// sonst fragte er weiter, und mit dem Knopf liefen zwei Abfragen
    /// nebeneinander. Läuft die Musik drüben, fragt er weiter: daran hängt,
    /// ob das Gerät noch da ist.
    private func takten() {
        let blatt = blattOffen && wache.lage != .gestoert
        let noetig = quelle != nil && imVordergrund && (blatt || ziel != nil)
        guard noetig else {
            abfrage?.cancel(); abfrage = nil
            zeiger?.cancel(); zeiger = nil
            return
        }
        if abfrage == nil {
            abfrage = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.fragen()
                    let pause: Double = self?.ziel != nil ? 2 : 3
                    try? await Task.sleep(for: .seconds(pause))
                }
            }
        }
        if ziel != nil, zeiger == nil {
            // Die Stelle drüben läuft zwischen zwei Abfragen weiter — hier im
            // Takt der Anzeige.
            zeiger = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, let ziel = self.ziel else { return }
                    self.spieler?.fernZeit(ziel.stelle())
                }
            }
        } else if ziel == nil {
            zeiger?.cancel(); zeiger = nil
        }
    }

    /// „Erneut versuchen" im Blatt: von vorn warten und gleich fragen.
    func erneutFragen() {
        wacheSetzen { $0.vonVorn() }
        stoerung = nil
        letzterFehler = nil
        wachhundStarten()
        Task { [weak self] in await self?.fragen() }
    }

    /// **Der Wachhund** wie in `AirPlayFlaeche` im Player: kam nach der
    /// Frist nichts, ist Schluss mit Platzhaltern.
    private func wachhundStarten() {
        wachhund?.cancel()
        guard quelle != nil, wache.lage == .laedt else { wachhund = nil; return }
        wachhund = Task { [weak self] in
            try? await Task.sleep(for: Abfragewache.frist)
            guard !Task.isCancelled, let self else { return }
            self.wacheSetzen { $0.fristVorbei() }
        }
    }

    /// Ändert die Wache und setzt sie nur, wenn sich etwas ändert — der Takt
    /// fragt alle drei Sekunden, das Blatt soll nicht jedes Mal neu zeichnen.
    private func wacheSetzen(_ aendern: (inout Abfragewache) -> Void) {
        var neu = wache
        aendern(&neu)
        guard neu != wache else { return }
        wache = neu
        if neu.lage == .gestoert {
            stoerung = letzterFehler.map { Stoerung($0) } ?? .keineVerbindung
            Spur.sag("[Connect] Geräteabfrage gestört")
        } else {
            stoerung = nil
        }
        if neu.lage != .laedt { wachhund?.cancel(); wachhund = nil }
        takten()
    }

    /// Läuft gerade eine Abfrage? Takt und „Erneut versuchen" überholen
    /// sich sonst, und die ältere Antwort überschreibt die neuere.
    @ObservationIgnored private var fragtGerade = false

    private func fragen() async {
        guard let quelle, !fragtGerade else { return }
        fragtGerade = true
        defer { fragtGerade = false }
        // Vor der Abfrage: welche eigenen Befehle kann ihre Antwort kennen?
        let marke = ziel.map { (sitzung: $0.sitzungID, marke: $0.marke()) }
        let begonnen = Date()
        let alle: [Musiksitzung]
        do {
            alle = try await quelle.geraete()
        } catch {
            // Abgebrochen (Hintergrund, Blatt zu) ist kein Aussetzer: sonst
            // zählte jedes Wegschalten mitten in einer Abfrage als „Gerät
            // fehlt", und nach dem dritten Mal war es „nicht mehr da".
            if Task.isCancelled || error is CancellationError
                || (error as? JellyfinError)?.urlFehlercode == .cancelled {
                return
            }
            // Still nach außen: ein Aussetzer im Takt ist kein Grund für eine
            // Meldung. Fehlt das Gerät dreimal, gilt es als weg (``Fernstand``).
            Spur.sag("[Connect] Geräte nicht abgefragt: \(error)")
            guard self.quelle === quelle else { return }
            letzterFehler = error
            wacheSetzen { $0.fehlgeschlagen() }
            if var z = ziel, begonnen >= zielSeit {
                let ereignis = z.abgleichen([])
                ziel = z
                if ereignis == .weg { await verloren() }
            }
            return
        }
        guard self.quelle === quelle else { return }
        geraete = alle
        letzterFehler = nil
        wacheSetzen { $0.geantwortet() }
        guard var z = ziel, begonnen >= zielSeit else { return }
        let ereignis = z.abgleichen(alle, marke: marke?.sitzung == z.sitzungID ? marke?.marke : nil)
        ziel = z
        switch ereignis {
        case .gleich: break
        case .stand, .schlange: await spiegeln()
        case .weg: await verloren()
        }
    }

    /// Den Stand drüben dem Spieler zeigen — mit der Schlange, sobald die
    /// Lieder dazu geholt sind.
    private func spiegeln() async {
        guard let z = ziel, let spieler else { return }
        let (ids, ab) = Uebergabe.fenster(z.ids, ab: z.index ?? 0, hoechstens: 500)
        if let bekannt = schlangenlieder, bekannt.ids == ids {
            spieler.fernSpiegeln(z, lieder: bekannt.lieder,
                                 index: Uebergabe.index(von: ab, in: ids, gefunden: bekannt.lieder))
            return
        }
        // Erst das laufende Lied, dann die Schlange, sobald sie da ist.
        // Steht das Lied schon da, bleibt die gezeigte Schlange stehen, bis
        // die neue geladen ist — sonst fiele sie bei jeder Abfrage während
        // des Ladens auf ein Lied zusammen und kehrte dann zurück.
        if spieler.fern?.sitzungID == z.sitzungID, let lied = z.lied,
           spieler.schlange.aktuell?.lied.id == lied.id {
            spieler.fernSpiegeln(z, lieder: spieler.schlange.eintraege.map(\.lied), index: spieler.schlange.position)
        } else {
            spieler.fernSpiegeln(z, lieder: nil, index: nil)
        }
        if !z.schlangeVoll.isEmpty, z.schlangeVoll.map(\.id) == z.ids {
            schlangenlieder = (z.ids, z.schlangeVoll)
        } else {
            guard let quelle, !ids.isEmpty, laedtSchlange != ids else { return }
            laedtSchlange = ids
            defer { laedtSchlange = nil }
            guard let lieder = try? await quelle.lieder(ids: ids), self.quelle === quelle else { return }
            schlangenlieder = (ids, lieder)
        }
        guard let frisch = ziel, frisch.sitzungID == z.sitzungID, let bekannt = schlangenlieder else { return }
        let (fids, fab) = Uebergabe.fenster(frisch.ids, ab: frisch.index ?? 0, hoechstens: 500)
        guard fids == bekannt.ids else { return }
        spieler.fernSpiegeln(frisch, lieder: bekannt.lieder,
                             index: Uebergabe.index(von: fab, in: fids, gefunden: bekannt.lieder))
    }

    /// Das Gerät ist weg: die Schlange steht hier angehalten bereit.
    private func verloren() async {
        guard let z = ziel, let spieler else { return }
        Spur.sag("[Connect] \(z.geraetename) ist weg")
        ziel = nil
        takten()
        let r = z.rueckholung()
        let lieder = await frischeLieder(r?.ids ?? [])
        let ab = r.map { Uebergabe.index(von: $0.ab, in: $0.ids, gefunden: lieder ?? []) } ?? 0
        spieler.fernBeenden(lieder: lieder, ab: ab, stelle: r?.stelle ?? 0, spielen: false)
        modell?.hinweis = String(localized: "\(z.geraetename) ist nicht mehr da. Die Musik steht hier bereit.")
    }

    // MARK: - Hinschicken

    /// **Ein Tipp auf ein Gerät im Blatt.**
    func waehlen(_ s: Musiksitzung) {
        blattOffen = false
        guard ziel?.sitzungID != s.id else { return }
        Task {
            // Läuft es auf Sonos, hält der an, und die Schlange geht von hier
            // hinüber — mit dem Stand, den Sonos zuletzt hatte.
            var vonSonos: (spielte: Bool, stelle: TimeInterval)?
            if spieler?.fern?.art == .sonos, let sonos { vonSonos = await sonos.abgeben() }
            await verbinden(s, vorher: vonSonos)
        }
    }

    /// Übergeben oder nur steuern — ``Uebergabe/art(hierSpielt:hierIstSchlange:dortSpielt:)``.
    /// `vorher`: der Stand eines Sonos-Lautsprechers, der eben abgegeben hat —
    /// die Schlange steht dann hier, angehalten, aber sie lief dort.
    func verbinden(_ gezeigt: Musiksitzung, vorher: (spielte: Bool, stelle: TimeInterval)? = nil) async {
        guard let quelle, let spieler, !beschaeftigt else { return }
        beschaeftigt = true
        defer { beschaeftigt = false }
        modell?.angebot = nil
        // **Frisch fragen, was dort läuft.** Die Zeile im Blatt ist bis zu
        // drei Sekunden alt, ein Angebot Minuten — und an ihr hängt, ob die
        // Schlange von hier hinübergeht und das Laufende drüben ersetzt.
        let s = await frischeSitzung(gezeigt, quelle: quelle)
        guard self.quelle === quelle else { return }

        let hier = spieler.fern == nil
        // Läuft es auf einem anderen Gerät, zählt dessen Schlange als „hier".
        let quellstand: (ids: [String], ab: Int, stelle: TimeInterval, lieder: [Lied])?
        if hier, let ab = spieler.schlange.position {
            quellstand = (spieler.schlange.eintraege.map(\.lied.id), ab, vorher?.stelle ?? spieler.stelle(),
                          spieler.schlange.eintraege.map(\.lied))
        } else if let z = ziel, let r = z.rueckholung() {
            quellstand = (r.ids, r.ab, r.stelle, schlangenlieder?.ids == r.ids ? schlangenlieder!.lieder : [])
        } else {
            quellstand = nil
        }
        let spieltGerade = vorher?.spielte
            ?? (hier ? spieler.spielt : (ziel.map { !$0.angehalten && $0.lied != nil } ?? false))
        let art = Uebergabe.art(hierSpielt: spieltGerade, hierIstSchlange: quellstand != nil,
                                dortSpielt: Uebergabe.dortAktiv(s))
        let anzeige = Fernanzeige(sitzungID: s.id, name: s.geraetename, zeichen: s.zeichen)
        Spur.sag("[Connect] \(s.geraetename): \(art == .uebergeben ? "übergeben" : "steuern")")

        var stand = Fernstand(s)
        if art == .uebergeben, let q = quellstand {
            let (ids, ab) = Uebergabe.fenster(q.ids, ab: q.ab)
            do {
                try await quelle.fern(.spielen(ids: ids, ab: ab, stelle: q.stelle), an: s.id)
            } catch {
                modell?.hinweis = String(localized: "\(s.geraetename) hat nicht reagiert.")
                return
            }
            // Vom einen Gerät zum anderen: das erste hört auf.
            if let alt = ziel, alt.sitzungID != s.id {
                try? await quelle.fern(.stopp, an: alt.sitzungID)
            }
            let lied = q.lieder.indices.contains(q.ab) ? q.lieder[q.ab] : nil
            stand = Fernstand(Musiksitzung(
                id: s.id, benutzerID: s.benutzerID, geraeteID: s.geraeteID, geraetename: s.geraetename,
                programm: s.programm, nimmtBefehle: s.nimmtBefehle, spieltMusik: s.spieltMusik,
                lied: lied, stelle: q.stelle, schlange: ids,
                schlangeneintraege: ids.indices.map { "playlistItem\($0)" },
                eintragID: "playlistItem\(ab)", letzteMeldung: Date()))
            // Bis das Gerät das neue Lied meldet, zählt seine alte Antwort nicht.
            if let lied { stand.erwarten(lied.id) }
            // Die Lieder sind hier schon da — der Ausschnitt, der hinüberging.
            if q.lieder.count == q.ids.count {
                let anfang = q.ab - ab
                schlangenlieder = (ids, Array(q.lieder[anfang ..< anfang + ids.count]))
            }
        } else {
            schlangenlieder = nil
        }
        spieler.fernBeginnen(anzeige)
        // Was an das alte Gerät wartete, gehört nicht zum neuen.
        folge = Fernbefehlsfolge()
        ziel = stand
        zielSeit = Date()
        takten()
        await spiegeln()
    }

    /// **Einen Knopf drüben ausführen** — der Stand folgt sofort
    /// (``Fernstand/vormerken(_:jetzt:)``), die Befehle gehen der Reihe nach
    /// (``Fernbefehlsfolge``), und die Abfrage danach bestätigt ihn.
    ///
    /// „Umschalten" geht als Pause oder Weiter hinaus
    /// (``Fernstand/aufloesen(_:jetzt:)``): ein Umschalter, fünfmal schnell
    /// geschickt, landet nur richtig, wenn jeder ankommt. Vorher schickte
    /// Abspielen nach einer Pause die ganze Schlange neu (`PlayNow`) — drüben
    /// begann sie von vorn, meldete dazwischen kein Lied, und hier ging das
    /// Blatt zu (24.09.).
    private func senden(_ aktion: Fernaktion) {
        guard quelle != nil, var z = ziel else { return }
        let gewollt = z.aufloesen(aktion) ?? spieler?.fernNeuanfang()
        guard let gewollt else { return }
        let nummer = z.vormerken(gewollt)
        ziel = z
        folge.einreihen(gewollt, nummer: nummer)
        Task { await spiegeln() }
        abarbeiten()
    }

    /// Schickt, was in der Folge wartet, einen Befehl nach dem anderen.
    private func abarbeiten() {
        guard sender == nil else { return }
        sender = Task { [weak self] in
            await self?.folgeSenden()
            self?.sender = nil
        }
    }

    private func folgeSenden() async {
        while let quelle, let z = ziel, let befehl = folge.naechster() {
            do {
                try await quelle.fern(befehl.aktion, an: z.sitzungID)
            } catch {
                if !Task.isCancelled { modell?.hinweis = String(localized: "\(z.geraetename) hat nicht reagiert.") }
            }
            let erledigt = folge.fertig() ?? befehl
            guard var frisch = ziel, frisch.sitzungID == z.sitzungID else { continue }
            frisch.erledigt(erledigt.nummer)
            ziel = frisch
        }
        // Nach dem letzten Befehl nachsehen, sobald das Gerät ihn umgesetzt
        // haben kann — statt auf den nächsten Takt zu warten.
        try? await Task.sleep(for: .seconds(Fernstand.nachlauf + 0.1))
        guard !Task.isCancelled, folge.leer else { return }
        await fragen()
    }

    // MARK: - Loslassen

    /// **Nur dieses iPhone löst sich** (Pille weggewischt): nicht mehr fragen,
    /// nichts mehr schicken — drüben läuft es weiter. Zurück kommt eine
    /// Schließung, die die Verbindung wiederherstellt („Rückgängig").
    func lokalLoesen() -> (@MainActor () -> Void)? {
        if spieler?.fern?.art == .sonos { return sonos?.lokalLoesen() }
        guard let z = ziel, let anzeige = spieler?.fern else { return nil }
        sender?.cancel(); sender = nil
        folge = Fernbefehlsfolge()
        ziel = nil
        takten()
        return { [weak self] in
            guard let self, self.ziel == nil, let spieler = self.spieler, spieler.fern == nil else { return }
            spieler.fernBeginnen(anzeige)
            self.ziel = z
            self.zielSeit = Date()
            self.takten()
            Task { await self.spiegeln() }
        }
    }

    // MARK: - Zurückholen

    /// **„Hier weiterhören"**: drüben stoppen, hier mit derselben Schlange
    /// ab derselben Stelle weiter.
    ///
    /// Erst die Lieder holen, dann drüben stoppen — umgekehrt stünde bei
    /// einem Fehler nirgends mehr Musik (dieselbe Reihenfolge wie bei der
    /// Übernahme im Player, Audit 16.09., T1-M7).
    func hierWeiterhoeren() async {
        if spieler?.fern?.art == .sonos {
            await sonos?.hierWeiterhoeren()
            return
        }
        guard let z = ziel else { return }
        await zurueckholen(z)
    }

    /// **Für Sonos**: drüben stoppen, die Schlange hier angehalten bereit —
    /// Sonos spielt sie gleich weiter. Zurück kommt, ob es drüben lief und
    /// an welcher Stelle; `nil`, wenn es nicht geklappt hat.
    func abgeben() async -> (spielte: Bool, stelle: TimeInterval)? {
        guard let z = ziel else { return nil }
        let lief = !z.angehalten && !z.gestoppt && z.lied != nil
        let stelle = z.stelle()
        guard await zurueckholen(z, spielen: false) else { return nil }
        return (lief, stelle)
    }

    /// `spielen`: hier gleich weiter („Hier weiterhören"); sonst steht die
    /// Schlange angehalten da. Zurück kommt, ob sie hier angekommen ist.
    @discardableResult
    private func zurueckholen(_ gemerkt: Fernstand, spielen: Bool = true) async -> Bool {
        guard let quelle, let spieler, !beschaeftigt else { return false }
        beschaeftigt = true
        defer { beschaeftigt = false }
        // **Der frische Stand, nicht der vom letzten Takt**: aus dem
        // Hintergrund zurück oder mit dem Angebot beim Öffnen ist der alte
        // Sekunden bis Minuten her. Ein eigener Befehl, den das Gerät noch
        // nicht bestätigt hat, gilt dabei weiter (``Fernstand/abgleichen(_:marke:jetzt:)``).
        var z = ziel.flatMap { $0.sitzungID == gemerkt.sitzungID ? $0 : nil } ?? gemerkt
        if let alle = try? await quelle.sitzungen(), self.quelle === quelle,
           alle.contains(where: { $0.id == z.sitzungID }) {
            _ = z.abgleichen(alle)
            Spur.sag("[Connect] frisch vor dem Zurückholen: \(z.lied?.titel ?? "nichts") bei \(Int(z.stelle())) s")
        }
        guard self.quelle === quelle else { return false }
        guard let r = z.rueckholung() else {
            // Drüben lief nichts: nur die Verbindung lösen.
            if spieler.fern != nil { spieler.fernBeenden(lieder: nil, ab: 0, stelle: 0, spielen: false) }
            ziel = nil
            takten()
            return true
        }
        let (ids, ab) = Uebergabe.fenster(r.ids, ab: r.ab, hoechstens: 500)
        guard let lieder = await frischeLieder(ids), !lieder.isEmpty else {
            modell?.hinweis = String(localized: "Die Schlange von \(z.geraetename) ließ sich nicht laden.")
            return false
        }
        let start = Uebergabe.index(von: ab, in: ids, gefunden: lieder)
        do {
            try await quelle.fern(.stopp, an: z.sitzungID)
        } catch {
            // Ist das Gerät gar nicht mehr da, gibt es drüben nichts anzuhalten.
            if geraete.contains(where: { $0.id == z.sitzungID }) {
                modell?.hinweis = String(localized: "\(z.geraetename) hat nicht reagiert.")
                return false
            }
        }
        // Die Stelle jetzt, nach dem Stopp — nicht vor dem Laden.
        let stelle = z.stelle()
        if spieler.fern == nil {
            // Aus dem Angebot, ohne verbunden zu sein.
            spieler.fernBeginnen(Fernanzeige(sitzungID: z.sitzungID, name: z.geraetename, zeichen: "iphone"))
        }
        Spur.sag("[Connect] hier weiter: Lied \(start + 1) von \(lieder.count), ab \(Int(stelle)) s")
        ziel = nil
        takten()
        spieler.fernBeenden(lieder: lieder, ab: start, stelle: stelle, spielen: spielen)
        modell?.angebot = nil
        return true
    }

    /// **Die Sitzung, wie sie jetzt ist.** Meldet sie gerade kein Lied, hat
    /// sich aber vor kurzem gemeldet, steht sie womöglich zwischen zwei
    /// Liedern (Jellyfin-Web meldet dazwischen kurz keins) — dann einmal
    /// nachfragen. Ohne Antwort gilt, was gezeigt war.
    private func frischeSitzung(_ s: Musiksitzung, quelle: JellyfinQuelle) async -> Musiksitzung {
        func holen() async -> Musiksitzung? {
            (try? await quelle.sitzungen())?.first { $0.id == s.id }
        }
        guard var frisch = await holen() else { return s }
        if frisch.lied == nil, let meldung = frisch.letzteMeldung,
           (frisch.abgefragt ?? Date()).timeIntervalSince(meldung) < 12 {
            try? await Task.sleep(for: .seconds(1.5))
            frisch = await holen() ?? frisch
        }
        return frisch
    }

    private func frischeLieder(_ ids: [String]) async -> [Lied]? {
        guard let quelle, !ids.isEmpty else { return nil }
        return try? await quelle.lieder(ids: ids)
    }

    // MARK: - Läuft woanders

    /// **Beim Öffnen: läuft auf einem eigenen anderen Gerät gerade Musik?**
    /// Dann ein Angebot, kein Zwang — wer hier nichts tut, dem passiert nichts.
    func nachsehen() async {
        guard let quelle, let spieler, ziel == nil, spieler.fern == nil, !spieler.spielt else { return }
        guard let alle = try? await quelle.sitzungen(), self.quelle === quelle else { return }
        guard let s = Geraeteliste.laeuftWoanders(alle, eigeneGeraeteID: quelle.geraeteID,
                                                  eigeneBenutzerID: quelle.konto.benutzerID,
                                                  programme: Geraeteliste.swiftlyProgramme),
              let lied = s.lied, !abgelehnt.contains("\(s.id)|\(lied.id)"),
              ziel == nil, !spieler.spielt else { return }
        modell?.angebot = Weiterhoerangebot(
            schluessel: "\(s.id)|\(lied.id)",
            titel: String(localized: "Läuft auf \(s.geraetename)"),
            lied: lied, zeichen: s.zeichen, art: .jellyfin(s))
    }

    /// „Hier weiterhören" im Angebot.
    func angebotAnnehmen(_ s: Musiksitzung) async {
        // Frisch fragt ``zurueckholen(_:)`` selbst.
        await zurueckholen(Fernstand(s))
    }

    /// Ein Tipp auf das Angebot selbst: nur verbinden und von hier steuern.
    func angebotSteuern(_ s: Musiksitzung) async {
        await verbinden(s)
    }

    func angebotAblehnen(_ schluessel: String) {
        abgelehnt.insert(schluessel)
    }
}

// MARK: - Zeichen

extension Musiksitzung {
    /// Das Zeichen zum Gerät. **Welches Gerät** es ist, entscheidet
    /// ``geraeteart`` im Paket; welches SF-Symbol dafür steht, ist Sache der
    /// App — wie `geraetezeichen` im Player.
    var zeichen: String {
        switch geraeteart {
        case .telefon: "iphone"
        case .tablet: "ipad"
        case .rechner: "laptopcomputer"
        case .fernseher: "tv"
        case .unbekannt: "hifispeaker"
        }
    }
}

/// **„Läuft auf ‹Gerät› – hier weiterhören?"** — ein Angebot über dem
/// Mini-Player, von Jellyfin (eine andere Sitzung spielt) oder Subsonic
/// (ein anderes Gerät hat eine neuere Schlange abgelegt).
struct Weiterhoerangebot: Identifiable {
    enum Art {
        case jellyfin(Musiksitzung)
        case subsonic(Gespeicherteschlange)
    }

    /// Wiedererkennbar, damit ein weggeklicktes Angebot nicht wiederkommt.
    let schluessel: String
    let titel: String
    let lied: Lied?
    let zeichen: String
    let art: Art

    var id: String { schluessel }
}
