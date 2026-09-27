import Foundation
import JellyfinKit

// MARK: - Was wir einem anderen Gerät sagen

/// **Ein Befehl an ein anderes Gerät** — was die Knöpfe im Blatt und im
/// Mini-Player auslösen, solange die Wiedergabe dort läuft.
public enum Fernaktion: Sendable, Equatable {
    case pause
    case weiter
    case umschalten
    case stopp
    case naechstes
    case voriges
    /// Absolute Stelle in Sekunden.
    case springen(TimeInterval)
    case wiederholung(Warteschlange.Wiederholung)
    case mischen(Bool)
    /// Eine Schlange dort spielen, ab `ab`, an der Stelle `stelle`.
    case spielen(ids: [String], ab: Int, stelle: TimeInterval)
    case alsNaechstes([String])
    case hintenAn([String])
}

/// Pfad, Abfrage und Rumpf eines Befehls — ohne Netz prüfbar.
public struct Fernanfrage: Sendable, Equatable {
    public let pfad: String
    public let abfrage: [URLQueryItem]
    public let rumpf: Data?
}

public enum Fernbedienung {

    /// **Jellyfins Wege für jeden Befehl.**
    ///
    /// - Wiedergabebefehle: `POST /Sessions/{id}/Playing/{Befehl}` —
    ///   `PlaystateCommand` in Jellyfins Schreibweise.
    /// - Wiederholen und Mischen: `POST /Sessions/{id}/Command` mit einem
    ///   `GeneralCommand` im Rumpf, dieselben Namen, die wir selbst annehmen
    ///   (``Kanalnachricht``).
    /// - Eine Schlange: `POST /Sessions/{id}/Playing` mit `itemIds` als
    ///   Komma-Liste in der Adresse — deshalb ``Uebergabe/fenster(_:ab:hoechstens:)``.
    public static func anfrage(_ aktion: Fernaktion, an sitzung: String) -> Fernanfrage {
        let basis = "Sessions/\(sitzung)/Playing"
        switch aktion {
        case .pause: return Fernanfrage(pfad: basis + "/Pause", abfrage: [], rumpf: nil)
        case .weiter: return Fernanfrage(pfad: basis + "/Unpause", abfrage: [], rumpf: nil)
        case .umschalten: return Fernanfrage(pfad: basis + "/PlayPause", abfrage: [], rumpf: nil)
        case .stopp: return Fernanfrage(pfad: basis + "/Stop", abfrage: [], rumpf: nil)
        case .naechstes: return Fernanfrage(pfad: basis + "/NextTrack", abfrage: [], rumpf: nil)
        case .voriges: return Fernanfrage(pfad: basis + "/PreviousTrack", abfrage: [], rumpf: nil)
        case let .springen(s):
            return Fernanfrage(pfad: basis + "/Seek",
                               abfrage: [.init(name: "seekPositionTicks", value: String(ticks(s)))],
                               rumpf: nil)
        case let .wiederholung(w):
            let wert = switch w {
            case .aus: "RepeatNone"
            case .alles: "RepeatAll"
            case .eines: "RepeatOne"
            }
            return befehl(sitzung, "SetRepeatMode", ["RepeatMode": wert])
        case let .mischen(an):
            return befehl(sitzung, "SetShuffleQueue", ["ShuffleMode": an ? "Shuffle" : "Sorted"])
        case let .spielen(ids, ab, stelle):
            let (teil, start) = Uebergabe.fenster(ids, ab: ab)
            var werte: [URLQueryItem] = [
                .init(name: "playCommand", value: "PlayNow"),
                .init(name: "itemIds", value: teil.joined(separator: ",")),
                .init(name: "startIndex", value: String(start)),
            ]
            if stelle > 0 { werte.append(.init(name: "startPositionTicks", value: String(ticks(stelle)))) }
            return Fernanfrage(pfad: basis, abfrage: werte, rumpf: nil)
        case let .alsNaechstes(ids):
            return Fernanfrage(pfad: basis, abfrage: [
                .init(name: "playCommand", value: "PlayNext"),
                .init(name: "itemIds", value: ids.prefix(Uebergabe.hoechstens).joined(separator: ",")),
            ], rumpf: nil)
        case let .hintenAn(ids):
            return Fernanfrage(pfad: basis, abfrage: [
                .init(name: "playCommand", value: "PlayLast"),
                .init(name: "itemIds", value: ids.prefix(Uebergabe.hoechstens).joined(separator: ",")),
            ], rumpf: nil)
        }
    }

