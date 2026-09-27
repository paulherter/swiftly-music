import Foundation
import JellyfinKit
import MusikKit
import OSLog
import SwiftUI

/// Die Bereiche der Leiste unten.
enum Bereich: Int, CaseIterable, Identifiable, Hashable {
    case start, bibliothek, suche, hoerbuecher
    var id: Int { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .start: "Start"
        case .bibliothek: "Bibliothek"
        case .suche: "Suche"
        case .hoerbuecher: "Hörbücher"
        }
    }

    var zeichen: Zeichen {
        switch self {
        case .start: .start
        case .bibliothek: .bibliothek
        case .suche: .suche
        case .hoerbuecher: .hoerbuecher
        }
    }
}

/// **Eine Seite im Stapel eines Bereichs**: eine Sammlung oder das Konto.
///
/// Das Konto kam als Blatt von unten; im Player fährt das Profil von rechts
/// herein (`ProfilRoute` in `Sources/Shared/Routen.swift`) — eine Unterseite,
/// von der man zurückgeht, und der Wisch vom Rand greift.
enum Seite: Hashable {
    case ziel(Ziel)
    case konto
    /// Umsortieren und Entfernen einer Playlist.
    case playlistBearbeiten(Playlist)
    /// Was auf dem Gerät liegt — die angeheftete Zeile in der Bibliothek.
    case geladen
}

/// Wohin ein Tipp führt.
enum Ziel: Hashable {
    case album(Album)
    case kuenstler(Kuenstler)
    case playlist(Playlist)
    case hoerbuch(Hoerbuch)
    /// Die Lieder mit Herz — oben in der Bibliothek angeheftet.
    case lieblingssongs
}

/// **Der Zustand der App**: wer angemeldet ist, welcher Bereich offen, was
/// zuletzt gehört wurde — und der Weg zum Spieler.
///
/// Die Seiten laden ihre Inhalte selbst; hier steht nur, was über Seiten
/// hinweg gilt. Favoriten gehören dazu: wer auf der Albumseite ein Herz setzt,
/// sieht es auch im Wiedergabeblatt, ohne dass eine der beiden neu lädt.
@MainActor
@Observable
final class Musikmodell {

    enum Lage: Equatable { case startet, abgemeldet, angemeldet }

    private(set) var lage: Lage = .startet
    private(set) var quelle: (any Musikquelle)?
    private(set) var zugang: GespeicherterZugang?
    /// Alle Konten auf diesem Gerät, auch auf verschiedenen Servern; eins
    /// davon gilt (``Kontenreihe``, wie der Kontenbund im Player).
    private(set) var konten: Kontenreihe<GespeicherterZugang>?
    /// Warum die Anmeldung wieder da ist — steht dort über den Feldern.
    var anmeldehinweis: String?
    /// Ob es den vierten Bereich gibt. **Beim Start gilt, was beim letzten
    /// Mal galt** (``hoerbuecherschluessel(_:)``) — sonst baute sich die
    /// Leiste kurz nach dem ersten Bild von drei auf vier Reiter um (24.09.; im Probelauf 1,7 s nach dem Start, nach dem Vorhang).
    private(set) var hatHoerbuecher = false
    /// Was auf diesem Gerät zuletzt gespielt wurde, neueste zuerst.
    private(set) var zuletzt: [Sammlungsverweis] = []
    /// Umgeschaltete Favoriten, Kennung → Stand; gilt vor dem Stand der Seite.
    private(set) var favoriten: [String: Bool] = [:]

    var bereich: Bereich = .start
    var pfade: [Bereich: [Seite]] = [:]
    var blattOffen = false
    /// Wo der Mini-Player auf dem Schirm steht, samt Hülle, Titel und
    /// zweiter Zeile — dort beginnt das Blatt, und dorthin kehrt es zurück.
    var miniRahmen: CGRect?
    var miniHuelle: CGRect?
    var miniTitel: CGRect?
    var miniZeile: CGRect?
    /// Was das Handlungsblatt gerade zeigt — „Mehr", langer Druck, Auswahl,
    /// Rückfrage (`Handlungsebene`).
    var handlungen: Handlungsliste?
    /// Die Musikbibliotheken des Servers; mehr als eine, dann gibt es die
    /// Wahl auf der Kontoseite. **`nil` heißt „noch nicht gefragt", nicht
    /// „keine"**: beim Anmelden steht hier der letzte Stand dieses Kontos
    /// (``bibliothekenschluessel(_:)``), sonst schob sich die Zeile auf der
    /// Kontoseite nachträglich ein, sobald die Antwort kam.
    private(set) var bibliotheken: [Musikbibliothek]?
    /// Zählt jeden Wechsel der Bibliothek — Start, Bibliothek und Hörbücher
    /// laden dann neu.
    private(set) var bibliothekswechsel = 0
    /// Die Frage nach einem Namen — neue Playlist, umbenennen.
    var namensfrage: Namensfrage?
    /// Zählt jede Änderung an Playlists — Bibliothek und Seiten laden neu.
    var playlistwechsel = 0
    /// Lieder, die in dieser Sitzung ein Herz bekamen: die Lieblingssongs
    /// zeigen sie sofort, bevor der Server gefragt ist.
    var neueLieblinge: [Lied] = []
    /// Zählt den zweiten Tipp auf „Suche" — dann geht das Feld auf.
    var sucheNochmal = 0
    /// Ein kurzer Hinweis unten („Kommt als Nächstes").
    var hinweis: String?
    /// Zum Hinweis ein „Rückgängig" — solange er steht.
    var rueckgaengig: (@MainActor () -> Void)?

