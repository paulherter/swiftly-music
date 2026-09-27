import Foundation
import JellyfinKit

/// **Ein Gerät, auf dem Jellyfin läuft** — aus `GET /Sessions`, mit dem, was
/// Swiftly Music zum Anzeigen und Steuern braucht.
///
/// Eigener Typ statt ``Fremdsitzung`` aus JellyfinKit: die kennt weder die
/// Schlange (`NowPlayingQueue`) noch Wiederholen, Mischen oder die Zeit der
/// letzten Meldung, und ihr Titel ist ein Film-`Item`. Die Regeln, welche
/// Sitzung zählt, stehen trotzdem nicht doppelt: die Geräteart kommt aus
/// ``Fremdsitzung/geraeteart``, die Stillefrist aus ``Uebernahme/stillefrist``.
public struct Musiksitzung: Sendable, Equatable, Identifiable {
    public let id: String
    public let benutzerID: String?
    public let geraeteID: String?
    public let geraetename: String
    /// „Jellyfin Web", „Swiftly Music", „Finamp".
    public let programm: String?
    /// `SupportsRemoteControl` — ohne das kommen unsere Befehle nicht an.
    public let nimmtBefehle: Bool
    /// `PlayableMediaTypes` enthält `Audio`.
    public let spieltMusik: Bool
    public let befehle: [String]
    /// Was dort läuft, wenn es ein Lied ist. Ohne Tonspur- und Dateiangaben —
    /// zum Anzeigen, nicht zum Abspielen.
    public let lied: Lied?
    /// Dort läuft etwas, aber kein Lied (ein Film).
    public let laeuftAnderes: Bool
    public let angehalten: Bool
    /// Sekunden, Stand der letzten Meldung des Geräts.
    public let stelle: TimeInterval
    public let lautstaerke: Int?
    public let wiederholung: Warteschlange.Wiederholung
    public let gemischt: Bool
    /// Die Schlange dort, als Liedkennungen.
    public let schlange: [String]
    /// Je Eintrag die `PlaylistItemId` — dasselbe Lied darf zweimal darin stehen.
    public let schlangeneintraege: [String]
    /// `NowPlayingQueueFullItems`, wenn der Server sie mitschickt.
    public let schlangeVoll: [Lied]
    /// `PlaylistItemId` des laufenden Eintrags.
    public let eintragID: String?
    public let letzteRegung: Date?
    /// `LastPlaybackCheckIn`: wann das Gerät zuletzt seine Stelle gemeldet hat.
    /// Nicht, zu welcher Zeit ``stelle`` gilt — die zählt der Server
    /// zwischen zwei Meldungen selbst weiter (``Fernstand``).
    public let letzteMeldung: Date?
    /// `LastPausedDate`: seit wann es dort angehalten ist.
    public let pausiertSeit: Date?
    /// Wann die Antwort mit dieser Sitzung ankam. Zu dieser Zeit gilt
    /// ``stelle``; `nil` heißt „eben".
    public var abgefragt: Date?

    public init(id: String, benutzerID: String?, geraeteID: String?, geraetename: String,
                programm: String?, nimmtBefehle: Bool = true, spieltMusik: Bool = true,
                befehle: [String] = [], lied: Lied? = nil, laeuftAnderes: Bool = false,
                angehalten: Bool = false, stelle: TimeInterval = 0, lautstaerke: Int? = nil,
                wiederholung: Warteschlange.Wiederholung = .aus, gemischt: Bool = false,
                schlange: [String] = [], schlangeneintraege: [String] = [], schlangeVoll: [Lied] = [],
                eintragID: String? = nil, letzteRegung: Date? = nil, letzteMeldung: Date? = nil,
                pausiertSeit: Date? = nil, abgefragt: Date? = nil) {
        self.id = id; self.benutzerID = benutzerID; self.geraeteID = geraeteID
        self.geraetename = geraetename; self.programm = programm
        self.nimmtBefehle = nimmtBefehle; self.spieltMusik = spieltMusik; self.befehle = befehle
        self.lied = lied; self.laeuftAnderes = laeuftAnderes
        self.angehalten = angehalten; self.stelle = stelle; self.lautstaerke = lautstaerke
        self.wiederholung = wiederholung; self.gemischt = gemischt
        self.schlange = schlange; self.schlangeneintraege = schlangeneintraege
        self.schlangeVoll = schlangeVoll; self.eintragID = eintragID
        self.letzteRegung = letzteRegung; self.letzteMeldung = letzteMeldung
        self.pausiertSeit = pausiertSeit; self.abgefragt = abgefragt
    }

