import Foundation
import Testing
@testable import MusikKit

/// **Der Testablauf gegen einen nachgebauten Jellyfin-Server** (24.09.): auf
/// dem MacBook läuft in Jellyfin-Web ein Lied, das dort gestartet wurde;
/// vorher hatte Swiftly Music eine andere Schlange dorthin geschickt.
///
/// Gemessen wird nicht gegen einen echten Server (auf dem Mac läuft kein
/// Docker). Stattdessen baut ``Sitzungsabbild`` nach, was Jellyfins
/// `SessionManager` mit den Meldungen eines Geräts macht, und schreibt die
/// Sitzung als JSON, wie `GET /Sessions` sie liefert. Nachgebaut nach dem
/// Quelltext (jellyfin 10.8.13 bis 10.11.0 und `master`):
///
/// - `SessionInfo.StartAutomaticProgress`: nach jeder echten Meldung zählt
///   der Server `PositionTicks` selbst weiter, jede Sekunde um eine Sekunde
///   (`ProgressIncrement`), ohne `LastPlaybackCheckIn` anzufassen. Die
///   gemeldete Stelle ist also schon „jetzt", nicht „bei der Meldung".
/// - `UpdateNowPlayingItem` (10.8–10.11) ersetzt `NowPlayingQueue` nur,
///   wenn eine Meldung eine mitbringt — Jellyfin-Web tut das beim Start,
///   beim Stopp und beim Umstellen der Schlange, nicht im 10-s-Takt. In
///   `master` setzt nur noch der Stopp die Schlange.
/// - `OnPlaybackStopped` setzt `NowPlayingQueue` und `PlaylistItemId` aus
///   der Stoppmeldung und löscht `NowPlayingItem`; die Schlange bleibt.
/// - Jellyfin-Web zählt `PlaylistItemId` je Seitenaufruf ab `playlistItem0`
///   (`playqueuemanager.js`), nach einem Neuladen also wieder von vorn.
@Suite("Connect: Testablauf")
struct ConnectAblaufTests {

    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    /// Die Lieder und ihre Länge.
    static let laengen: [String: TimeInterval] = ["a1": 200, "a2": 210, "a3": 190, "b1": 240, "b2": 230, "b3": 250]

    static func lesen(_ json: Data) throws -> [Musiksitzung] {
        let roh = try JSONDecoder().decode([Vielleicht<JSitzung>].self, from: json)
        return roh.compactMap(\.wert).map {
            $0.musiksitzung { e in Lied(id: e.id, titel: e.name, dauer: laengen[e.id]) }
        }
    }

    /// Eine Abfrage zur Zeit `t`, wie `JellyfinQuelle.sitzungen()` sie liefert.
    static func abfrage(_ server: Sitzungsabbild, _ t: Date) throws -> [Musiksitzung] {
        try lesen(server.json(t))
    }

    // MARK: Stelle