    /// Ein Hinweis mit „Rückgängig", etwa nach dem Entfernen aus einer Playlist.
    func rueckgaengigAnbieten(_ text: String, tun: @escaping @MainActor () -> Void) {
        hinweis = text
        rueckgaengig = tun
    }

    let spieler = Spieler()
    let ablage = Ablage()
    let einstellungen = Musikeinstellungen()
    let netz = Netzwaechter()
    /// Connect über Jellyfin: andere Geräte, hinschicken, steuern.
    let fern = Fernmodell()
    /// Sonos im selben Netz: finden, hinschicken, Lautstärke, Gruppen.
    let sonos = Sonosmodell()
    /// Weiterhören über die Schlange eines Subsonic-Servers.
    let serverschlange = Schlangenabgleich()
    /// „Läuft auf ‹Gerät› – hier weiterhören?" über dem Mini-Player.
    var angebot: Weiterhoerangebot?

    init() {
        // **Was Kanal und Connect erzählen, landet im Systemprotokoll**
        // (Konsole, Filter „Swiftly Music") — sonst verschwänden die Zeilen
        // aus `Spur` ungelesen.
        // Dazu in den Ring für „Protokoll teilen" (``Protokoll``).
        let protokoll = Logger(subsystem: "de.paulherter.swiftly.music", category: "Connect")
        Spur.schreiben = { text in
            protokoll.notice("\(text, privacy: .public)")
            Protokollring.geteilt.anhaengen("[Connect] " + text)
        }
        spieler.ablage = ablage
        spieler.einstellungen = einstellungen
        spieler.verbindung = netz.verbindung
        spieler.sparsam = netz.sparsam
        ablage.verbindung = netz.verbindung
        ablage.nurWLAN = einstellungen.nurWLANLaden
        spieler.geaendert = { [weak self] in
            guard let self else { return }
            self.schlangeVormerken()
            self.radioPruefen()
            self.fern.wiedergabeGeaendert()
            self.serverschlange.vormerken()
            // Spielt hier etwas, ist das Angebot erledigt.
            if self.spieler.spielt { self.angebot = nil }
        }
        spieler.nachtragen = { [weak self] n in self?.nachtragMerken(n) }
        // Ein Blatt „Abspielen auf" für beide: Connect und Sonos fragen, solange es offen ist.
        fern.sonos = sonos
        fern.blattGeaendert = { [weak self] offen in self?.sonos.blattOffen = offen }
        netz.beiWechsel = { [weak self] alt, neu in self?.netzGewechselt(von: alt, zu: neu) }
        netz.beiSparmodus = { [weak self] an in self?.spieler.sparsam = an }
    }

    /// Das Netz hat gewechselt: die nächsten Lieder kommen in der Rate, die
    /// für das neue gilt.
    /// **Ohne Netz** läuft, was geladen ist: der Spieler springt über den
    /// Rest, die Bibliothek zeigt das Geladene, Start verweist dorthin
    /// (Finamps „Auto Offline").
    var offline: Bool { netz.verbindung == .keine }

    private func netzGewechselt(von alt: Verbindung, zu neu: Verbindung) {
        spieler.verbindung = neu
        ablage.verbindung = neu
        ablage.weiterladen()
        guard lage == .angemeldet else { return }
        Protokoll.schreib("[Netz] \(alt) → \(neu)")
        if neu == .keine {
            hinweis = String(localized: "Kein Netz. Es läuft, was geladen ist.")
        } else if alt == .keine {
            Task { await nachtraegeSenden() }
        }
    }

    // MARK: - Bibliothek

    private static func bibliotheksschluessel(_ konto: Kontokennung) -> String {
        "musik.bibliothek.\(konto.ablagename)"
    }

    private static func bibliothekenschluessel(_ konto: Kontokennung) -> String {
        "musik.bibliotheken.\(konto.ablagename)"
    }

    private static func hoerbuecherschluessel(_ konto: Kontokennung) -> String {
        "musik.hoerbuecher.\(konto.ablagename)"
    }

    /// Die gewählte Bibliothek, `nil` für alle.
    var bibliothek: String? { quelle?.bibliothek }

    /// **Nur eine Bibliothek zeigen** — je Konto gemerkt (Feishins Wahl je
    /// Server).
    func bibliothekWaehlen(_ id: String?) {
        guard let quelle else { return }
        quelle.bibliothek = id
        UserDefaults.standard.set(id, forKey: Self.bibliotheksschluessel(quelle.konto))
        bibliothekswechsel += 1
    }

