import Foundation

// MARK: - Was Sonos direkt spielt

public enum Sonosregel {

    /// **Direkt, wenn der Lautsprecher die Datei so kann** — MP3, AAC, und
    /// FLAC und ALAC bis 24 Bit und 48 kHz (Sonos S2). Alles andere wird
    /// umgewandelt, dieselben 320 kbit/s MP3 wie auf dem iPhone
    /// (``Abspielregel/umwandlung(fuer:)``).
    ///
    /// Ohne Angaben: direkt — wie beim iPhone ist eine Umwandlung auf
    /// Verdacht der schlechtere Irrtum. `nil` heißt direkt.
    public static func umwandlung(fuer format: Tonformat?) -> Umwandlung? {
        kannDirekt(format) ? nil : Abspielregel.umwandlung(fuer: .jellyfin)
    }

    static let behaelter: Set<String> = ["mp3", "mpeg", "mpga", "m4a", "mp4", "aac", "adts", "flac", "alac"]
    static let codecs: Set<String> = ["mp3", "aac", "flac", "alac"]

    public static func kannDirekt(_ format: Tonformat?) -> Bool {
        guard let format else { return true }
        if let b = format.behaelter?.lowercased(), !b.isEmpty, !behaelter.contains(b) { return false }
        if let c = format.codec?.lowercased(), !c.isEmpty, !codecs.contains(c) { return false }
        let verlustfrei = ["flac", "alac"].contains(format.codec?.lowercased() ?? format.behaelter?.lowercased() ?? "")
        if verlustfrei {
            if let t = format.bitTiefe, t > 24 { return false }
            if let r = format.abtastrate, r > 48_000 { return false }
        }
        if format.behaelter == nil, format.codec == nil, let mime = format.mime?.lowercased() {
            return ["audio/mpeg", "audio/mp3", "audio/mp4", "audio/x-m4a", "audio/aac",
                    "audio/flac", "audio/x-flac"].contains(mime)
        }
        return true
    }
}

// MARK: - Titel und Hülle für die Sonos-App

public enum SonosDIDL {

    /// **DIDL-Lite zu einem Lied**, damit der Lautsprecher und die Sonos-App
    /// Titel, Künstler*in, Album und Hülle zeigen. Unmaskiert — die SOAP-Hülle
    /// maskiert es noch einmal als Wert (``SonosSoap/anfrage(_:_:_:)``).
    public static func metadaten(_ lied: Lied, adresse: URL, mime: String?, huelle: URL?) -> String {
        let m = SonosText.maskieren
        var item = "<item id=\"-1\" parentID=\"-1\" restricted=\"true\">"
        let dauer = lied.dauer.map { " duration=\"\(SonosZeit.schreiben($0)).000\"" } ?? ""
        item += "<res protocolInfo=\"http-get:*:\(m(mime ?? "*")):*\"\(dauer)>\(m(adresse.absoluteString))</res>"
        item += "<dc:title>\(m(lied.titel))</dc:title>"
        item += "<upnp:class>object.item.audioItem.musicTrack</upnp:class>"
        if let k = lied.kuenstler, !k.isEmpty {
            item += "<dc:creator>\(m(k))</dc:creator><upnp:artist>\(m(k))</upnp:artist>"
        }
        if let a = lied.album, !a.isEmpty { item += "<upnp:album>\(m(a))</upnp:album>" }
        if let huelle { item += "<upnp:albumArtURI>\(m(huelle.absoluteString))</upnp:albumArtURI>" }
        item += "</item>"
        return "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\""
            + " xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\""
            + " xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\""
            + " xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\">"
            + item + "</DIDL-Lite>"
    }

    /// Der Titel aus `TrackMetaData` — für eine Meldung, wenn dort etwas
    /// anderes läuft.
    public static func titel(_ didl: String?) -> String? {
        guard let didl, !didl.isEmpty, didl != "NOT_IMPLEMENTED" else { return nil }
        return SonosKnoten.lesen(didl)?.wert("title")
    }
}

// MARK: - Der Stand drüben

/// **Was der Lautsprecher gerade macht** — `GetTransportInfo`,
/// `GetPositionInfo` und `GetMediaInfo` zusammen.
public struct SonosLage: Sendable, Equatable {
    public enum Zustand: Sendable, Equatable {
        case spielt, pausiert, gestoppt
        /// Lädt oder wechselt gerade — zählt als spielend.
        case wechselt

        public init(_ roh: String?) {
            switch roh {
            case "PLAYING": self = .spielt
            case "PAUSED_PLAYBACK": self = .pausiert
            case "TRANSITIONING": self = .wechselt
            default: self = .gestoppt
            }
        }
    }

    public let zustand: Zustand
    /// `TrackURI` — was gerade läuft.
    public let spur: String?
    /// `CurrentURI` und `NextURI` aus `GetMediaInfo`.
    public let geladen: String?
    public let naechstesGeladen: String?
    public let stelle: TimeInterval
    public let dauer: TimeInterval?
    /// `Track` — die Nummer in der Sonos-Warteschlange, ab 1.
    public let nummer: Int?