    private static func befehl(_ sitzung: String, _ name: String, _ werte: [String: String]) -> Fernanfrage {
        let rumpf = try? JSONSerialization.data(withJSONObject: ["Name": name, "Arguments": werte],
                                                options: [.sortedKeys])
        return Fernanfrage(pfad: "Sessions/\(sitzung)/Command", abfrage: [], rumpf: rumpf)
    }

    static func ticks(_ sekunden: TimeInterval) -> Int64 {
        Int64((max(0, sekunden) * 10_000_000).rounded())
    }
}

// MARK: - Übergeben

public enum Uebergabe {

    /// **Höchstens 200 Lieder gehen mit.** Die Kennungen stehen in der
    /// Adresse, und davor sitzt oft ein Vorposten, der Adresszeilen über
    /// 8 KB ablehnt (nginx, Kestrel). 200 Kennungen zu 33 Zeichen sind 6,6 KB.
    public static let hoechstens = 200
    /// Wie viel von dem, was schon lief, mitgeht — für „Zurück" drüben.
    static let rueckblick = 20

    /// Der Ausschnitt einer langen Schlange um das laufende Lied, und wo es
    /// darin steht. Was kommt, hat Vorrang vor dem, was lief.
    public static func fenster(_ ids: [String], ab: Int, hoechstens: Int = hoechstens) -> (ids: [String], ab: Int) {
        guard !ids.isEmpty, hoechstens > 0 else { return ([], 0) }
        let ab = min(max(ab, 0), ids.count - 1)
        guard ids.count > hoechstens else { return (ids, ab) }
        let anfang = max(0, min(ab - rueckblick, ids.count - hoechstens))
        let ende = min(ids.count, anfang + hoechstens)
        return (Array(ids[anfang ..< ende]), ab - anfang)
    }

    /// **Wo das Lied `ab` steht, wenn nicht alle Kennungen ein Lied ergaben**
    /// (gelöscht, keine Rechte). Fehlt das Lied selbst, geht es mit dem
    /// nächsten weiter, das es noch gibt.
    public static func index(von ab: Int, in ids: [String], gefunden: [Lied]) -> Int {
        guard !gefunden.isEmpty else { return 0 }
        let da = Set(gefunden.map(\.id))
        let davor = ids.prefix(max(0, ab)).filter { da.contains($0) }.count
        return min(davor, gefunden.count - 1)
    }

    /// Was ein Tipp auf ein Gerät bedeutet.
    public enum Art: Sendable, Equatable {
        /// Die Schlange von hier dorthin schicken und hier anhalten.
        case uebergeben
        /// Nur steuern, was dort schon läuft.
        case steuern
    }

    /// **Spielt hier etwas, geht es mit.** Sonst: läuft dort etwas, wird es
    /// gesteuert; läuft nirgends etwas, geht die angehaltene Schlange von
    /// hier hinüber — so wie bei Spotify.
    public static func art(hierSpielt: Bool, hierIstSchlange: Bool, dortSpielt: Bool) -> Art {
        if hierSpielt { return .uebergeben }
        if dortSpielt { return .steuern }
        return hierIstSchlange ? .uebergeben : .steuern
    }

    /// So lange nach einer Pause zählt ein Lied drüben noch als das, woran
    /// jemand gerade ist.
    public static let pausenfrist: TimeInterval = 600