    /// Spielt dort gerade ein Lied, nicht angehalten?
    public var spielt: Bool { lied != nil && !angehalten }

    /// Telefon, Fernseher, Rechner — **dieselbe Entscheidung wie im Player**
    /// (``Fremdsitzung/geraeteart``), damit ein Android-Telefon nicht hier als
    /// Fernseher erscheint und dort als Telefon.
    public var geraeteart: Fremdsitzung.Geraeteart {
        Fremdsitzung(id: id, geraeteID: geraeteID, geraetename: geraetename, programm: programm,
                     nimmtBefehle: nimmtBefehle, laeuft: nil, stand: nil).geraeteart
    }

    /// **Wo in ``schlange`` das laufende Lied steht** — `nil`, wenn die
    /// Schlange nicht zu ihm passt.
    ///
    /// Die Schlange in `GET /Sessions` ist oft eine alte: Jellyfin setzt
    /// `NowPlayingQueue` nur aus Meldungen, die eine mitbringen (Start und
    /// Stopp bei Jellyfin-Web, in `master` nur noch der Stopp), und löscht
    /// sie nie; `PlaylistItemId` dagegen kommt mit jeder Meldung. Startete
    /// jemand drüben selbst etwas anderes, steht die Schlange, die Swiftly
    /// Music vorher geschickt hatte, noch da — und Jellyfin-Web zählt die
    /// Einträge nach jedem Neuladen wieder ab `playlistItem0`, sodass der
    /// neue Eintrag in der alten Schlange ein anderes Lied treffen kann
    /// (24.09.: „ein anderes Lied, eines, das ich vorhin dorthin
    /// geschickt hatte"). Deshalb gilt ein Eintrag nur, wenn an ihm auch das
    /// laufende Lied steht, und ein Eintrag, der fehlt, heißt: alte Schlange.
    public var index: Int? {
        let mitEintraegen = schlangeneintraege.contains { !$0.isEmpty }
        if let eintragID, !eintragID.isEmpty, mitEintraegen {
            guard let i = schlangeneintraege.firstIndex(of: eintragID), i < schlange.count else { return nil }
            if let lied, schlange[i] != lied.id { return nil }
            return i
        }
        guard let lied else { return nil }
        return schlange.firstIndex(of: lied.id)
    }
}

// MARK: - Welche Geräte angeboten werden

/// **Welche Sitzungen in der Geräteliste stehen, und welche als „läuft
/// woanders" angeboten wird.**
///
/// Die Fallen sind dieselben wie bei ``Uebernahme`` im Player, und sie
/// stehen dort ausführlich: `controllableByUserId` liefert einem
/// Administrator den ganzen Haushalt, also zählt nur das eigene Konto; und
/// ohne die eigene Gerätekennung zeigt das Gerät sich selbst an.
public enum Geraeteliste {

    /// **Nur Swiftly-Geräte im Blatt „Abspielen auf"** — andere
    /// Jellyfin-Programme stehen nicht mehr darin (Jellyfin-Web, Finamp):
    /// wie weit sie Befehle wirklich ausführen, weiß man vorher nicht. Mac
    /// und Fernseher kommen dazu, sobald es Swiftly Music dort gibt.
    public static let swiftlyProgramme: Set<String> = ["Swiftly Music"]

