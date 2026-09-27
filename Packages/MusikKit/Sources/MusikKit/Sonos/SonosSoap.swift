import Foundation

// Die lokale Schnittstelle eines Sonos-Lautsprechers: UPnP über SOAP, Port
// 1400. Nachgelesen bei svrooij, „sonos-api-docs" (sonos.svrooij.io), und in
// SoCo (Python, MIT-Lizenz, github.com/SoCo/SoCo) — Aufbau der Hülle,
// Pfade und Namen der Dienste folgen dort `soco/services.py`.

/// **Die Dienste, die Swiftly Music braucht** — jeder mit seinem Pfad und
/// seinem Namen für den `SOAPACTION`-Kopf.
public enum SonosDienst: String, Sendable, CaseIterable {
    case avTransport = "AVTransport"
    case renderingControl = "RenderingControl"
    case groupRenderingControl = "GroupRenderingControl"
    case zoneGroupTopology = "ZoneGroupTopology"

    public var pfad: String {
        switch self {
        case .avTransport: "/MediaRenderer/AVTransport/Control"
        case .renderingControl: "/MediaRenderer/RenderingControl/Control"
        case .groupRenderingControl: "/MediaRenderer/GroupRenderingControl/Control"
        case .zoneGroupTopology: "/ZoneGroupTopology/Control"
        }
    }

    public var art: String { "urn:schemas-upnp-org:service:\(rawValue):1" }
}

/// Eine fertige Anfrage: wohin, welcher `SOAPACTION`, welcher Rumpf.
public struct SonosAnfrage: Sendable, Equatable {
    public let dienst: SonosDienst
    public let aktion: String
    public let rumpf: String

    public var pfad: String { dienst.pfad }
    public var soapAction: String { "\"\(dienst.art)#\(aktion)\"" }

    /// Die Anfrage an den Lautsprecher unter `basis` (`http://ip:1400`).
    public func urlRequest(basis: URL, frist: TimeInterval = 4) -> URLRequest {
        var r = URLRequest(url: basis.appendingPathComponent(String(dienst.pfad.dropFirst())),
                           timeoutInterval: frist)
        r.httpMethod = "POST"
        r.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        r.setValue(soapAction, forHTTPHeaderField: "SOAPACTION")
        r.httpBody = Data(rumpf.utf8)
        return r
    }
}

public enum SonosFehler: Error, Sendable, Equatable {
    /// Der Lautsprecher hat abgelehnt — mit dem UPnP-Fehlercode, wenn er einen nennt.
    case abgelehnt(status: Int, upnp: Int?)
    /// Die Antwort war kein SOAP, das wir lesen können.
    case unlesbar
    /// Keine Antwort (aus, anderes Netz, keine Freigabe fürs lokale Netz).
    case nichtErreichbar

    /// **716 „Resource not found", 714 „Illegal MIME-type"** — der
    /// Lautsprecher kommt an die Adresse nicht heran oder kann das Format
    /// nicht. Beides heißt für uns: der Server ist von dort nicht erreichbar
    /// oder liefert etwas, das Sonos nicht spielt.
    public var quelleUnerreichbar: Bool {
        if case let .abgelehnt(_, upnp) = self, let upnp { return [701, 714, 716].contains(upnp) }
        return false
    }
}

public enum SonosSoap {

    /// **Die Hülle.** Werte werden maskiert; die Reihenfolge der Argumente
    /// zählt — Sonos liest sie nach Stellung, nicht nach Namen.
    public static func anfrage(_ dienst: SonosDienst, _ aktion: String,
                               _ werte: KeyValuePairs<String, String> = [:]) -> SonosAnfrage {
        var argumente = ""
        for (name, wert) in werte {
            argumente += "<\(name)>\(SonosText.maskieren(wert))</\(name)>"
        }
        let rumpf = "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
            + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\""
            + " s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
            + "<s:Body><u:\(aktion) xmlns:u=\"\(dienst.art)\">\(argumente)</u:\(aktion)></s:Body>"
            + "</s:Envelope>"
        return SonosAnfrage(dienst: dienst, aktion: aktion, rumpf: rumpf)
    }

    /// **Die Werte einer Antwort**: die Kinder von `<u:{Aktion}Response>`
    /// als Name → Text. Ein `s:Fault` wird zum ``SonosFehler``.
    public static func antwort(_ daten: Data, status: Int, aktion: String) throws -> [String: String] {
        let baum = SonosKnoten.lesen(daten)
        guard (200 ..< 300).contains(status) else {
            let code = baum?.wert("errorCode").flatMap { Int($0) }
            throw SonosFehler.abgelehnt(status: status, upnp: code)
        }
        guard let baum, let antwort = baum.finde(aktion + "Response") else {
            throw SonosFehler.unlesbar
        }
        var werte: [String: String] = [:]
        for k in antwort.kinder { werte[k.name] = k.text }
        return werte
    }
}

// MARK: - Zeit

public enum SonosZeit {
    /// „0:03:21", „00:03:21.000", „NOT_IMPLEMENTED" → Sekunden oder `nil`.
    public static func lesen(_ text: String?) -> TimeInterval? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let teile = text.split(separator: ":")
        guard teile.count == 3, let h = Double(teile[0]), let m = Double(teile[1]),
              let s = Double(teile[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    /// Sekunden → „H:MM:SS" für `Seek` (`REL_TIME`).
    public static func schreiben(_ sekunden: TimeInterval) -> String {
        let ganz = Int(max(0, sekunden).rounded(.down))
        return String(format: "%d:%02d:%02d", ganz / 3600, (ganz / 60) % 60, ganz % 60)
    }
}