    // MARK: - Radio

    /// Für welches Lied schon Nachschub geholt wurde — einmal je Lied.
    @ObservationIgnored private var radioFuer: String?

    /// **Geht die Schlange zu Ende, kommt Ähnliches dazu** (``Radioregel``).
    private func radioPruefen() {
        guard let quelle, !offline, spieler.schlangeIstEigen, let lied = spieler.aktuell, radioFuer != lied.id,
              Radioregel.brauchtNachschub(spieler.schlange, an: einstellungen.radio) else { return }
        radioFuer = lied.id
        Task { [weak self] in
            guard let vorschlaege = try? await quelle.sofortmix(.lied(lied), anzahl: 50),
                  let self, self.quelle === quelle, self.spieler.aktuell?.id == lied.id else { return }
            let neu = Radioregel.auswahl(vorschlaege, schlange: self.spieler.schlange)
            if !neu.isEmpty { self.spieler.hintenAn(neu) }
        }
    }

    // MARK: - Nachträge

    private func nachtragsschluessel(_ konto: Kontokennung) -> String {
        "musik.nachtraege.\(konto.ablagename)"
    }

    private func nachtraegeLesen(_ konto: Kontokennung) -> Nachtragsliste {
        UserDefaults.standard.data(forKey: nachtragsschluessel(konto))
            .flatMap { try? JSONDecoder().decode(Nachtragsliste.self, from: $0) } ?? Nachtragsliste()
    }

    private func nachtraegeSchreiben(_ liste: Nachtragsliste, _ konto: Kontokennung) {
        UserDefaults.standard.set(try? JSONEncoder().encode(liste), forKey: nachtragsschluessel(konto))
    }

    private func nachtragMerken(_ n: Nachtrag) {
        guard let konto = quelle?.konto else { return }
        var liste = nachtraegeLesen(konto)
        liste.merken(n)
        nachtraegeSchreiben(liste, konto)
    }

    /// Schickt nach, was ohne Netz gehört wurde — der Reihe nach; beim
    /// ersten Fehler ist wieder Schluss bis zum nächsten Mal.
    func nachtraegeSenden() async {
        guard let quelle, !offline else { return }
        let konto = quelle.konto
        for n in nachtraegeLesen(konto).eintraege {
            do {
                try await quelle.scrobbeln(Lied(id: n.liedID, titel: n.titel), beginn: n.zeit, nachtraeglich: true)
            } catch {
                return
            }
            guard self.quelle === quelle else { return }
            var liste = nachtraegeLesen(konto)
            liste.erledigt(n)
            nachtraegeSchreiben(liste, konto)
        }
    }

    /// „Nur über WLAN laden" umgelegt.
    func ladeerlaubnisGeaendert() {
        ablage.nurWLAN = einstellungen.nurWLANLaden
        ablage.weiterladen()
    }

    var benutzername: String { quelle?.benutzername ?? "" }

    /// Kein Blatt offen. Ein Knopf mit langem Druck fragt das vor seiner
    /// Handlung: nach dem langen Druck steht das Blatt schon, und das
    /// Loslassen darf nicht auch noch die Seite öffnen (`LangerDruck`).
    var frei: Bool { handlungen == nil }

    // MARK: - Anmeldung

    /// Beim Start: das zuletzt aktive Konto wiederherstellen — und den Server
    /// fragen, ob die Anmeldung noch gilt.
    ///
    /// Vorher genügte der Eintrag im Schlüsselbund: ein widerrufenes Merkmal
    /// oder ein geändertes Passwort führte nicht zur Anmeldung, sondern in
    /// leere Seiten mit Fehlern, und hinaus ging es nur über die Kontoseite.
    /// Derselbe Fehler, den der Player gemacht hat (`AppModel`, Prüfung
    /// über `sitzungGiltNoch`). Ohne Netz bleibt alles, wie es ist — die
    /// geladene Musik soll auch im Flugzeug laufen (``Anmeldestand``).
    func starten() async {
        guard lage == .startet else { return }
        konten = Zugangsablage.lesen()
        guard let abgelegt = konten?.aktives, let neu = await Quellenbau.quelle(aus: abgelegt) else {
            #if targetEnvironment(simulator)
            if await bildschirmfotoAnmelden() { return }
            #endif
            lage = .abgemeldet
            return
        }
        angemeldet(neu, zugang: abgelegt)
        pruefen(neu, zugang: abgelegt)
    }