    /// Jellyfin-Web meldet alle 10 s, der Server zählt dazwischen selbst —
    /// die Anzeige darf höchstens 1 s danebenliegen und nie zurückspringen.
    @Test("Die Stelle folgt dem Gerät auf 1 s genau und springt nicht zurück", arguments: [0.0, 0.3, 0.7])
    func stelleFolgt(versatz: TimeInterval) throws {
        var server = Sitzungsabbild(fassung: .v10_11)
        let start = Self.t0
        // Wahr: b2 läuft ab 12 s, seit `start`.
        func wahr(_ t: Date) -> TimeInterval { 12 + t.timeIntervalSince(start) }
        server.start("b2", stelle: 12, eintrag: "playlistItem1",
                     schlange: [("b1", "playlistItem0"), ("b2", "playlistItem1")], t: start)
        var stand: Fernstand?
        var groessterFehler = 0.0
        var groessterRuecksprung = 0.0
        var zuletzt: TimeInterval?
        var meldungBis = start
        // 60 s lang: Abfrage alle 2 s, Anzeige alle 0,5 s.
        for schritt in 0 ..< 120 {
            let t = start.addingTimeInterval(versatz + Double(schritt) * 0.5)
            // Echte Meldungen des Geräts alle 10 s.
            while meldungBis.addingTimeInterval(10) <= t {
                meldungBis = meldungBis.addingTimeInterval(10)
                server.fortschritt(stelle: wahr(meldungBis), t: meldungBis)
            }
            if schritt % 4 == 0 {
                let sitzungen = try Self.abfrage(server, t)
                if stand == nil {
                    stand = Fernstand(try #require(sitzungen.first), jetzt: t)
                } else {
                    _ = stand!.abgleichen(sitzungen, jetzt: t)
                }
            }
            let gezeigt = try #require(stand).stelle(jetzt: t)
            groessterFehler = max(groessterFehler, abs(gezeigt - wahr(t)))
            if let zuletzt { groessterRuecksprung = max(groessterRuecksprung, zuletzt - gezeigt) }
            zuletzt = gezeigt
        }
        #expect(groessterFehler <= 1, "Stelle bis zu \(groessterFehler) s daneben")
        #expect(groessterRuecksprung <= 0.25, "Anzeige springt bis zu \(groessterRuecksprung) s zurück")
    }

    // MARK: Lied und Schlange

    /// Vorher schickte Swiftly Music a1–a3 zum Mac; dann startet jemand dort
    /// selbst ein anderes Album. Der Server behält die alte Schlange.
    static func vorgeschichte(_ fassung: Sitzungsabbild.Fassung, neuGeladen: Bool) -> Sitzungsabbild {
        var server = Sitzungsabbild(fassung: fassung)
        let a: [(String, String)] = [("a1", "playlistItem0"), ("a2", "playlistItem1"), ("a3", "playlistItem2")]
        // Über die App geschickt: PlayNow a1–a3, ab a2.
        server.start("a2", stelle: 40, eintrag: "playlistItem1", schlange: a, t: t0)
        server.fortschritt(stelle: 50, t: t0.addingTimeInterval(10))
        // Stopp mit der alten Schlange, dann der Start von b1–b3 ab b2.
        let b: [(String, String)] = neuGeladen
            ? [("b1", "playlistItem0"), ("b2", "playlistItem1"), ("b3", "playlistItem2")]
            : [("b1", "playlistItem3"), ("b2", "playlistItem4"), ("b3", "playlistItem5")]
        server.stopp(stelle: 55, eintrag: "playlistItem1", schlange: a, t: t0.addingTimeInterval(15))
        server.start("b2", stelle: 0, eintrag: b[1].1, schlange: b, t: t0.addingTimeInterval(16))
        // Kam die Stoppmeldung nach dem Start an (beide ohne Warten
        // abgeschickt), steht die alte Schlange wieder da.
        if fassung == .spaeterStopp {
            server.stopp(stelle: 55, eintrag: "playlistItem1", schlange: a, t: t0.addingTimeInterval(16.2))
        }
        server.fortschritt("b2", eintrag: b[1].1, stelle: 10, t: t0.addingTimeInterval(26))
        return server
    }

    @Test("Läuft drüben ein anderes Lied als in der alten Schlange, zeigt der Stand dieses Lied",
          arguments: [(Sitzungsabbild.Fassung.master, false), (.master, true), (.spaeterStopp, false),
                      (.spaeterStopp, true), (.v10_11, false), (.v10_11, true)])
    func richtigesLied(fassung: Sitzungsabbild.Fassung, neuGeladen: Bool) throws {
        let server = Self.vorgeschichte(fassung, neuGeladen: neuGeladen)
        let t = Self.t0.addingTimeInterval(33.4)
        let json = try server.json(t)
        let sitzung = try #require(try Self.lesen(json).first)
        let stand = Fernstand(sitzung, jetzt: t)
        let protokoll = String(decoding: json, as: UTF8.self)
        #expect(stand.lied?.id == "b2", "\(protokoll)")
        // Was das Blatt zeigt: das Lied an `index` in `ids`.
        let gezeigt = stand.index.flatMap { stand.ids.indices.contains($0) ? stand.ids[$0] : nil }
        #expect(gezeigt == "b2", "Blatt zeigt \(gezeigt ?? "nichts") statt b2 — \(protokoll)")
        // „Dieses iPhone": dasselbe Lied an derselben Stelle (wahr: 17,4 s).
        let r = try #require(stand.rueckholung(jetzt: t), "nichts zum Zurückholen — \(protokoll)")
        #expect(r.ids[r.ab] == "b2")
        #expect(abs(r.stelle - 17.4) <= 1, "Stelle \(r.stelle) statt 17,4")
    }

    @Test("Die Schlange drüben gilt nur, wenn das laufende Lied darin an seinem Eintrag steht")
    func schlangeGeprueft() throws {
        let server = Self.vorgeschichte(.v10_11, neuGeladen: false)
        let s = try #require(try Self.abfrage(server, Self.t0.addingTimeInterval(30)).first)
        #expect(s.schlange == ["b1", "b2", "b3"])
        #expect(s.index == 1)
        let alt = try #require(try Self.abfrage(Self.vorgeschichte(.master, neuGeladen: true),
                                                Self.t0.addingTimeInterval(30)).first)
        // playlistItem1 steht in der alten Schlange bei a2 — das ist nicht b2.
        #expect(alt.index == nil)
    }

    // MARK: Tippen und Zurückholen

    /// Schritt 3: hier liegt noch die alte, angehaltene Schlange, drüben
    /// läuft b2 — ein Tipp steuert, statt a1–a3 wieder hinüberzuschicken.
    /// Angehalten zählt drüben nur eine Weile.
    @Test("Tipp aufs Gerät: was drüben läuft oder eben angehalten wurde, wird gesteuert")
    func tippSteuert() throws {
        var server = Self.vorgeschichte(.master, neuGeladen: true)
        var t = Self.t0.addingTimeInterval(30)
        var s = try #require(try Self.abfrage(server, t).first)
        s.abgefragt = t
        #expect(Uebergabe.art(hierSpielt: false, hierIstSchlange: true, dortSpielt: Uebergabe.dortAktiv(s)) == .steuern)
        server.fortschritt(stelle: 14, angehalten: true, t: t)
        t = t.addingTimeInterval(60)
        s = try #require(try Self.abfrage(server, t).first)
        s.abgefragt = t
        #expect(s.pausiertSeit != nil)
        #expect(Uebergabe.dortAktiv(s))
        t = t.addingTimeInterval(Uebergabe.pausenfrist)
        s.abgefragt = t
        #expect(!Uebergabe.dortAktiv(s))
        // Zwischen zwei Liedern (kein NowPlayingItem) ist drüben nichts —
        // deshalb fragt `Fernmodell.frischeSitzung` dann ein zweites Mal.
        server.stopp(stelle: 20, eintrag: "playlistItem1", schlange: [], t: t)
        s = try #require(try Self.abfrage(server, t).first)
        #expect(!Uebergabe.dortAktiv(s))
    }

    /// Schritte 1–4 an einem Stück: verbunden, drüben läuft b2 weiter,
    /// Abfragen im Takt, dann „Dieses iPhone" mit frischer Abfrage.
    @Test("Hier weiterhören: dasselbe Lied an derselben Stelle, auf 1 s", arguments: [Sitzungsabbild.Fassung.master, .v10_11])
    func hierWeiter(fassung: Sitzungsabbild.Fassung) throws {
        var server = Self.vorgeschichte(fassung, neuGeladen: true)
        // Wahr: b2 ab 0 s bei t0+16.
        func wahr(_ t: Date) -> TimeInterval { t.timeIntervalSince(Self.t0.addingTimeInterval(16)) }
        var t = Self.t0.addingTimeInterval(27.3)
        var stand = Fernstand(try #require(try Self.abfrage(server, t).first), jetzt: t)
        for schritt in 1 ... 20 {
            t = Self.t0.addingTimeInterval(27.3 + Double(schritt) * 2)
            if Int(wahr(t)) / 10 > Int(wahr(t - 2)) / 10 {
                let meldung = Self.t0.addingTimeInterval(16 + Double(Int(wahr(t)) / 10 * 10))
                server.fortschritt(stelle: wahr(meldung), t: meldung)
            }
            _ = stand.abgleichen(try Self.abfrage(server, t), jetzt: t)
            #expect(stand.index.map { stand.ids[$0] } == "b2")
        }
        // Zurückholen: frische Abfrage 0,4 s nach dem letzten Takt.
        t = t.addingTimeInterval(0.4)
        _ = stand.abgleichen(try Self.abfrage(server, t), jetzt: t)
        let r = try #require(stand.rueckholung(jetzt: t))
        #expect(r.ids[r.ab] == "b2")
        #expect(abs(r.stelle - wahr(t)) <= 1, "Stelle \(r.stelle) statt \(wahr(t))")
    }
}