    /// Die Geräte, an die Swiftly Music Musik schicken kann — was gerade
    /// spielt zuerst, dann nach letzter Regung. `programme`: nur Sitzungen
    /// dieser Programme; `nil` heißt jedes.
    public static func auswahl(_ sitzungen: [Musiksitzung], eigeneGeraeteID: String,
                               eigeneBenutzerID: String, programme: Set<String>? = nil) -> [Musiksitzung] {
        sitzungen
            .filter { taugt($0, eigeneGeraeteID: eigeneGeraeteID, eigeneBenutzerID: eigeneBenutzerID) }
            .filter { s in programme.map { s.programm.map($0.contains) ?? false } ?? true }
            .sorted { a, b in
                if a.spielt != b.spielt { return a.spielt }
                return (a.letzteRegung ?? .distantPast) > (b.letzteRegung ?? .distantPast)
            }
    }

    static func taugt(_ s: Musiksitzung, eigeneGeraeteID: String, eigeneBenutzerID: String) -> Bool {
        // 1. Nicht wir selbst.
        guard s.geraeteID != eigeneGeraeteID else { return false }
        // 2. Nur das eigene Konto — fremde Wiedergabe zu übernehmen wäre ein Übergriff.
        guard let wem = s.benutzerID, wem == eigeneBenutzerID else { return false }
        // 3. Befehle müssen ankommen, und es muss Musik spielen können.
        return s.nimmtBefehle && s.spieltMusik
    }

    /// **„Läuft auf ‹Gerät›"** — eine eigene andere Sitzung, die gerade ein
    /// Lied spielt und sich vor kurzem gemeldet hat. Die jüngste zuerst.
    ///
    /// Angehalten zählt nicht: wer drüben auf Pause gedrückt hat, hat
    /// aufgehört, und ein Angebot beim Öffnen wäre dann nur im Weg.
    public static func laeuftWoanders(_ sitzungen: [Musiksitzung], eigeneGeraeteID: String,
                                      eigeneBenutzerID: String, programme: Set<String>? = nil,
                                      jetzt: Date = Date()) -> Musiksitzung? {
        auswahl(sitzungen, eigeneGeraeteID: eigeneGeraeteID, eigeneBenutzerID: eigeneBenutzerID,
                programme: programme)
            .filter { s in
                guard s.spielt else { return false }
                let zuletzt = [s.letzteMeldung, s.letzteRegung].compactMap { $0 }.max()
                guard let zuletzt else { return true }
                return jetzt.timeIntervalSince(zuletzt) <= Uebernahme.stillefrist
            }
            .max { ($0.letzteRegung ?? .distantPast) < ($1.letzteRegung ?? .distantPast) }
    }
}

// MARK: - Lesen

/// `SessionInfoDto`, soweit Musik es braucht — nachsichtig wie `JEintrag`:
/// ein Feld mit unerwartetem Typ lässt nur dieses Feld leer.
struct JSitzung: Decodable, Sendable {
    let id: String
    let benutzerID: String?
    let geraeteID: String?
    let geraetename: String?
    let programm: String?
    let nimmtBefehle: Bool
    let arten: [String]
    let befehle: [String]
    let laeuft: JEintrag?
    let angehalten: Bool
    let stelleTicks: Int64?
    let lautstaerke: Int?
    let wiederholung: String?
    let reihenfolge: String?
    let schlange: [JSchlangeneintrag]
    let schlangeVoll: [JEintrag]
    let eintragID: String?
    let letzteRegung: Date?
    let letzteMeldung: Date?
    let pausiertSeit: Date?