    #if targetEnvironment(simulator)
    /// **Screenshots im Simulator**: mit Startargumenten meldet die App sich
    /// selbst an, ohne dass jemand die Maske ausfüllt — nur solange noch kein
    /// Konto abgelegt ist. Denselben Weg wie eine Person an der Maske:
    /// ``Anmeldemodell/verbinden()`` erkennt den Servertyp selbst
    /// (Jellyfin oder Subsonic), dann ``Anmeldemodell/anmelden(_:)`` wie
    /// gewohnt.
    ///
    /// Zugangsdaten kommen ausschließlich aus den Startargumenten
    /// (`-SwiftlyScreenshotServer`, `-SwiftlyScreenshotUser`,
    /// `-SwiftlyScreenshotPass`) und werden nie protokolliert. Nur im
    /// Simulator übersetzt, im Gerätebau nicht enthalten.
    private func bildschirmfotoAnmelden() async -> Bool {
        let werte = UserDefaults.standard
        guard let server = werte.string(forKey: "SwiftlyScreenshotServer"), !server.isEmpty,
              let benutzer = werte.string(forKey: "SwiftlyScreenshotUser"), !benutzer.isEmpty,
              let passwort = werte.string(forKey: "SwiftlyScreenshotPass") else { return false }
        let anmeldung = Anmeldemodell()
        anmeldung.adresse = server
        await anmeldung.verbinden()
        guard anmeldung.erkannt != nil else { return false }
        anmeldung.benutzer = benutzer
        anmeldung.passwort = passwort
        await anmeldung.anmelden(self)
        return quelle != nil
    }
    #endif

    /// Fragt im Hintergrund, ob die Anmeldung noch gilt, und meldet sie ab,
    /// wenn der Server ausdrücklich ablehnt.
    private func pruefen(_ neu: any Musikquelle, zugang: GespeicherterZugang) {
        Task { [weak self] in
            let stand = await neu.anmeldungPruefen()
            Protokoll.schreib("[Konto] Anmeldung geprüft: \(stand)")
            guard stand == .giltNicht, let self, self.quelle === neu else { return }
            await self.ungueltig(zugang)
        }
    }

    /// **Die Anmeldung gilt nicht mehr.** Das Konto geht aus der Reihe; ist
    /// noch eins da, gilt das, sonst geht es zur Anmeldung — mit dem Satz des
    /// Players, warum.
    private func ungueltig(_ zugang: GespeicherterZugang) async {
        let name = zugang.benutzername
        await entfernen(zugang)
        if let weiter = konten?.aktives.benutzername {
            hinweis = String(localized: "Die Anmeldung von \(name) gilt nicht mehr. Jetzt angemeldet als \(weiter).")
        } else {
            anmeldehinweis = String(localized: "Die Anmeldung gilt nicht mehr. Bitte neu anmelden.")
        }
    }

    /// **Zu einem anderen Konto wechseln.** Die Schlange des alten bleibt
    /// liegen und ist wieder da, wenn es zurückgeht.
    func kontoWechseln(zu zugang: GespeicherterZugang) async {
        guard zugang.kontokennung.schluessel != quelle?.konto.schluessel else { return }
        schlangeSichern()
        guard let neu = await Quellenbau.quelle(aus: zugang) else { return }
        angemeldet(neu, zugang: zugang)
        pruefen(neu, zugang: zugang)
    }

    /// **Ein Konto ist angemeldet** — frisch, beim Start oder nach einem
    /// Wechsel. Es kommt in die Reihe der Konten und gilt ab jetzt; war schon
    /// eins da, ist das vorher getrennt (``trennen()``).
    func angemeldet(_ neu: any Musikquelle, zugang: GespeicherterZugang) {
        if quelle != nil { trennen() }
        let reihe = Kontenreihe.aufgenommen(zugang, in: konten)
        if reihe != konten { Zugangsablage.schreiben(reihe) }
        konten = reihe
        Protokoll.schreib("[Konto] angemeldet · \(zugang.serverbeschreibung) · \(neu.konto.server.absoluteString)")
        quelle = neu
        self.zugang = zugang
        spieler.quelle = neu
        ablage.einrichten(konto: neu.konto, quelle: neu)
        zuletzt = Self.zuletztLesen(neu.konto)
        neu.bibliothek = UserDefaults.standard.string(forKey: Self.bibliotheksschluessel(neu.konto))
        bibliotheken = UserDefaults.standard.data(forKey: Self.bibliothekenschluessel(neu.konto))
            .flatMap { try? JSONDecoder().decode([Musikbibliothek].self, from: $0) }
        if let stand = Self.schlangeLesen(neu.konto) { spieler.wiederherstellen(stand) }
        favoriten = [:]
        pfade = [:]
        bereich = .start
        hatHoerbuecher = UserDefaults.standard.bool(forKey: Self.hoerbuecherschluessel(neu.konto))
        lage = .angemeldet
        anmeldehinweis = nil
        angebot = nil
        if let jellyfin = neu as? JellyfinQuelle { fern.starten(jellyfin, modell: self) }
        sonos.starten(neu, modell: self)
        if let subsonic = neu as? any Serverschlange { serverschlange.starten(subsonic, konto: neu.konto, modell: self) }
        Task { [weak self] in await self?.nachtraegeSenden() }
        Task { [weak self] in
            guard let liste = try? await neu.bibliotheken(), let self, self.quelle === neu else { return }
            self.bibliotheken = liste
            UserDefaults.standard.set(try? JSONEncoder().encode(liste),
                                      forKey: Self.bibliothekenschluessel(neu.konto))
            // Eine gewählte Bibliothek, die es nicht mehr gibt, gilt nicht mehr.
            if let id = neu.bibliothek, !liste.contains(where: { $0.id == id }) { self.bibliothekWaehlen(nil) }
        }
        Task { [weak self] in
            let da = await neu.hatHoerbuecher()
            // Ohne Netz sagt die Antwort nichts; es bleibt beim letzten Stand.
            guard let self, self.quelle === neu, !self.offline else { return }
            UserDefaults.standard.set(da, forKey: Self.hoerbuecherschluessel(neu.konto))
            guard da != self.hatHoerbuecher else { return }
            // Hat es sich seit dem letzten Mal geändert, steht der Reiter
            // einfach da oder fehlt — ohne Umbau vor den Augen.
            var ohne = Transaction(animation: nil)
            ohne.disablesAnimations = true
            withTransaction(ohne) { self.hatHoerbuecher = da }
        }
    }