// MARK: - Der nachgebaute Server

/// **Eine Sitzung, wie Jellyfins `SessionManager` sie führt** — nur, was
/// Connect liest. Siehe ``ConnectAblaufTests``.
struct Sitzungsabbild {
    enum Fassung: Sendable, CustomTestStringConvertible {
        /// 10.8 bis 10.11: Start und Stopp bringen die Schlange mit.
        case v10_11
        /// Wie 10.11, aber die Stoppmeldung des alten Liedes kam nach dem Start des neuen.
        case spaeterStopp
        /// `master`: nur der Stopp setzt die Schlange.
        case master

        var testDescription: String {
            switch self {
            case .v10_11: "10.11"
            case .spaeterStopp: "10.11, Stopp nach Start"
            case .master: "master"
            }
        }
    }

    let fassung: Fassung
    var lied: String?
    /// `PositionTicks` der letzten echten Meldung, in Sekunden.
    var gemeldet: TimeInterval = 0
    var meldung: Date?
    var angehalten = false
    var pausiertSeit: Date?
    var schlange: [(id: String, eintrag: String)] = []
    var eintrag: String?
    var regung: Date?

    init(fassung: Fassung) { self.fassung = fassung }

    /// `POST /Sessions/Playing`.
    mutating func start(_ id: String, stelle: TimeInterval, eintrag: String,
                        schlange: [(String, String)], t: Date) {
        aktualisieren(id, stelle: stelle, angehalten: false, eintrag: eintrag, t: t)
        if fassung != .master, !schlange.isEmpty { self.schlange = schlange.map { (id: $0.0, eintrag: $0.1) } }
    }