    struct JSchlangeneintrag: Decodable, Sendable {
        let id: String
        let eintrag: String?
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: JSchluessel.self)
            guard let id = c.wert("Id", String.self), !id.isEmpty else {
                throw DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: "Id"))
            }
            self.id = id
            eintrag = c.wert("PlaylistItemId", String.self)
        }
    }

    struct JStand: Decodable, Sendable {
        let angehalten: Bool?
        let stelleTicks: Int64?
        let lautstaerke: Int?
        let wiederholung: String?
        let reihenfolge: String?
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: JSchluessel.self)
            angehalten = c.wert("IsPaused", Bool.self)
            stelleTicks = c.zahl64("PositionTicks")
            lautstaerke = c.zahl("VolumeLevel")
            wiederholung = c.wert("RepeatMode", String.self)
            // `PlaybackOrder` seit 10.9, davor `ShuffleMode`.
            reihenfolge = c.wert("PlaybackOrder", String.self) ?? c.wert("ShuffleMode", String.self)
        }
    }

    struct JFaehig: Decodable, Sendable {
        let arten: [String]?
        let befehle: [String]?
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: JSchluessel.self)
            arten = c.wert("PlayableMediaTypes", [String].self)
            befehle = c.wert("SupportedCommands", [String].self)
        }
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: JSchluessel.self)
        guard let id = c.wert("Id", String.self), !id.isEmpty else {
            throw DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: "Id"))
        }
        self.id = id
        benutzerID = c.wert("UserId", String.self)
        geraeteID = c.wert("DeviceId", String.self)
        geraetename = c.wert("DeviceName", String.self)
        programm = c.wert("Client", String.self)
        nimmtBefehle = c.wert("SupportsRemoteControl", Bool.self) ?? false
        let faehig = c.wert("Capabilities", JFaehig.self)
        arten = c.wert("PlayableMediaTypes", [String].self) ?? faehig?.arten ?? []
        befehle = c.wert("SupportedCommands", [String].self) ?? faehig?.befehle ?? []
        laeuft = c.wert("NowPlayingItem", JEintrag.self)
        let stand = c.wert("PlayState", JStand.self)
        angehalten = stand?.angehalten ?? false
        stelleTicks = stand?.stelleTicks
        lautstaerke = stand?.lautstaerke
        wiederholung = stand?.wiederholung
        reihenfolge = stand?.reihenfolge
        schlange = c.liste("NowPlayingQueue")
        schlangeVoll = c.liste("NowPlayingQueueFullItems")
        eintragID = c.wert("PlaylistItemId", String.self)
        letzteRegung = c.wert("LastActivityDate", String.self).flatMap(JDatum.lesen)
        letzteMeldung = c.wert("LastPlaybackCheckIn", String.self).flatMap(JDatum.lesen)
            // Jellyfin schreibt „nie" als 0001-01-01.
            .flatMap { $0.timeIntervalSince1970 > 0 ? $0 : nil }
        pausiertSeit = c.wert("LastPausedDate", String.self).flatMap(JDatum.lesen)
            .flatMap { $0.timeIntervalSince1970 > 0 ? $0 : nil }
    }

    /// In unsere Begriffe — `lied` baut die Quelle (``JellyfinQuelle/liedAus(_:)``).
    func musiksitzung(_ lied: (JEintrag) -> Lied) -> Musiksitzung {
        let istLied = laeuft.map { ($0.typ ?? "Audio") == "Audio" || $0.medienart == "Audio" } ?? false
        let wieder: Warteschlange.Wiederholung = switch wiederholung {
        case "RepeatAll": .alles
        case "RepeatOne": .eines
        default: .aus
        }
        return Musiksitzung(
            id: id, benutzerID: benutzerID, geraeteID: geraeteID,
            geraetename: Geraetename.lesbar(geraetename ?? programm ?? ""),
            programm: programm, nimmtBefehle: nimmtBefehle,
            spieltMusik: arten.contains("Audio"), befehle: befehle,
            lied: istLied ? laeuft.map(lied) : nil,
            laeuftAnderes: laeuft != nil && !istLied,
            angehalten: angehalten,
            stelle: TimeInterval(max(0, stelleTicks ?? 0)) / 10_000_000,
            lautstaerke: lautstaerke, wiederholung: wieder, gemischt: reihenfolge == "Shuffle",
            schlange: schlange.map(\.id), schlangeneintraege: schlange.map { $0.eintrag ?? "" },
            schlangeVoll: schlangeVoll.map(lied), eintragID: eintragID,
            letzteRegung: letzteRegung, letzteMeldung: letzteMeldung, pausiertSeit: pausiertSeit)
    }
}

// MARK: - Gerätenamen