    /// **Ist drüben etwas, das man steuern will, statt es zu überschreiben?**
    /// Ein Lied, das spielt oder vor kurzem angehalten wurde. Vorher zählte
    /// nur „spielt" aus der Zeile im Blatt — die ist bis zu drei Sekunden
    /// alt, und zwischen zwei Liedern meldet Jellyfin-Web kurz keins. Dann
    /// ging die angehaltene Schlange von hier hinüber und ersetzte, was dort
    /// lief. Die Sitzung muss deshalb frisch abgefragt sein.
    public static func dortAktiv(_ s: Musiksitzung, jetzt: Date = Date()) -> Bool {
        guard s.lied != nil else { return false }
        guard s.angehalten, let seit = s.pausiertSeit else { return true }
        return (s.abgefragt ?? jetzt).timeIntervalSince(seit) <= pausenfrist
    }
}

// MARK: - Was dort läuft

/// **Der Stand eines anderen Geräts, wie Blatt und Mini-Player ihn zeigen.**
///
/// Drei Dinge machen ihn mehr als eine Kopie der letzten Abfrage:
///
/// 1. **Die Stelle läuft weiter — ab der Abfrage, nicht ab der Meldung.**
///    Jellyfin-Web meldet sich nur alle 10 Sekunden, aber der Server zählt
///    `PositionTicks` dazwischen selbst weiter, jede volle Sekunde um eine
///    (`SessionInfo.StartAutomaticProgress`), ohne `LastPlaybackCheckIn`
///    anzufassen. Vorher rechnete der Stand ab der Meldung noch einmal
///    dieselben Sekunden dazu: bis zu 10 s zu weit, und bei jeder echten
///    Meldung sprang die Anzeige zurück (24.09.: „Hin- und
///    Herspringen"). Jetzt gilt die Stelle zur Zeit der Abfrage
///    (``Musiksitzung/abgefragt``) plus dem Bruchteil der angefangenen
///    Sekunde (``verzug(_:jetzt:)``); Abweichungen unter ``toleranz`` setzen
///    die eigene Rechnung nicht neu.
/// 2. **Ein eigener Befehl gilt sofort, und keine Abfrage überholt ihn.**
///    Auf Pause getippt, zeigt der Knopf sofort Abspielen. Jeder Befehl
///    bekommt eine Folgenummer (``befehlsnummer``); eine Abfrage darf Lauf,
///    Stelle und Schalter erst wieder setzen, wenn sie **nach** dem letzten
///    erledigten Befehl und seinem ``nachlauf`` begonnen hat
///    (``marke(jetzt:)``). Eine Zeitfrist allein reichte nicht: bei fünf
///    schnellen Tipps kam die Antwort auf den dritten nach der Frist des
///    ersten und schaltete den Knopf zurück (24.09.).
/// 3. **Die Schlange zählt nur, wenn das laufende Lied darin steht**
///    (``Musiksitzung/index``) — sonst ist es eine alte, und der Stand
///    kennt nur das laufende Lied.
/// 4. **Ein Gerät, das kurz nichts meldet, verliert sein Lied nicht.**
///    Jellyfin-Web meldet beim Umschalten und nach einem Stopp für einen
///    Takt kein `NowPlayingItem`. Stünde dann hier keins, ginge der
///    Mini-Player weg und das offene Blatt zu. Das Lied bleibt stehen,
///    angehalten (``gestoppt``); Abspielen fängt die Schlange dort neu an.
public struct Fernstand: Sendable, Equatable {

    public let sitzungID: String
    public private(set) var geraetename: String
    public private(set) var geraeteart: Musiksitzung.Geraeteart
    public private(set) var lied: Lied?
    public private(set) var angehalten: Bool
    public private(set) var wiederholung: Warteschlange.Wiederholung
    public private(set) var gemischt: Bool
    /// Die Schlange dort, als Kennungen, und wo das laufende Lied steht.
    public private(set) var ids: [String]
    public private(set) var index: Int?
    public private(set) var schlangeVoll: [Lied]
    /// Das Gerät meldet kein Lied mehr — gezeigt wird das letzte, angehalten.
    public private(set) var gestoppt = false
    /// Die Folgenummer des letzten eigenen Befehls.
    public private(set) var befehlsnummer = 0
    private var stelleBeiBezug: TimeInterval
    private var bezug: Date
    /// Bis zu welcher Nummer die Befehle beim Server angekommen sind.
    private var erledigtBis = 0
    /// Nach dem letzten erledigten Befehl: bis dahin darf das Gerät noch den
    /// alten Stand melden.
    private var ruheBis: Date?
    private var letzterBefehl: Date?
    /// Wie oft hintereinander die Sitzung in der Abfrage fehlte.
    private var fehlt = 0
    /// Nach dem Übergeben: dieses Lied soll drüben laufen.
    private var erwartung: Erwartung?
    /// Die zuletzt gemeldete Stelle, roh — kommt dieselbe wieder, hat das
    /// Gerät nichts Neues gesagt.
    private var gemeldet: TimeInterval?

