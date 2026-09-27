import Foundation
@testable import MusikKit
import Network

/// **Ein Sonos-Haushalt zum Testen** — echte HTTP-Server auf 127.0.0.1,
/// einer je Lautsprecher, die SOAP annehmen und ihren Zustand halten:
/// was geladen ist, ob es spielt, die Stelle, die Lautstärke, wer mit wem
/// gruppiert ist. Nachgebaut nach dem, was svrooij und SoCo über die
/// Schnittstelle sagen — nicht nach einem echten Gerät.
final class ScheinHaushalt: @unchecked Sendable {

    struct Lautsprecher {
        let id: String
        let name: String
        var port: UInt16 = 0
        var gruppe: String
        var zustand = "STOPPED"
        var adresse = ""
        var metadaten = ""
        var naechste = ""
        var naechsteMetadaten = ""
        var stelle: TimeInterval = 0
        var lautstaerke = 20
        /// Die Sonos-Warteschlange: Adresse und Metadaten je Lied.
        var warteschlange: [(adresse: String, metadaten: String)] = []
        /// Das laufende Lied darin, ab 1.
        var nummer = 0
        var modus = "NORMAL"

        var ausSchlange: Bool { adresse.hasPrefix("x-rincon-queue:") }
        var spur: String {
            ausSchlange ? (warteschlange.indices.contains(nummer - 1) ? warteschlange[nummer - 1].adresse : "") : adresse
        }
        var spurMetadaten: String {
            ausSchlange ? (warteschlange.indices.contains(nummer - 1) ? warteschlange[nummer - 1].metadaten : "") : metadaten
        }
    }

    /// Kann dieser Haushalt keine Warteschlange (lehnt `AddURIToQueue` ab)?
    var ohneWarteschlange = false

    private let schloss = NSLock()
    private var geraete: [String: Lautsprecher] = [:]
    private var reihenfolge: [String] = []
    private var lauscher: [NWListener] = []
    /// Jede angenommene Aktion, der Reihe nach — „Play", „Seek" …
    private var protokoll: [String] = []

    /// Legt die Lautsprecher an und startet ihre Server.
    init(_ namen: [String]) async throws {
        for (i, name) in namen.enumerated() {
            let id = "RINCON_SCHEIN\(i)01400"
            geraete[id] = Lautsprecher(id: id, name: name, gruppe: id)
            reihenfolge.append(id)
        }
        for id in reihenfolge {
            let (l, port) = try await Self.lauschen { [weak self] anfrage in
                self?.beantworten(id, anfrage) ?? (500, "")
            }
            lauscher.append(l)
            schloss.withLock { geraete[id]?.port = port }
        }
    }

    deinit { lauscher.forEach { $0.cancel() } }

    func id(_ name: String) -> String { reihenfolge.first { geraete[$0]?.name == name }! }

    func lautsprecher(_ name: String) -> SonosLautsprecher {
        schloss.withLock {
            let g = geraete[reihenfolge.first { geraete[$0]?.name == name }!]!
            return SonosLautsprecher(id: g.id, name: g.name, basis: URL(string: "http://127.0.0.1:\(g.port)")!)
        }
    }

    func zustand(_ name: String) -> Lautsprecher { schloss.withLock { geraete[id(name)]! } }
    var aktionen: [String] { schloss.withLock { protokoll } }

    // MARK: Was außerhalb passiert

    /// Das laufende Lied ist zu Ende: das nächste rückt nach — aus der
    /// Warteschlange, oder im Rückfall das gesetzte nächste.
    func liedZuEnde(_ name: String) {
        schloss.withLock {
            var g = geraete[id(name)]!
            if g.ausSchlange {
                g.stelle = 0
                if g.modus == "REPEAT_ONE" {
                } else if g.nummer < g.warteschlange.count {
                    g.nummer += 1
                } else if g.modus == "REPEAT_ALL" {
                    g.nummer = 1
                } else {
                    g.zustand = "STOPPED"
                }
                geraete[g.id] = g
                return
            }
            g.adresse = g.naechste
            g.metadaten = g.naechsteMetadaten
            g.naechste = ""
            g.naechsteMetadaten = ""
            g.stelle = 0
            g.zustand = g.adresse.isEmpty ? "STOPPED" : "PLAYING"
            geraete[g.id] = g
        }
    }

    /// Jemand spielt in der Sonos-App etwas anderes.
    func fremdSpielen(_ name: String) {
        schloss.withLock {
            geraete[id(name)]!.adresse = "x-sonos-spotify:spotify%3atrack%3a123"
            geraete[id(name)]!.naechste = ""
            geraete[id(name)]!.zustand = "PLAYING"
        }
    }

    func weiterlaufen(_ name: String, sekunden: TimeInterval) {
        schloss.withLock { geraete[id(name)]!.stelle += sekunden }
    }