/// **Ein Gerätename, wie ihn ein Mensch vergeben hat** — auch wenn er
/// unterwegs verbogen wurde.
///
/// Anlass: ein MacBook heißt in Jellyfin „Anna’s MacBook", bei uns stand
/// „Annaas MacBook" (24.09.). Jellyfin nimmt den Namen aus der Kopfzeile
/// `Authorization: MediaBrowser Device="…"` und löst dort Prozentzeichen auf
/// (`WebUtility.UrlDecode`, `AuthorizationContext.GetParts`). Schickt ein
/// Programm den Namen roh, mit dem typografischen Apostroph, den macOS in
/// jeden Rechnernamen setzt (U+2019), kommen dessen drei UTF-8-Bytes
/// E2 80 99 über eine Kopfzeile, die nur Latin-1 kennt — und heraus kommt
/// „Annaâ" plus zwei unsichtbare Steuerzeichen, klein gesetzt kaum von
/// „Annaa" zu unterscheiden. Jellyfins Oberfläche zeigt für das Gerät
/// oft den Namen aus der Geräteverwaltung, der beim Anmelden anders ankam.
///
/// Repariert wird nur, was sich eindeutig zurücklesen lässt:
/// 1. Prozentkodierung, die niemand aufgelöst hat („Anna%E2%80%99s").
/// 2. UTF-8, als Latin-1 oder Windows-1252 gelesen („Annaâ€™s") — nur wenn
///    die Bytes zurück wieder gültiges UTF-8 ergeben; „Café" bleibt „Café".
/// 3. Steuerzeichen fallen heraus.
///
/// Base64 kommt in Gerätenamen nicht vor: Jellyfin-Web kodiert so nur die
/// Gerätekennung (`btoa(userAgent|Zeit)`), nicht den Namen.
public enum Geraetename {

    public static func lesbar(_ roh: String) -> String {
        var name = roh
        if eindeutigKodiert(name), let frei = name.removingPercentEncoding {
            name = frei
        }
        name = zurueckgelesen(name)
        let sauber = String(String.UnicodeScalarView(name.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }))
        let fertig = sauber.trimmingCharacters(in: .whitespaces)
        return fertig.isEmpty ? roh : fertig
    }

    /// **Ist der Name wirklich kodiert, oder steht das `%` darin wörtlich?**
    /// Ein Kodierer ersetzt jedes Leerzeichen; steht neben einem wörtlichen
    /// Leerzeichen ein `%20`, hat das niemand kodiert — „R%20D Lab" heißt
    /// so. Kodiert gilt ein Name also, wenn er ein `%XX` trägt und entweder
    /// gar kein Leerzeichen hat oder kein kodiertes. Ungültiges UTF-8 lässt
    /// `removingPercentEncoding` ohnehin stehen.
    static func eindeutigKodiert(_ name: String) -> Bool {
        guard name.range(of: "%[0-9A-Fa-f]{2}", options: .regularExpression) != nil else { return false }
        let leer = name.contains(" ")
        let kodiertesLeer = name.range(of: "%20", options: .caseInsensitive) != nil
        return !(leer && kodiertesLeer)
    }

    /// UTF-8, das als Latin-1/Windows-1252 gelesen wurde, zurück in Zeichen.
    static func zurueckgelesen(_ s: String) -> String {
        // Nur, wenn ein Anfangsbyte einer UTF-8-Folge dasteht (Â bis ô).
        guard s.unicodeScalars.contains(where: { (0xC2 ... 0xF4).contains($0.value) }) else { return s }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(s.unicodeScalars.count)
        for z in s.unicodeScalars {
            if z.value < 0x100 {
                bytes.append(UInt8(z.value))
            } else if let b = windows1252[z.value] {
                bytes.append(b)
            } else {
                return s
            }
        }
        guard let neu = String(bytes: bytes, encoding: .utf8), neu != s else { return s }
        return neu
    }

    /// Die Zeichen, die Windows-1252 auf 0x80 bis 0x9F legt.
    private static let windows1252: [UInt32: UInt8] = [
        0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, 0x2020: 0x86,
        0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, 0x0152: 0x8C,
        0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92, 0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95,
        0x2013: 0x96, 0x2014: 0x97, 0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B,
        0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F,
    ]
}