    /// `POST /Sessions/Playing/Progress` — Jellyfin-Web ohne Schlange.
    /// Jellyfin-Web schickt Lied und Eintrag mit — auch wenn der Server
    /// nach einem späten Stopp gerade keins mehr kennt.
    mutating func fortschritt(_ id: String? = nil, eintrag: String? = nil, stelle: TimeInterval,
                              angehalten: Bool = false, t: Date) {
        guard let id = id ?? lied else { return }
        aktualisieren(id, stelle: stelle, angehalten: angehalten, eintrag: eintrag ?? self.eintrag ?? "", t: t)
    }

    /// `POST /Sessions/Playing/Stopped`.
    mutating func stopp(stelle: TimeInterval, eintrag: String, schlange: [(String, String)], t: Date) {
        self.schlange = schlange.map { (id: $0.0, eintrag: $0.1) }
        self.eintrag = eintrag
        lied = nil
        gemeldet = 0
        angehalten = false
        regung = t
    }

    private mutating func aktualisieren(_ id: String, stelle: TimeInterval, angehalten: Bool,
                                        eintrag: String, t: Date) {
        lied = id
        regung = t
        meldung = t
        if angehalten, pausiertSeit == nil { pausiertSeit = t } else if !angehalten { pausiertSeit = nil }
        self.angehalten = angehalten
        gemeldet = stelle
        self.eintrag = eintrag
    }

    /// `PositionTicks` zur Zeit `t`: der Server zählt jede volle Sekunde
    /// nach der Meldung eine Sekunde dazu, nie bis ans Ende.
    func positionTicks(_ t: Date) -> Int64 {
        var s = gemeldet
        if let lied, !angehalten, let meldung {
            var schritte = max(0, floor(t.timeIntervalSince(meldung)))
            let laenge = ConnectAblaufTests.laengen[lied] ?? .infinity
            while schritte > 0, gemeldet + schritte >= laenge { schritte -= 1 }
            s += schritte
        }
        return Int64((s * 10_000_000).rounded())
    }

    func json(_ t: Date) throws -> Data {
        let zeit = ISO8601DateFormatter()
        zeit.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var s: [String: Any] = [
            "Id": "s-mac", "UserId": "u1", "DeviceId": "mac-1", "DeviceName": "Anna’s MacBook",
            "Client": "Jellyfin Web", "SupportsRemoteControl": true,
            "PlayableMediaTypes": ["Audio", "Video"],
            "PlayState": ["PositionTicks": positionTicks(t), "IsPaused": angehalten,
                          "RepeatMode": "RepeatNone", "PlaybackOrder": "Default"] as [String: Any],
            "NowPlayingQueue": schlange.map { ["Id": $0.id, "PlaylistItemId": $0.eintrag] },
            "LastActivityDate": zeit.string(from: regung ?? t),
            "LastPlaybackCheckIn": meldung.map { zeit.string(from: $0) } ?? "0001-01-01T00:00:00.0000000Z",
        ]
        if let eintrag { s["PlaylistItemId"] = eintrag }
        if let pausiertSeit { s["LastPausedDate"] = zeit.string(from: pausiertSeit) }
        if let lied {
            s["NowPlayingItem"] = ["Id": lied, "Name": lied, "Type": "Audio", "MediaType": "Audio",
                                   "RunTimeTicks": Int64((ConnectAblaufTests.laengen[lied] ?? 0) * 10_000_000)]
        }
        return try JSONSerialization.data(withJSONObject: [s], options: [.sortedKeys])
    }
}