    // MARK: SOAP

    private func beantworten(_ id: String, _ anfrage: Anfrage) -> (Int, String) {
        schloss.lock()
        defer { schloss.unlock() }
        if anfrage.methode == "GET" {
            let g = geraete[id]!
            return (200, "<?xml version=\"1.0\"?><root><device><roomName>\(g.name)</roomName>"
                + "<modelName>Schein</modelName><UDN>uuid:\(id)</UDN></device></root>")
        }
        let aktion = anfrage.soapAction.split(separator: "#").last.map { $0.replacingOccurrences(of: "\"", with: "") } ?? ""
        let dienst = anfrage.soapAction.split(separator: "#").first.map { $0.replacingOccurrences(of: "\"", with: "") } ?? ""
        guard let baum = SonosKnoten.lesen(anfrage.rumpf), let knoten = baum.finde(aktion) else { return fehler(402) }
        var a: [String: String] = [:]
        for k in knoten.kinder { a[k.name] = k.text }
        protokoll.append(aktion)
        var g = geraete[id]!
        var aus: [(String, String)] = []

        switch aktion {
        case "SetAVTransportURI":
            let uri = a["CurrentURI"] ?? ""
            if uri.hasPrefix("x-rincon-queue:") {
                g.gruppe = id
                g.adresse = uri
                g.naechste = ""
                g.zustand = "STOPPED"
                g.nummer = g.warteschlange.isEmpty ? 0 : 1
                g.stelle = 0
            } else if uri.hasPrefix("x-rincon:") {
                let ziel = String(uri.dropFirst("x-rincon:".count))
                guard let k = geraete[ziel] else { return fehler(701) }
                g.gruppe = k.gruppe
                g.zustand = "PLAYING"
            } else {
                // Eigene Adresse: raus aus jeder Gruppe.
                g.gruppe = id
                g.adresse = uri
                g.metadaten = a["CurrentURIMetaData"] ?? ""
                g.naechste = ""
                g.zustand = "STOPPED"
                g.stelle = 0
            }
        case "RemoveAllTracksFromQueue":
            g.warteschlange = []
            g.nummer = 0
        case "AddURIToQueue":
            guard !ohneWarteschlange else { return fehler(800) }
            g.warteschlange.append((a["EnqueuedURI"] ?? "", a["EnqueuedURIMetaData"] ?? ""))
            aus = [("FirstTrackNumberEnqueued", String(g.warteschlange.count)), ("NumTracksAdded", "1"),
                   ("NewQueueLength", String(g.warteschlange.count))]
        case "AddMultipleURIsToQueue":
            guard !ohneWarteschlange else { return fehler(800) }
            let n = Int(a["NumberOfURIs"] ?? "") ?? 0
            let uris = (a["EnqueuedURIs"] ?? "").split(separator: " ").map(String.init)
            // Die Metadaten stehen mit Leerzeichen hintereinander — getrennt
            // wird am Ende jedes DIDL-Lite.
            let ende = "</DIDL-Lite>"
            let metas = (a["EnqueuedURIsMetaData"] ?? "").components(separatedBy: ende + " ")
                .map { $0.hasSuffix(ende) ? $0 : $0 + ende }
            guard uris.count == n, metas.count == n else { return fehler(402) }
            let erste = g.warteschlange.count + 1
            g.warteschlange += zip(uris, metas).map { ($0, $1) }
            aus = [("FirstTrackNumberEnqueued", String(erste)), ("NumTracksAdded", String(n)),
                   ("NewQueueLength", String(g.warteschlange.count)), ("NewUpdateID", "1")]
        case "RemoveTrackRangeFromQueue":
            let ab = (Int(a["StartingIndex"] ?? "") ?? 0) - 1
            let n = Int(a["NumberOfTracks"] ?? "") ?? 0
            guard ab >= 0, ab + n <= g.warteschlange.count else { return fehler(701) }
            g.warteschlange.removeSubrange(ab ..< ab + n)
            aus = [("NewUpdateID", "2")]
        case "SetNextAVTransportURI":
            g.naechste = a["NextURI"] ?? ""
            g.naechsteMetadaten = a["NextURIMetaData"] ?? ""
        case "Play":
            guard g.gruppe == id else { return fehler(800) }
            guard !g.spur.isEmpty else { return fehler(701) }
            // Eine Adresse, an die er nicht herankommt: er versucht es und steht.
            g.zustand = g.spur.contains("unerreichbar") ? "STOPPED" : "PLAYING"
        case "Pause": g.zustand = "PAUSED_PLAYBACK"
        case "Stop": g.zustand = "STOPPED"
        case "Seek" where a["Unit"] == "TRACK_NR":
            guard g.ausSchlange, let n = Int(a["Target"] ?? ""), n >= 1, n <= g.warteschlange.count else {
                return fehler(701)
            }
            g.nummer = n
            g.stelle = 0
        case "Seek":
            guard !g.adresse.isEmpty, let s = SonosZeit.lesen(a["Target"]) else { return fehler(701) }
            g.stelle = s
        case "SetPlayMode": g.modus = a["NewPlayMode"] ?? "NORMAL"
        case "GetTransportInfo":
            aus = [("CurrentTransportState", g.zustand), ("CurrentTransportStatus", "OK"), ("CurrentSpeed", "1")]
        case "GetPositionInfo":
            aus = [("Track", String(g.ausSchlange ? g.nummer : 1)), ("TrackDuration", "0:03:00"),
                   ("TrackMetaData", g.spurMetadaten),
                   ("TrackURI", g.spur), ("RelTime", SonosZeit.schreiben(g.stelle)),
                   ("AbsTime", "NOT_IMPLEMENTED")]
        case "GetMediaInfo":
            aus = [("NrTracks", String(g.ausSchlange ? g.warteschlange.count : 1)), ("CurrentURI", g.adresse), ("CurrentURIMetaData", g.metadaten),
                   ("NextURI", g.naechste), ("NextURIMetaData", g.naechsteMetadaten)]
        case "DelegateGroupCoordinationTo":
            guard g.gruppe == id, let neu = a["NewCoordinator"], geraete[neu]?.gruppe == id else { return fehler(800) }
            for m in reihenfolge where geraete[m]!.gruppe == id { geraete[m]!.gruppe = neu }
            geraete[neu]!.adresse = g.ausSchlange ? "x-rincon-queue:\(neu)#0" : g.adresse
            geraete[neu]!.metadaten = g.metadaten
            geraete[neu]!.naechste = g.naechste
            geraete[neu]!.naechsteMetadaten = g.naechsteMetadaten
            geraete[neu]!.zustand = g.zustand
            geraete[neu]!.stelle = g.stelle
            geraete[neu]!.warteschlange = g.warteschlange
            geraete[neu]!.nummer = g.nummer
            geraete[neu]!.modus = g.modus
            if a["RejoinGroup"] == "1" {
                g.gruppe = neu
                g.adresse = "x-rincon:\(neu)"
            } else {
                // Allein und still — und mit leerer Warteschlange, die trotzdem
                // `Track` 1 meldet, wie ein echter.
                g.gruppe = id
                g.adresse = "x-rincon-queue:\(id)#0"
                g.warteschlange = []
                g.nummer = 1
                g.zustand = "STOPPED"
                g.stelle = 0
            }
        case "BecomeCoordinatorOfStandaloneGroup":
            let andere = reihenfolge.filter { $0 != id && geraete[$0]!.gruppe == g.gruppe }
            if g.gruppe == id, let neu = andere.first {
                // Der Koordinator geht: die Gruppe spielt beim nächsten weiter.
                for m in andere { geraete[m]!.gruppe = neu }
                geraete[neu]!.adresse = g.adresse
                geraete[neu]!.metadaten = g.metadaten
                geraete[neu]!.naechste = g.naechste
                geraete[neu]!.naechsteMetadaten = g.naechsteMetadaten
                geraete[neu]!.zustand = g.zustand
                geraete[neu]!.stelle = g.stelle
                geraete[neu]!.warteschlange = g.warteschlange
                geraete[neu]!.nummer = g.nummer
                if g.ausSchlange { geraete[neu]!.adresse = "x-rincon-queue:\(neu)#0" }
                g.adresse = ""
                g.naechste = ""
                g.zustand = "STOPPED"
                aus = [("DelegatedGroupCoordinatorID", neu), ("NewGroupID", "\(id):9")]
            } else {
                aus = [("DelegatedGroupCoordinatorID", ""), ("NewGroupID", "\(id):9")]
            }
            g.gruppe = id
        case "GetVolume": aus = [("CurrentVolume", String(g.lautstaerke))]
        case "SetVolume": g.lautstaerke = Int(a["DesiredVolume"] ?? "") ?? g.lautstaerke
        case "GetGroupVolume":
            let m = reihenfolge.filter { geraete[$0]!.gruppe == g.gruppe }.map { $0 == id ? g.lautstaerke : geraete[$0]!.lautstaerke }
            aus = [("CurrentVolume", String(m.reduce(0, +) / max(m.count, 1)))]
        case "SnapshotGroupVolume": break
        case "SetGroupVolume":
            let wert = Int(a["DesiredVolume"] ?? "") ?? 0
            for m in reihenfolge where geraete[m]!.gruppe == g.gruppe { geraete[m]!.lautstaerke = wert }
            g.lautstaerke = wert
        case "GetZoneGroupState":
            geraete[id] = g
            aus = [("ZoneGroupState", zonenstand())]
        default:
            return fehler(401)
        }
        geraete[id] = g
        let werte = aus.map { "<\($0.0)>\(SonosText.maskieren($0.1))</\($0.0)>" }.joined()
        return (200, "<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body>"
            + "<u:\(aktion)Response xmlns:u=\"\(dienst)\">\(werte)</u:\(aktion)Response></s:Body></s:Envelope>")
    }