    private struct Erwartung: Sendable, Equatable {
        let lied: String
        let bis: Date
    }

    /// So lange darf ein Gerät nach dem Übergeben noch sein altes Lied melden.
    public static let uebergabefrist: TimeInterval = 8

    /// **Nach einem erledigten Befehl**: so lange braucht das Gerät, bis der
    /// Server seinen neuen Stand kennt — der Server reicht den Befehl über
    /// den Kanal weiter, das Gerät führt ihn aus und meldet sich erst dann.
    public static let nachlauf: TimeInterval = 2
    /// **Höchstens so lange** nach dem letzten Befehl zählt er mehr als die
    /// Abfrage — auch wenn seine Antwort nie kam.
    public static let vorrang: TimeInterval = 8
    /// So oft darf die Sitzung fehlen, bevor sie als weg gilt — ein
    /// einzelner Aussetzer des Servers soll die Verbindung nicht trennen.
    public static let geduld = 3
    /// Weiter als so lange rechnet die Stelle nicht über eine Abfrage hinaus.
    static let hoechstesAlter: TimeInterval = 60
    /// So weit darf eine Abfrage von der eigenen Rechnung abweichen, ohne
    /// dass die Anzeige springt — die Schätzung selbst liegt darunter.
    public static let toleranz: TimeInterval = 0.75

    public init(_ s: Musiksitzung, jetzt: Date = Date()) {
        sitzungID = s.id
        geraetename = s.geraetename
        geraeteart = s.geraeteart
        lied = s.lied
        angehalten = s.angehalten
        wiederholung = s.wiederholung
        gemischt = s.gemischt
        let schlange = Self.schlange(s)
        ids = schlange.ids
        index = schlange.index
        schlangeVoll = schlange.voll
        stelleBeiBezug = s.stelle + Self.verzug(s, jetzt: jetzt)
        bezug = s.abgefragt ?? jetzt
        gemeldet = s.stelle
    }

    /// **Die Schlange, die gilt**: die gemeldete, wenn das laufende Lied an
    /// seinem Eintrag darin steht; sonst nur das Lied selbst. Ohne Lied
    /// (gestoppt) die gemeldete — die kam mit der Stoppmeldung.
    static func schlange(_ s: Musiksitzung) -> (ids: [String], index: Int?, voll: [Lied]) {
        guard let lied = s.lied else { return (s.schlange, s.index, s.schlangeVoll) }
        guard !s.schlange.isEmpty, let i = s.index else { return ([lied.id], 0, []) }
        return (s.schlange, i, s.schlangeVoll.map(\.id) == s.schlange ? s.schlangeVoll : [])
    }

    /// **Wie weit die Stelle über `PositionTicks` hinaus ist.** Der Server
    /// zählt nur volle Sekunden nach der letzten Meldung; was von der
    /// angefangenen Sekunde schon um ist, fehlt ihm. Ohne Meldezeit oder
    /// angehalten: nichts.
    static func verzug(_ s: Musiksitzung, jetzt: Date) -> TimeInterval {
        guard !s.angehalten, s.lied != nil, let meldung = s.letzteMeldung else { return 0 }
        let alter = (s.abgefragt ?? jetzt).timeIntervalSince(meldung)
        guard alter.isFinite else { return 0 }
        return alter - alter.rounded(.down)
    }