    public init(zustand: Zustand, spur: String?, geladen: String?, naechstesGeladen: String?,
                stelle: TimeInterval, dauer: TimeInterval?, nummer: Int? = nil) {
        self.nummer = nummer
        self.zustand = zustand
        self.spur = spur.flatMap { $0.isEmpty ? nil : $0 }
        self.geladen = geladen.flatMap { $0.isEmpty ? nil : $0 }
        self.naechstesGeladen = naechstesGeladen.flatMap { $0.isEmpty ? nil : $0 }
        self.stelle = stelle
        self.dauer = dauer
    }

    public var laeuft: Bool { zustand == .spielt || zustand == .wechselt }
}

/// **Was wir dem Lautsprecher zuletzt gegeben haben** — das laufende Lied
/// und das nächste, jeweils Adresse und Eintrag in unserer Schlange.
public struct SonosGesendet: Sendable, Equatable {
    public let adresse: String
    public let eintrag: UUID
    public var naechsteAdresse: String?
    public var naechsterEintrag: UUID?

    public init(adresse: String, eintrag: UUID, naechsteAdresse: String? = nil, naechsterEintrag: UUID? = nil) {
        self.adresse = adresse
        self.eintrag = eintrag
        self.naechsteAdresse = naechsteAdresse
        self.naechsterEintrag = naechsterEintrag
    }
}

/// **Unsere Schlange führt, der Lautsprecher kennt nur zwei Lieder.** Er
/// spielt das laufende (`SetAVTransportURI`) und hat das nächste schon
/// (`SetNextAVTransportURI`), damit es ohne Lücke weitergeht. Was darüber
/// hinausgeht — Mischen, Wiederholen, Umstellen —, entscheidet die
/// ``Warteschlange`` hier.
public enum Sonosfolge {

    /// Was als nächstes Lied an den Lautsprecher geht: bei „ein Lied
    /// wiederholen" das laufende noch einmal, sonst das nächste der Schlange.
    public static func naechster(_ s: Warteschlange) -> Warteschlange.Eintrag? {
        s.wiederholtLaufendes ? s.aktuell : s.naechster
    }

    public enum Befund: Sendable, Equatable {
        /// Er spielt, was wir geschickt haben.
        case gleich
        /// Er ist von selbst ins nächste Lied gegangen.
        case weiter
        /// Er spielt etwas anderes — jemand hat in der Sonos-App oder mit
        /// einem anderen Dienst übernommen.
        case fremd
        /// Er hat nichts geladen.
        case leer
    }

    /// **Wie das, was läuft, zu dem passt, was wir geschickt haben.**
    ///
    /// Nach einem Übergang steht das frühere nächste Lied als laufendes da,
    /// und das nächste ist leer. Sind beide Adressen gleich (dasselbe Lied
    /// wiederholt), verrät nur das: `NextURI` ist dann aufgebraucht.
    public static func befund(_ lage: SonosLage, gesendet: SonosGesendet) -> Befund {
        guard let laeuft = (lage.spur ?? lage.geladen).map(gleichgestellt) else { return .leer }
        let aktuell = gleichgestellt(gesendet.adresse)
        if let naechste = gesendet.naechsteAdresse.map(gleichgestellt), laeuft == naechste {
            if naechste != aktuell { return .weiter }
            // Dasselbe zweimal: weiter ist er, wenn das nächste verbraucht ist.
            return lage.naechstesGeladen == nil ? .weiter : .gleich
        }
        return laeuft == aktuell ? .gleich : .fremd
    }

    // MARK: Die Sonos-Warteschlange

    /// **Höchstens so viele Lieder gehen in die Sonos-Warteschlange** — um
    /// das laufende herum, was kommt, hat Vorrang (``Uebergabe/fenster(_:ab:hoechstens:)``).
    /// Rückt die Wiedergabe vor, wird hinten nachgefüllt.
    public static let hoechstens = 200

    /// Der Ausschnitt unserer Schlange, der an Sonos geht, und wo darin das
    /// laufende Lied steht.
    public static func fenster(_ s: Warteschlange, hoechstens: Int = hoechstens)
        -> (eintraege: [Warteschlange.Eintrag], ab: Int) {
        guard let p = s.position, !s.istLeer else { return ([], 0) }
        let alle = s.eintraege
        let (ids, ab) = Uebergabe.fenster(alle.map(\.id.uuidString), ab: p, hoechstens: hoechstens)
        guard let erste = ids.first, let anfang = alle.firstIndex(where: { $0.id.uuidString == erste }) else {
            return ([], 0)
        }
        return (Array(alle[anfang ..< anfang + ids.count]), ab)
    }

    /// `SetPlayMode`: Wiederholen macht Sonos selbst, damit er ohne das
    /// Telefon weiterspielt. Mischen nicht — die Reihenfolge ist schon unsere.
    public static func spielmodus(_ w: Warteschlange.Wiederholung) -> String {
        switch w {
        case .aus: "NORMAL"
        case .alles: "REPEAT_ALL"
        case .eines: "REPEAT_ONE"
        }
    }