    private func zonenstand() -> String {
        let koordinatoren = reihenfolge.filter { geraete[$0]!.gruppe == $0 }
        var xml = "<ZoneGroupState><ZoneGroups>"
        for k in koordinatoren {
            xml += "<ZoneGroup Coordinator=\"\(k)\" ID=\"\(k):1\">"
            for m in reihenfolge where geraete[m]!.gruppe == k {
                let g = geraete[m]!
                xml += "<ZoneGroupMember UUID=\"\(m)\" Location=\"http://127.0.0.1:\(g.port)/xml/device_description.xml\" ZoneName=\"\(g.name)\"/>"
            }
            xml += "</ZoneGroup>"
        }
        return xml + "</ZoneGroups></ZoneGroupState>"
    }

    private func fehler(_ code: Int) -> (Int, String) {
        (500, "<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body>"
            + "<s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail>"
            + "<UPnPError xmlns=\"urn:schemas-upnp-org:control-1-0\"><errorCode>\(code)</errorCode></UPnPError>"
            + "</detail></s:Fault></s:Body></s:Envelope>")
    }

    // MARK: HTTP

    struct Anfrage: Sendable {
        let methode: String
        let soapAction: String
        let rumpf: Data
    }

    private final class Puffer: @unchecked Sendable { var daten = Data() }