    /// Die Stelle jetzt — weitergerechnet, solange es spielt, nie über das Ende.
    public func stelle(jetzt: Date = Date()) -> TimeInterval {
        var s = stelleBeiBezug
        if !angehalten, lied != nil {
            s += min(max(jetzt.timeIntervalSince(bezug), 0), Self.hoechstesAlter)
        }
        if let dauer = lied?.dauer { s = min(s, dauer) }
        return max(0, s)
    }

    public var dauer: TimeInterval? { lied?.dauer }

    /// **Spielt es drüben gerade?** Ein Lied, nicht angehalten, nicht
    /// gestoppt — danach richtet sich bei Sonos die Stille, die die App auf
    /// dem Sperrbildschirm als laufend zeigt (`Sonosstille`).
    public var laeuft: Bool { lied != nil && !angehalten && !gestoppt }

    /// Was eine neue Abfrage geändert hat.
    public enum Ereignis: Sendable, Equatable {
        case gleich
        /// Stand, Stelle oder Schalter.
        case stand
        /// Ein anderes Lied oder eine andere Schlange.
        case schlange
        /// Die Sitzung ist weg (``geduld`` Abfragen hintereinander).
        case weg
    }

    // MARK: Abfragen

    /// **Wann eine Abfrage begann** — mit ihr wird entschieden, ob sie den
    /// letzten eigenen Befehl schon kennen kann.
    public struct Anfragemarke: Sendable, Equatable {
        let nummer: Int
        /// Alle Befehle bis ``nummer`` waren erledigt und ihr Nachlauf vorbei.
        let frei: Bool
    }

    /// Vor jeder Abfrage nehmen, nach ihr an ``abgleichen(_:marke:jetzt:)`` geben.
    public func marke(jetzt: Date = Date()) -> Anfragemarke {
        Anfragemarke(nummer: befehlsnummer,
                     frei: erledigtBis >= befehlsnummer && ruheBis.map { jetzt >= $0 } ?? true)
    }

    /// Ob ein eigener Befehl noch mehr zählt als eine Abfrage mit `marke`.
    func eigenerBefehlGilt(_ marke: Anfragemarke, jetzt: Date) -> Bool {
        guard let letzterBefehl, jetzt < letzterBefehl.addingTimeInterval(Self.vorrang) else { return false }
        return marke.nummer != befehlsnummer || !marke.frei
    }

    /// **Eine Abfrage aufnehmen.** Fehlt die Sitzung darin, zählt das mit;
    /// erst nach ``geduld`` Fehlversuchen ist sie weg. Ohne `marke` gilt die
    /// Abfrage als eben erst begonnen.
    public mutating func abgleichen(_ sitzungen: [Musiksitzung], marke: Anfragemarke? = nil,
                                    jetzt: Date = Date()) -> Ereignis {
        guard let s = sitzungen.first(where: { $0.id == sitzungID }) else {
            fehlt += 1
            return fehlt >= Self.geduld ? .weg : .gleich
        }
        fehlt = 0
        return aufnehmen(s, marke: marke ?? self.marke(jetzt: jetzt), jetzt: jetzt)
    }

