import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// **Ein Sonos-Lautsprecher, angesprochen über seine lokale Schnittstelle**
/// (`http://ip:1400`, SOAP). Ein Actor je Lautsprecher: Befehle an ihn gehen
/// der Reihe nach, und ein abgebrochener Aufgabenbaum bricht auch die
/// Anfrage ab.
///
/// Keine Adresse, die hier hindurchgeht, landet im Protokoll — die zum
/// Server tragen das Zugangsmerkmal.
public actor SonosClient {
    public nonisolated let basis: URL
    let sitzung: URLSession

    public init(basis: URL, sitzung: URLSession = SonosClient.standardsitzung) {
        self.basis = basis
        self.sitzung = sitzung
    }

    /// Kurze Fristen: ein Lautsprecher im selben Netz antwortet in
    /// Millisekunden. Wer nach vier Sekunden nichts sagt, ist weg.
    public static let standardsitzung: URLSession = {
        let k = URLSessionConfiguration.ephemeral
        k.timeoutIntervalForRequest = 4
        k.timeoutIntervalForResource = 8
        k.waitsForConnectivity = false
        k.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: k)
    }()

    // MARK: - Senden

    @discardableResult
    func senden(_ anfrage: SonosAnfrage) async throws -> [String: String] {
        let (daten, antwort): (Data, URLResponse)
        do {
            (daten, antwort) = try await sitzung.data(for: anfrage.urlRequest(basis: basis))
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SonosFehler.nichtErreichbar
        }
        let status = (antwort as? HTTPURLResponse)?.statusCode ?? 0
        return try SonosSoap.antwort(daten, status: status, aktion: anfrage.aktion)
    }

    @discardableResult
    private func avt(_ aktion: String, _ werte: KeyValuePairs<String, String> = ["InstanceID": "0"]) async throws -> [String: String] {
        try await senden(SonosSoap.anfrage(.avTransport, aktion, werte))
    }

    // MARK: - Wer bist du

    public func beschreibung() async throws -> SonosBeschreibung {
        var r = URLRequest(url: basis.appendingPathComponent("xml/device_description.xml"), timeoutInterval: 4)
        r.httpMethod = "GET"
        let daten: Data
        do {
            (daten, _) = try await sitzung.data(for: r)
        } catch {
            throw SonosFehler.nichtErreichbar
        }
        guard let b = SonosBeschreibung.lesen(daten) else { throw SonosFehler.unlesbar }
        return b
    }

    /// Alle Gruppen im Haushalt — jeder Lautsprecher kennt sie.
    public func gruppen() async throws -> [SonosGruppe] {
        let w = try await senden(SonosSoap.anfrage(.zoneGroupTopology, "GetZoneGroupState"))
        return SonosTopologie.gruppen(w["ZoneGroupState"] ?? "")
    }

    // MARK: - Abspielen (nur am Koordinator)

    public func laden(_ adresse: String, metadaten: String) async throws {
        try await avt("SetAVTransportURI", ["InstanceID": "0", "CurrentURI": adresse,
                                            "CurrentURIMetaData": metadaten])
    }

    /// Das nächste Lied — leere Adresse nimmt es weg.
    public func naechstesLaden(_ adresse: String, metadaten: String) async throws {
        try await avt("SetNextAVTransportURI", ["InstanceID": "0", "NextURI": adresse,
                                                "NextURIMetaData": metadaten])
    }

    public func abspielen() async throws { try await avt("Play", ["InstanceID": "0", "Speed": "1"]) }
    public func pausieren() async throws { try await avt("Pause") }
    public func stoppen() async throws { try await avt("Stop") }

    public func springen(_ sekunden: TimeInterval) async throws {
        try await avt("Seek", ["InstanceID": "0", "Unit": "REL_TIME", "Target": SonosZeit.schreiben(sekunden)])
    }

    /// Im Rückfall mit einzelnen Adressen wiederholt und mischt unsere Schlange.
    public func normalerLauf() async throws {
        try await spielmodus("NORMAL")
    }

    /// Transport, Stelle und geladene Adressen in einem Zug.
    public func lage() async throws -> SonosLage {
        async let t = avt("GetTransportInfo")
        async let p = avt("GetPositionInfo")
        async let m = avt("GetMediaInfo")
        let (transport, position, medien) = try await (t, p, m)
        return SonosLage(zustand: .init(transport["CurrentTransportState"]),
                         spur: position["TrackURI"],
                         geladen: medien["CurrentURI"], naechstesGeladen: medien["NextURI"],
                         stelle: SonosZeit.lesen(position["RelTime"]) ?? 0,
                         dauer: SonosZeit.lesen(position["TrackDuration"]).flatMap { $0 > 0 ? $0 : nil },
                         nummer: position["Track"].flatMap { Int($0) })
    }

    // MARK: - Warteschlange (nur am Koordinator)

    /// Ein Lied für die Warteschlange: Adresse und DIDL-Lite.
    public typealias Eintrag = (adresse: String, metadaten: String)

    /// So viele gehen je `AddMultipleURIsToQueue` — dieselbe Grenze wie in
    /// SoCo (`add_multiple_to_queue`, 16).
    public static let buendel = 16

    public func schlangeLeeren() async throws {
        try await avt("RemoveAllTracksFromQueue")
    }

    /// **Hinten anfügen**, in Bündeln. Adressen und Metadaten stehen je mit
    /// einem Leerzeichen getrennt in einem Feld, wie SoCo es schickt.
    /// Lehnt der Lautsprecher das ab, geht es einzeln (`AddURIToQueue`).
    public func anfuegen(_ eintraege: [Eintrag]) async throws {
        var rest = eintraege[...]
        while !rest.isEmpty {
            let teil = Array(rest.prefix(Self.buendel))
            rest = rest.dropFirst(teil.count)
            do {
                try await avt("AddMultipleURIsToQueue", [
                    "InstanceID": "0", "UpdateID": "0", "NumberOfURIs": String(teil.count),
                    "EnqueuedURIs": teil.map(\.adresse).joined(separator: " "),
                    "EnqueuedURIsMetaData": teil.map(\.metadaten).joined(separator: " "),
                    "ContainerURI": "", "ContainerMetaData": "",
                    "DesiredFirstTrackNumberEnqueued": "0", "EnqueueAsNext": "0",
                ])
            } catch SonosFehler.abgelehnt {
                for e in teil {
                    try await avt("AddURIToQueue", [
                        "InstanceID": "0", "EnqueuedURI": e.adresse, "EnqueuedURIMetaData": e.metadaten,
                        "DesiredFirstTrackNumberEnqueued": "0", "EnqueueAsNext": "0",
                    ])
                }
            }
        }
    }

    /// `anzahl` Lieder ab Nummer `ab` (1-basiert) heraus.
    public func bereichEntfernen(ab: Int, anzahl: Int) async throws {
        guard anzahl > 0 else { return }
        try await avt("RemoveTrackRangeFromQueue", ["InstanceID": "0", "UpdateID": "0",
                                                    "StartingIndex": String(ab), "NumberOfTracks": String(anzahl)])
    }

    /// Die Warteschlange als Quelle — danach spielt der Lautsprecher sie
    /// ohne Zutun durch.
    public func schlangeWaehlen(_ koordinator: String) async throws {
        try await laden("x-rincon-queue:\(koordinator)#0", metadaten: "")
    }

    /// Zu Lied `nummer` (1-basiert) der Warteschlange.
    public func zuNummer(_ nummer: Int) async throws {
        try await avt("Seek", ["InstanceID": "0", "Unit": "TRACK_NR", "Target": String(nummer)])
    }

    public func spielmodus(_ modus: String) async throws {
        try await avt("SetPlayMode", ["InstanceID": "0", "NewPlayMode": modus])
    }

    // MARK: - Gruppieren

    /// **Diesen Lautsprecher zur Gruppe von `koordinator` holen** — er
    /// spielt dann, was der Koordinator spielt.
    public func beitreten(_ koordinator: String) async throws {
        try await laden("x-rincon:\(koordinator)", metadaten: "")
    }

    /// **Die Gruppe an `neuer` abgeben** — nur am Koordinator. Warteschlange,
    /// Lied und Stelle gehen mit, die Gruppe spielt ohne Pause weiter.
    /// `RejoinGroup=0`: dieser Lautsprecher steht danach allein und still.
    public func koordinationAbgeben(an neuer: String) async throws {
        try await avt("DelegateGroupCoordinationTo", ["InstanceID": "0", "NewCoordinator": neuer, "RejoinGroup": "0"])
    }

    /// Aus seiner Gruppe lösen; er steht danach allein und still da.
    public func alleinstellen() async throws {
        try await avt("BecomeCoordinatorOfStandaloneGroup")
    }

    // MARK: - Lautstärke

    public func lautstaerke() async throws -> Int {
        let w = try await senden(SonosSoap.anfrage(.renderingControl, "GetVolume",
                                                   ["InstanceID": "0", "Channel": "Master"]))
        return Int(w["CurrentVolume"] ?? "") ?? 0
    }

    public func lautstaerkeSetzen(_ wert: Int) async throws {
        try await senden(SonosSoap.anfrage(.renderingControl, "SetVolume",
                                           ["InstanceID": "0", "Channel": "Master",
                                            "DesiredVolume": String(min(max(wert, 0), 100))]))
    }

    /// Die Lautstärke der ganzen Gruppe — nur am Koordinator.
    public func gruppenlautstaerke() async throws -> Int {
        let w = try await senden(SonosSoap.anfrage(.groupRenderingControl, "GetGroupVolume", ["InstanceID": "0"]))
        return Int(w["CurrentVolume"] ?? "") ?? 0
    }

    /// **Vorher ein Schnappschuss**, sonst verteilt Sonos die Änderung nicht
    /// im Verhältnis der einzelnen Lautstärken (svrooij, GroupRenderingControl).
    public func gruppenlautstaerkeSetzen(_ wert: Int) async throws {
        try await senden(SonosSoap.anfrage(.groupRenderingControl, "SnapshotGroupVolume", ["InstanceID": "0"]))
        try await senden(SonosSoap.anfrage(.groupRenderingControl, "SetGroupVolume",
                                           ["InstanceID": "0", "DesiredVolume": String(min(max(wert, 0), 100))]))
    }
}