    /// **Abmelden fragt vorher** (BRAND.md §7: wo etwas verloren geht) — das
    /// fragt die Kontoseite; hier geschieht es. **Es trifft nur das aktive
    /// Konto:** sind noch andere da, gilt das nächste (wie `signOut` im
    /// Player); erst nach dem letzten geht es zur Anmeldung.
    func abmelden() async {
        guard let zugang = konten?.aktives else {
            trennen()
            lage = .abgemeldet
            return
        }
        let alt = quelle
        await entfernen(zugang)
        await alt?.abmelden()
    }

    /// Nimmt ein Konto aus der Reihe. War es das aktive, gilt das nächste
    /// oder niemand.
    private func entfernen(_ zugang: GespeicherterZugang) async {
        let warAktiv = zugang.kontokennung.schluessel == quelle?.konto.schluessel
        let rest = konten?.entfernt(zugang.kontokennung)
        konten = rest
        Zugangsablage.schreiben(rest)
        Protokoll.schreib("[Konto] entfernt · \(zugang.serverbeschreibung)")
        guard warAktiv else { return }
        if let naechstes = rest?.aktives, let neu = await Quellenbau.quelle(aus: naechstes) {
            angemeldet(neu, zugang: naechstes)
            pruefen(neu, zugang: naechstes)
        } else {
            trennen()
            lage = .abgemeldet
        }
    }

    // MARK: - Liedtext

    /// **Liedtexte je Lied, höchstens 50** — für Jellyfin und Subsonic
    /// gleich. Vorher fragte die Liedtextansicht bei jedem Öffnen den Server,
    /// auch für das Lied, das gerade läuft. Gemerkt wird auch „keiner da";
    /// ein Fehler nie (``Zwischenspeicher``).
    @ObservationIgnored private var liedtexte = Zwischenspeicher<String, Liedtext?>(grenze: 50)

    /// Was schon geholt ist, ohne zu warten. `.some(nil)`: das Lied hat keinen.
    func gemerkterLiedtext(_ lied: Lied) -> Liedtext?? {
        liedtexte.wert(lied.id)
    }

    /// Der Liedtext, beim ersten Mal vom Server.
    func liedtext(_ lied: Lied) async throws -> Liedtext? {
        if let gemerkt = liedtexte.wert(lied.id) { return gemerkt }
        guard let quelle else { return nil }
        let text = try await quelle.liedtext(lied)
        if self.quelle === quelle { liedtexte.merken(text, fuer: lied.id) }
        return text
    }

    /// Alles, was am angemeldeten Konto hängt, loslassen — vor dem Abmelden
    /// und vor jedem Wechsel.
    private func trennen() {
        fern.beenden()
        sonos.beenden()
        serverschlange.beenden()
        angebot = nil
        spieler.beenden()
        ablage.trennen()
        quelle = nil
        zugang = nil
        spieler.quelle = nil
        zuletzt = []
        favoriten = [:]
        neueLieblinge = []
        pfade = [:]
        blattOffen = false
        handlungen = nil
        bibliotheken = nil
        liedtexte.leeren()
    }

    /// **„Verbindung prüfen"** auf der Kontoseite, wie in den Einstellungen
    /// des Players (`AppModel.verbindungPruefen`): fragt den Server nach sich
    /// selbst und sagt, was zurückkam. Wer erreichbar ist, bekommt gleich die
    /// liegengebliebenen Scrobbles.
    func verbindungPruefen() async -> String {
        guard let quelle else { return String(localized: "Nicht angemeldet.") }
        do {
            let beschreibung: String
            if let j = quelle as? JellyfinQuelle {
                let info = try await j.client.publicSystemInfo()
                beschreibung = "Jellyfin \(info.version ?? "?")"
            } else if let s = quelle as? SubsonicQuelle {
                beschreibung = try await s.client.ping().anzeigename
            } else {
                return ""
            }
            Protokoll.schreib("[Netz] Verbindung geprüft: erreichbar · \(beschreibung)")
            Task { [weak self] in await self?.nachtraegeSenden() }
            return String(localized: "Erreichbar — \(beschreibung)")
        } catch {
            return Fehlertext.lesbar(error)
        }
    }