    /// Ein HTTP-Server auf 127.0.0.1, freier Port. Eine Anfrage je
    /// Verbindung, danach zu.
    static func lauschen(_ antwort: @escaping @Sendable (Anfrage) -> (Int, String)) async throws -> (NWListener, UInt16) {
        let p = NWParameters.tcp
        p.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let l = try NWListener(using: p)
        let schlange = DispatchQueue(label: "schein-sonos")
        l.newConnectionHandler = { v in
            v.start(queue: schlange)
            lesen(v, Puffer(), antwort)
        }
        return try await withCheckedThrowingContinuation { fortsetzung in
            let einmal = Puffer()
            l.stateUpdateHandler = { lage in
                guard einmal.daten.isEmpty else { return }
                switch lage {
                case .ready:
                    einmal.daten = Data([1])
                    fortsetzung.resume(returning: (l, l.port?.rawValue ?? 0))
                case let .failed(e):
                    einmal.daten = Data([1])
                    fortsetzung.resume(throwing: e)
                default: break
                }
            }
            l.start(queue: schlange)
        }
    }

    private static func lesen(_ v: NWConnection, _ puffer: Puffer,
                              _ antwort: @escaping @Sendable (Anfrage) -> (Int, String)) {
        v.receive(minimumIncompleteLength: 1, maximumLength: 65536) { daten, _, fertig, fehler in
            if let daten { puffer.daten.append(daten) }
            if let anfrage = zerlegen(puffer.daten) {
                let (status, text) = antwort(anfrage)
                let rumpf = Data(text.utf8)
                let kopf = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Internal Server Error")\r\n"
                    + "Content-Type: text/xml; charset=\"utf-8\"\r\nContent-Length: \(rumpf.count)\r\n"
                    + "Connection: close\r\n\r\n"
                v.send(content: Data(kopf.utf8) + rumpf, completion: .contentProcessed { _ in v.cancel() })
                return
            }
            if fertig || fehler != nil { v.cancel(); return }
            lesen(v, puffer, antwort)
        }
    }

    private static func zerlegen(_ daten: Data) -> Anfrage? {
        guard let trenner = daten.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let kopf = String(decoding: daten[..<trenner.lowerBound], as: UTF8.self)
        var zeilen = kopf.components(separatedBy: "\r\n")
        let erste = zeilen.removeFirst().split(separator: " ")
        var felder: [String: String] = [:]
        for z in zeilen {
            guard let d = z.firstIndex(of: ":") else { continue }
            felder[z[..<d].lowercased()] = z[z.index(after: d)...].trimmingCharacters(in: .whitespaces)
        }
        let laenge = Int(felder["content-length"] ?? "0") ?? 0
        let rumpf = daten[trenner.upperBound...]
        guard rumpf.count >= laenge else { return nil }
        return Anfrage(methode: erste.first.map(String.init) ?? "", soapAction: felder["soapaction"] ?? "",
                       rumpf: Data(rumpf.prefix(laenge)))
    }
}