    mutating func aufnehmen(_ s: Musiksitzung, marke: Anfragemarke, jetzt: Date) -> Ereignis {
        if let e = erwartung {
            // Das Gerät hat die Schlange noch nicht angenommen und meldet,
            // was vorher lief — das würde kurz im Blatt aufblitzen.
            if jetzt < e.bis, s.lied?.id != e.lied { return .gleich }
            erwartung = nil
        }
        let vorher = self
        let befehlGilt = eigenerBefehlGilt(marke, jetzt: jetzt)
        geraetename = s.geraetename

        guard let neuesLied = s.lied else {
            // Kein Lied gemeldet: das letzte bleibt stehen, angehalten.
            if lied != nil {
                gestoppt = true
                if !befehlGilt, !angehalten {
                    festhalten(stelle(jetzt: jetzt), jetzt: jetzt)
                    angehalten = true
                }
            }
            return self == vorher ? .gleich : .stand
        }
        gestoppt = false
        let neu = Self.schlange(s)
        let liedWechsel = neuesLied.id != lied?.id || neu.index != index
        lied = neuesLied
        ids = neu.ids
        index = neu.index
        if !neu.voll.isEmpty || neu.ids != vorher.ids { schlangeVoll = neu.voll }

        if !befehlGilt {
            letzterBefehl = nil
            angehalten = s.angehalten
            wiederholung = s.wiederholung
            gemischt = s.gemischt
        }
        if !befehlGilt || liedWechsel {
            let zeit = s.abgefragt ?? jetzt
            let neueStelle = s.stelle + Self.verzug(s, jetzt: jetzt)
            // Läuft dasselbe Lied weiter, setzt nur eine echte Abweichung die
            // Rechnung neu: dieselbe rohe Stelle wie beim letzten Mal heißt,
            // der Server hat nichts gezählt (zwei Abfragen in einer Sekunde),
            // und unter ``toleranz`` ist es Rauschen der Schätzung.
            let laeuftWeiter = !liedWechsel && !angehalten && !vorher.angehalten && !vorher.gestoppt
            let nichtsNeues = laeuftWeiter && gemeldet == s.stelle
            let rauschen = laeuftWeiter && abs(neueStelle - vorher.stelle(jetzt: zeit)) < Self.toleranz
            if !(nichtsNeues || rauschen) {
                stelleBeiBezug = neueStelle
                bezug = zeit
            }
            gemeldet = s.stelle
        }
        if ids != vorher.ids || liedWechsel { return .schlange }
        return self == vorher ? .gleich : .stand
    }

    /// **Nach dem Übergeben**: bis das Gerät `liedID` meldet (höchstens
    /// ``uebergabefrist``), gelten seine Antworten als veraltet.
    public mutating func erwarten(_ liedID: String, jetzt: Date = Date()) {
        erwartung = Erwartung(lied: liedID, bis: jetzt.addingTimeInterval(Self.uebergabefrist))
    }

    // MARK: Eigene Befehle

    /// **Was ein Knopf drüben wirklich heißen soll.** `umschalten` wird zu
    /// Pause oder Weiter nach dem gezeigten Stand — ein Umschalter, fünfmal
    /// schnell geschickt, kommt nur richtig an, wenn keiner verloren geht.
    /// Meldet das Gerät kein Lied mehr, fängt Abspielen die Schlange neu an.
    /// `nil`: es gibt nichts, was sich anfangen ließe.
    public func aufloesen(_ aktion: Fernaktion, jetzt: Date = Date()) -> Fernaktion? {
        switch aktion {
        case .umschalten:
            if gestoppt || lied == nil { return neuanfang(jetzt: jetzt) }
            return angehalten ? .weiter : .pause
        case .weiter:
            if gestoppt || lied == nil { return neuanfang(jetzt: jetzt) }
            return .weiter
        default:
            return aktion
        }
    }

    private func neuanfang(jetzt: Date) -> Fernaktion? {
        guard let r = rueckholung(jetzt: jetzt) else { return nil }
        return .spielen(ids: r.ids, ab: r.ab, stelle: r.stelle)
    }

    /// **Einen eigenen Befehl vorwegnehmen**, damit der Knopf sofort folgt.
    /// Gibt die Folgenummer zurück, mit der er später als erledigt gilt.
    @discardableResult
    public mutating func vormerken(_ aktion: Fernaktion, jetzt: Date = Date()) -> Int {
        let hier = stelle(jetzt: jetzt)
        befehlsnummer += 1
        letzterBefehl = jetzt
        ruheBis = nil
        switch aktion {
        case .pause:
            festhalten(hier, jetzt: jetzt); angehalten = true
        case .weiter:
            festhalten(hier, jetzt: jetzt); angehalten = false
        case .umschalten:
            festhalten(hier, jetzt: jetzt); angehalten.toggle()
        case let .springen(s):
            festhalten(max(0, min(s, dauer ?? s)), jetzt: jetzt)
        case let .wiederholung(w):
            wiederholung = w
        case let .mischen(an):
            gemischt = an
        case let .spielen(_, _, s):
            // Neu angefangen: es läuft, ab der Stelle.
            if gestoppt, lied != nil {
                gestoppt = false
                festhalten(s, jetzt: jetzt)
                angehalten = false
            }
        case .stopp, .naechstes, .voriges, .alsNaechstes, .hintenAn:
            // Was dort als Nächstes läuft, weiß erst das Gerät.
            break
        }
        return befehlsnummer
    }