    // MARK: - Abspielen

    /// Spielt; mit `eintragen` merkt es sich die Sammlung für „Zuletzt
    /// gehört". **Nur Abspielen und Zufall einer Sammlung tragen ein** — auf
    /// ihrer Seite oder an ihrer Kachel (24.09.). Ein angetipptes Lied,
    /// ob in der Suche oder in einer Liste, spielt zwar mit Herkunft, steht
    /// danach aber nicht in „Zuletzt gehört".
    func spielen(_ lieder: [Lied], ab start: Int? = nil, mischen: Bool = false,
                 herkunft: Sammlungsverweis?, eintragen: Bool = false, stelle: TimeInterval? = nil) {
        guard !lieder.isEmpty else { return }
        if eintragen, let herkunft { merken(herkunft) }
        angebot = nil
        spieler.spiele(lieder, ab: start, mischen: mischen, herkunft: herkunft, stelle: stelle)
    }

    // MARK: - Weiterhören

    /// Die App kommt nach vorn oder geht nach hinten.
    func phaseGewechselt(aktiv: Bool) {
        if aktiv {
            fern.vordergrund()
            sonos.vordergrund()
            Task { await serverschlange.nachsehen() }
        } else {
            schlangeSichern()
            fern.hintergrund()
            sonos.hintergrund()
            serverschlange.hintergrund()
        }
    }

    /// „Hier weiterhören" im Angebot.
    func angebotAnnehmen() {
        guard let a = angebot else { return }
        angebot = nil
        switch a.art {
        case let .jellyfin(s): Task { await fern.angebotAnnehmen(s) }
        case let .subsonic(server): serverschlange.annehmen(server)
        }
    }

    /// Ein Tipp auf das Angebot selbst: bei Jellyfin von hier aus steuern.
    func angebotSteuern() {
        guard let a = angebot, case let .jellyfin(s) = a.art else { return }
        angebot = nil
        Task { await fern.angebotSteuern(s) }
    }

    func angebotAblehnen() {
        guard let a = angebot else { return }
        fern.angebotAblehnen(a.schluessel)
        angebot = nil
    }

    func alsNaechstes(_ lieder: [Lied]) {
        guard !lieder.isEmpty else { return }
        spieler.alsNaechstes(lieder)
        hinweis = String(localized: "Kommt als Nächstes.")
    }

    func hintenAn(_ lieder: [Lied]) {
        guard !lieder.isEmpty else { return }
        spieler.hintenAn(lieder)
        hinweis = String(localized: "Steht jetzt hinten in der Schlange.")
    }

    /// Spielt einen Sofortmix; ein Fehler steht als Hinweis unten.
    func sofortmix(_ ziel: Mixziel, herkunft: Sammlungsverweis? = nil) async {
        guard let quelle else { return }
        do {
            let lieder = try await quelle.sofortmix(ziel, anzahl: 50)
            guard !lieder.isEmpty else {
                hinweis = String(localized: "Für diesen Mix hat der Server nichts gefunden.")
                return
            }
            spielen(lieder, ab: 0, herkunft: herkunft)
        } catch {
            hinweis = Fehlertext.lesbar(error)
        }
    }

    // MARK: - Sammlungen

    /// Die Lieder einer Sammlung — vom Server, und ohne Netz aus der Ablage,
    /// wenn sie geladen ist (`VERHALTEN.md` H8: ohne auf den Server zu warten,
    /// den es im Flugzeug nicht gibt).
    func lieder(_ ziel: Ziel) async -> [Lied]? {
        guard let quelle else { return nil }
        do {
            switch ziel {
            case let .album(a): return try await quelle.album(a.id).lieder
            case let .playlist(p): return try await quelle.playlist(p.id).lieder
            case let .kuenstler(k): return try await quelle.alleLieder(von: k)
            case let .hoerbuch(h): return try await quelle.hoerbuch(h.id).teile
            case .lieblingssongs: return try await quelle.lieblingssongs()
            }
        } catch {
            if let geladen = ablage.verzeichnis.sammlungen[Self.verweis(ziel).id]?.lieder, !geladen.isEmpty {
                return geladen
            }
            hinweis = Fehlertext.lesbar(error)
            return nil
        }
    }

    func abspielen(_ ziel: Ziel, mischen: Bool = false) async {
        guard let lieder = await lieder(ziel) else { return }
        spielen(lieder, ab: mischen ? nil : 0, mischen: mischen, herkunft: Self.verweis(ziel), eintragen: true)
    }

    func alsNaechstes(_ ziel: Ziel) async {
        guard let lieder = await lieder(ziel) else { return }
        alsNaechstes(lieder)
    }

    func hintenAn(_ ziel: Ziel) async {
        guard let lieder = await lieder(ziel) else { return }
        hintenAn(lieder)
    }