    /// **Wo die Sonos-Warteschlange steht, in unserer Schlange.** Die
    /// Nummer (`Track`) zeigt auf den Eintrag, den wir an diese Stelle
    /// gelegt haben — solange dort unsere Adresse läuft. Sonst hat jemand
    /// die Warteschlange drüben geändert oder etwas anderes gestartet.
    public static func befund(_ lage: SonosLage, schlange: Sonosschlange, koordinator: String)
        -> (befund: Befund, index: Int?) {
        guard let geladen = lage.geladen else { return (.leer, nil) }
        guard geladen.hasPrefix("x-rincon-queue:\(koordinator)") else { return (.fremd, nil) }
        // **Ohne laufende Adresse zählt die Nummer nicht.** Eine geleerte
        // Warteschlange meldet trotzdem `Track` 1 — das hieß „weiter zum
        // ersten Lied" und setzte hier ein falsches Lied (Test 25.09., beim
        // Gruppieren).
        guard lage.spur != nil else { return (.leer, nil) }
        guard let n = lage.nummer, n >= 1, n <= schlange.folge.count else { return (.fremd, nil) }
        let i = n - 1
        if let spur = lage.spur, gleichgestellt(spur) != gleichgestellt(schlange.adressen[i]) {
            return (.fremd, nil)
        }
        return (i == schlange.aktuell ? .gleich : .weiter, i)
    }

    /// Adressen vergleichbar machen: ohne Prozentzeichen-Kodierung und
    /// Rand. Eine Firmware, die `%2C` als `,` zurückgibt, meint dasselbe.
    static func gleichgestellt(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.removingPercentEncoding ?? t
    }

    /// **Der Stand als Sitzung**, damit ``Fernstand`` ihn führt wie ein
    /// Connect-Gerät: dieselbe weiche Stelle, dieselbe Regel für eigene
    /// Befehle, die eine Abfrage nicht überholen darf.
    ///
    /// Das Lied und die Schlange sind unsere — was drüben läuft, zeigt der
    /// Befund. Läuft dort nichts von uns, meldet die Sitzung kein Lied, und
    /// ``Fernstand`` hält das letzte angehalten fest.
    public static func sitzung(id: String, name: String, schlange: Warteschlange, lage: SonosLage,
                               unser: Bool, abgefragt: Date) -> Musiksitzung {
        let eintraege = schlange.eintraege
        return Musiksitzung(
            id: id, benutzerID: nil, geraeteID: id, geraetename: name, programm: "Sonos",
            lied: unser ? schlange.aktuell?.lied : nil,
            angehalten: !lage.laeuft, stelle: lage.stelle,
            wiederholung: schlange.wiederholung, gemischt: schlange.gemischt,
            schlange: eintraege.map(\.lied.id),
            schlangeneintraege: eintraege.map(\.id.uuidString),
            eintragID: schlange.aktuell?.id.uuidString,
            abgefragt: abgefragt)
    }
}

/// **Was in der Sonos-Warteschlange liegt** — unsere Einträge in der Folge,
/// in der sie dort stehen, ihre Adressen, und welcher gerade läuft.
public struct Sonosschlange: Sendable, Equatable {
    public internal(set) var folge: [UUID]
    public internal(set) var adressen: [String]
    /// Der laufende, als Index in ``folge``.
    public internal(set) var aktuell: Int
    public internal(set) var wiederholung: Warteschlange.Wiederholung

    public init(folge: [UUID], adressen: [String], aktuell: Int, wiederholung: Warteschlange.Wiederholung) {
        self.folge = folge
        self.adressen = adressen
        self.aktuell = aktuell
        self.wiederholung = wiederholung
    }

    public var eintrag: UUID? { folge.indices.contains(aktuell) ? folge[aktuell] : nil }

    /// Was nach dem laufenden in der Warteschlange liegt.
    public var kommende: [UUID] { folge.indices.contains(aktuell) ? Array(folge[(aktuell + 1)...]) : [] }

    /// **Wie das Kommende an unsere Schlange angeglichen wird.** Liegt drüben
    /// schon der Anfang dessen, was kommen soll, wird nur hinten angefügt;
    /// sonst alles hinter dem laufenden weg und neu. Das laufende Lied bleibt
    /// in beiden Fällen unberührt — es spielt ohne Unterbrechung weiter.
    public enum Angleich: Sendable, Equatable {
        case nichts
        case anfuegen(ab: Int)
        /// Ab der Nummer (1-basiert) `ab` die `anzahl` Lieder weg, dann alles anfügen.
        case ersetzen(ab: Int, anzahl: Int)
    }

    public func angleich(_ gewollt: [UUID]) -> Angleich {
        let da = kommende
        if da == gewollt { return .nichts }
        if gewollt.count > da.count, Array(gewollt.prefix(da.count)) == da { return .anfuegen(ab: da.count) }
        return .ersetzen(ab: aktuell + 2, anzahl: da.count)
    }
}