    /// Der Befehl `nummer` ist beim Server angekommen (oder gescheitert).
    public mutating func erledigt(_ nummer: Int, jetzt: Date = Date()) {
        erledigtBis = max(erledigtBis, nummer)
        if erledigtBis >= befehlsnummer { ruheBis = jetzt.addingTimeInterval(Self.nachlauf) }
    }

    private mutating func festhalten(_ s: TimeInterval, jetzt: Date) {
        stelleBeiBezug = s
        bezug = jetzt
    }

    // MARK: Zurückholen

    /// Was „Hier weiterhören" braucht: die Schlange, wo es darin steht, und
    /// die Stelle. `nil`, wenn dort nichts lief.
    public func rueckholung(jetzt: Date = Date()) -> (ids: [String], ab: Int, stelle: TimeInterval)? {
        guard !ids.isEmpty, let index, index < ids.count else { return nil }
        return (ids, index, stelle(jetzt: jetzt))
    }
}

// MARK: - Befehle der Reihe nach

/// **Befehle an ein anderes Gerät gehen einer nach dem anderen.**
///
/// Vorher lief jeder Tipp als eigene Anfrage los. Fünf schnelle Tipps auf
/// Abspielen/Pause kamen dann in beliebiger Folge beim Server an, und was
/// drüben zuletzt ankam, war nicht, was hier zuletzt gedrückt wurde.
///
/// Jetzt ist höchstens einer unterwegs. Was wartet und dasselbe einstellt
/// (Lauf, Stelle, Wiederholen, Mischen), wird vom Neueren ersetzt statt
/// angehängt — fünf Tipps sind höchstens zwei Anfragen, und die letzte ist
/// die, die zählt. „Weiter" und „Zurück" zählen jeder für sich.
public struct Fernbefehlsfolge: Sendable, Equatable {

    public struct Befehl: Sendable, Equatable {
        public let nummer: Int
        public let aktion: Fernaktion
    }

    public private(set) var wartend: [Befehl] = []
    public private(set) var unterwegs: Befehl?

    public init() {}

    enum Art: Equatable { case lauf, sprung, wiederholung, mischen }

    static func art(_ a: Fernaktion) -> Art? {
        switch a {
        case .pause, .weiter, .umschalten: .lauf
        case .springen: .sprung
        case .wiederholung: .wiederholung
        case .mischen: .mischen
        case .stopp, .naechstes, .voriges, .spielen, .alsNaechstes, .hintenAn: nil
        }
    }

    public mutating func einreihen(_ aktion: Fernaktion, nummer: Int) {
        if let art = Self.art(aktion) {
            wartend.removeAll { Self.art($0.aktion) == art }
            // Was unterwegs ist, stellt schon genau das ein — es erledigt
            // dann auch diese Nummer.
            if art != .sprung, unterwegs?.aktion == aktion, aktion != .umschalten {
                unterwegs = Befehl(nummer: nummer, aktion: aktion)
                return
            }
        }
        wartend.append(Befehl(nummer: nummer, aktion: aktion))
    }

    /// Der nächste Befehl zum Senden — nur, wenn keiner unterwegs ist.
    public mutating func naechster() -> Befehl? {
        guard unterwegs == nil, !wartend.isEmpty else { return nil }
        unterwegs = wartend.removeFirst()
        return unterwegs
    }

    /// Der Befehl unterwegs ist beantwortet. Zurück kommt er mit der
    /// Nummer, die er jetzt erledigt — ein gleicher, der unterdessen kam,
    /// hat sie hochgesetzt.
    @discardableResult
    public mutating func fertig() -> Befehl? {
        defer { unterwegs = nil }
        return unterwegs
    }

    public var leer: Bool { unterwegs == nil && wartend.isEmpty }
}

public extension Musiksitzung {
    typealias Geraeteart = Fremdsitzung.Geraeteart
}