    static func verweis(_ ziel: Ziel) -> Sammlungsverweis {
        switch ziel {
        case let .album(a): Sammlungsverweis(a)
        case let .kuenstler(k): Sammlungsverweis(k)
        case let .playlist(p): Sammlungsverweis(p)
        case let .hoerbuch(h): Sammlungsverweis(h)
        case .lieblingssongs:
            Sammlungsverweis(art: .playlist, kennung: Self.lieblingskennung,
                             titel: String(localized: "Lieblingssongs"), bild: nil)
        }
    }

    // MARK: - Zuletzt gehört

    func merken(_ verweis: Sammlungsverweis) {
        var neu = verweis
        neu.zeit = Date()
        zuletzt = Zuletztgehoert.merken(neu, in: zuletzt)
        guard let konto = quelle?.konto else { return }
        Self.zuletztSchreiben(zuletzt, konto)
    }

    private static func zuletztSchluessel(_ konto: Kontokennung) -> String {
        "musik.zuletzt.\(konto.ablagename)"
    }

    private static func zuletztLesen(_ konto: Kontokennung) -> [Sammlungsverweis] {
        guard let daten = UserDefaults.standard.data(forKey: zuletztSchluessel(konto)),
              let liste = try? JSONDecoder().decode([Vielleicht<Sammlungsverweis>].self, from: daten)
        else { return [] }
        // Was von früher stammt und nicht hineingehört (Singles, EPs,
        // Hörbücher), fällt beim Laden heraus.
        return Zuletztgehoert.bereinigt(liste.compactMap(\.wert))
    }

    private static func zuletztSchreiben(_ liste: [Sammlungsverweis], _ konto: Kontokennung) {
        guard let daten = try? JSONEncoder().encode(liste) else { return }
        UserDefaults.standard.set(daten, forKey: zuletztSchluessel(konto))
    }

    // MARK: - Schlange über den Neustart

    @ObservationIgnored private var sicherung: Task<Void, Never>?

    /// Ablegen, eine Sekunde nach der letzten Änderung — wer drei Lieder
    /// hintereinander anstellt, schreibt einmal.
    private func schlangeVormerken() {
        sicherung?.cancel()
        sicherung = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.schlangeSichern()
        }
    }

    /// Sofort ablegen — beim Wechsel in den Hintergrund, mit der Stelle.
    ///
    /// Während Connect bleibt die Datei, wie sie ist: die Schlange hier ist
    /// die gespiegelte des anderen Geräts (``Spieler/schlangenstand()``).
    func schlangeSichern() {
        // Bei Sonos ist die Schlange hier die eigene — sie wird abgelegt.
        guard spieler.schlangeIstEigen else { return }
        guard let konto = quelle?.konto, let datei = Self.schlangendatei(konto) else { return }
        guard let stand = spieler.schlangenstand() else {
            try? FileManager.default.removeItem(at: datei)
            return
        }
        let daten = try? JSONEncoder().encode(stand)
        Task.detached(priority: .utility) { try? daten?.write(to: datei, options: .atomic) }
    }

    private static func schlangendatei(_ konto: Kontokennung) -> URL? {
        guard let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let ordner = basis.appendingPathComponent("Musik", isDirectory: true)
            .appendingPathComponent(konto.ablagename, isDirectory: true)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return ordner.appendingPathComponent("schlange.json")
    }

    private static func schlangeLesen(_ konto: Kontokennung) -> Schlangenstand? {
        guard let datei = schlangendatei(konto), let daten = try? Data(contentsOf: datei) else { return nil }
        return try? JSONDecoder().decode(Schlangenstand.self, from: daten)
    }

    // MARK: - Favoriten

    func istFavorit(_ id: String, sonst: Bool) -> Bool {
        favoriten[id] ?? sonst
    }

    /// **Schaltet sofort um** (`VERHALTEN.md` D6) und nimmt es zurück, wenn
    /// der Server ablehnt.
    /// Die Kennung der Lieblingssongs, wo eine Sammlung eine braucht.
    static let lieblingskennung = "lieblingssongs"

    /// `lied`: das Lied selbst, wenn es eins ist — dann steht es sofort in
    /// den Lieblingssongs.
    ///
    /// Beim Druck ein leichter Ruck, wie beim Merken im Player
    /// (`BrowseViews`, `Stil.ruck(.leicht)`) — die Rückmeldung gehört zum
    /// Finger, nicht zur Antwort des Servers.
    func favoritSetzen(_ ziel: Favoritziel, id: String, an: Bool, lied: Lied? = nil) {
        Musikstil.ruck(.leicht)
        let vorher = favoriten[id]
        favoriten[id] = an
        if let lied {
            neueLieblinge.removeAll { $0.id == lied.id }
            if an { neueLieblinge.insert(lied, at: 0) }
        }
        if var lied = spieler.aktuell, lied.id == id {
            lied.favorit = an
            spieler.aktualisieren(lied)
        }
        guard let quelle else { return }
        Task { [weak self] in
            do {
                try await quelle.favorit(ziel, an: an)
            } catch {
                guard let self else { return }
                self.favoriten[id] = vorher
                self.hinweis = Fehlertext.lesbar(error)
            }
        }
    }

    /// **Viele Lieder auf einmal** zu den Lieblingssongs oder heraus („Zu
    /// Playlist hinzufügen", ``Lieblingsauswahl``): sofort in der App, dann
    /// in Bündeln zum Server. Lehnt er ab, springt alles zurück. Gibt zurück,
    /// ob der Server es genommen hat.
    func favoritenSetzen(_ lieder: [Lied], an: Bool) async -> Bool {
        guard !lieder.isEmpty else { return true }
        Musikstil.ruck(.leicht)
        let ids = Set(lieder.map(\.id))
        let vorher = Dictionary(lieder.map { ($0.id, favoriten[$0.id]) }, uniquingKeysWith: { a, _ in a })
        let vorherNeu = neueLieblinge
        let vorherLied = spieler.aktuell
        for id in ids { favoriten[id] = an }
        neueLieblinge.removeAll { ids.contains($0.id) }
        if an { neueLieblinge.insert(contentsOf: lieder.filter { ids.contains($0.id) }, at: 0) }
        if var lied = spieler.aktuell, ids.contains(lied.id) {
            lied.favorit = an
            spieler.aktualisieren(lied)
        }
        guard let quelle else { return false }
        do {
            try await quelle.lieblingeSetzen(Array(vorher.keys), an: an)
            return true
        } catch {
            for (id, wert) in vorher { favoriten[id] = wert }
            neueLieblinge = vorherNeu
            if let vorherLied, spieler.aktuell?.id == vorherLied.id { spieler.aktualisieren(vorherLied) }
            hinweis = Fehlertext.lesbar(error)
            return false
        }
    }

    // MARK: - Wege

    func oeffnen(_ ziel: Ziel) {
        pfade[bereich, default: []].append(.ziel(ziel))
    }

    /// **Eine Single spielt, statt eine Seite mit einer Zeile zu öffnen**;
    /// ein Album oder eine EP geht auf.
    func albumTippen(_ album: Album) {
        if album.istSingle {
            Task { await abspielen(.album(album)) }
        } else {
            oeffnen(.album(album))
        }
    }

    /// Das Konto, von rechts — im Bereich, in dem man gerade ist. **Liegt es
    /// dort schon im Stapel, geht es dorthin zurück** statt ein zweites Mal
    /// hinauf (`zumProfil()` in `HauptView`).
    func kontoOeffnen() {
        var pfad = pfade[bereich] ?? []
        if let i = pfad.lastIndex(of: .konto) {
            pfad.removeSubrange((i + 1)...)
        } else {
            pfad.append(.konto)
        }
        pfade[bereich] = pfad
    }

    /// Aus dem Wiedergabeblatt: Blatt zu, Seite auf.
    func oeffnenAusBlatt(_ ziel: Ziel) {
        blattOffen = false
        oeffnen(ziel)
    }

    /// Die Adresse einer Hülle: die abgelegte, wenn es eine gibt, sonst die
    /// vom Server in einer der festen Größen.
    func bildadresse(_ bild: Bildbezug?, punkte: CGFloat) -> URL? {
        guard let bild else { return nil }
        if let lokal = ablage.lokalesBild(bild) { return lokal }
        return quelle?.bildadresse(bild, kante: Bildlager.stufe(punkte: punkte))
    }

    func heldbildadresse(_ bild: Bildbezug?, breite: CGFloat) -> URL? {
        guard let bild else { return nil }
        if let lokal = ablage.lokalesBild(bild) { return lokal }
        return quelle?.heldbildadresse(bild, breite: Bildlager.stufe(punkte: breite))
    }
}

/// **Künstler zum Lesen**: „A, B und C" in der Sprache der App — nie der
/// rohe Tag des Servers (`Kuenstlernamen` in MusikKit).
enum Musiksprache {
    static let gebiet = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
}

extension Lied {
    var kuenstlerzeile: String? { Kuenstlernamen.zeile(kuenstlernamen, sprache: Musiksprache.gebiet) }
    /// Der erste Künstler — dorthin führt ein Tipp auf die Zeile.
    var ersterKuenstler: String? { kuenstlernamen.first }
}

extension Album {
    var kuenstlerzeile: String? { Kuenstlernamen.zeile(kuenstlernamen, sprache: Musiksprache.gebiet) }
    /// „Album", „Single", „EP" — was es ist (``Veroeffentlichung``).
    var artname: String {
        switch Veroeffentlichung.art(self) {
        case .single: String(localized: "Single")
        case .ep: String(localized: "EP")
        case .live: String(localized: "Live")
        case .album, .zusammenstellung: String(localized: "Album")
        }
    }
    var istSingle: Bool { Veroeffentlichung.istSingle(self) }
}

/// Ein Listeneintrag, der beim Lesen nicht wirft — eine kaputte Zeile in
/// „Zuletzt gehört" nimmt nicht die ganze Liste mit.
struct Vielleicht<T: Decodable>: Decodable {
    let wert: T?
    init(from decoder: any Decoder) throws { wert = try? T(from: decoder) }
}
