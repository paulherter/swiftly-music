import Foundation
import JellyfinKit
@testable import MusikKit
import SubsonicKit

/// Liest eine Datei aus `Fixtures`.
func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw URLError(.fileDoesNotExist)
    }
    return try Data(contentsOf: url)
}

/// **Ein Jellyfin aus Dateien.** Jeder Pfad bekommt die Datei, die ihm
/// zugeordnet ist; ohne Zuordnung antwortet er mit 404. Die Antworten sind von
/// Hand nach Jellyfins Schnittstelle geschrieben — gegen einen echten Server
/// wird hier nicht getestet.
final class Jellyfinstelle: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var zuordnung: [String: String] = [:]
    nonisolated(unsafe) static var anfragen: [URLRequest] = []
    static let schloss = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }

    /// Der Schlüssel ist der Pfad, bei `Items` zusätzlich `Ids` oder der
    /// Wert von `IncludeItemTypes` und `ParentId` — sonst ließen sich Alben
    /// und Lieder derselben Adresse nicht unterscheiden.
    static func schluessel(_ url: URL) -> String {
        let werte = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func wert(_ name: String) -> String? { werte.first { $0.name == name }?.value }
        var s = url.path
        if wert("Ids") != nil { return s + "?Ids" }
        if let t = wert("IncludeItemTypes") { s += "?\(t)" }
        if let p = wert("ParentId") { s += "&ParentId=\(p)" }
        return s
    }

    override func startLoading() {
        Self.schloss.lock()
        Self.anfragen.append(request)
        let datei = Self.zuordnung[Self.schluessel(request.url!)]
        Self.schloss.unlock()
        let daten = datei.flatMap { try? fixture($0) }
        let antwort = HTTPURLResponse(url: request.url!, statusCode: daten == nil ? 404 : 200,
                                      httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: antwort, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: daten ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func quelle(_ zuordnung: [String: String]) async -> JellyfinQuelle {
        schloss.withLock {
            self.zuordnung = zuordnung
            anfragen = []
        }
        let k = URLSessionConfiguration.ephemeral
        k.protocolClasses = [Jellyfinstelle.self]
        let server = URL(string: "https://musik.example.de")!
        let client = JellyfinClient(baseURL: server, deviceID: "musik-geraet", deviceName: "iPhone",
                                    clientVersion: "1.0.0", programm: "Swiftly Music",
                                    urlSession: URLSession(configuration: k))
        let sitzung = Session(accessToken: "tok", userID: "u1", userName: "Anna", serverURL: server)
        await client.setSession(sitzung)
        return JellyfinQuelle(client: client, sitzung: sitzung, geraeteID: "musik-geraet")
    }

    static func werte(_ anfrage: URLRequest) -> [String: String] {
        var d: [String: String] = [:]
        for w in URLComponents(url: anfrage.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            d[w.name] = w.value ?? ""
        }
        return d
    }
}

/// **Ein Subsonic aus Dateien**, Endpunkt → Dateifolge.
final class Subsonicstelle: @unchecked Sendable {
    private let schloss = NSLock()
    private var zuordnung: [String: [String]]
    private(set) var endpunkte: [String] = []

    init(_ zuordnung: [String: [String]]) { self.zuordnung = zuordnung }

    func quelle() -> SubsonicQuelle {
        let client = SubsonicClient(
            zugang: SubsonicZugang(server: URL(string: "https://musik.example.org")!, benutzer: "demo",
                                   passwort: "demo"),
            salz: "abc") { [self] anfrage in
                let endpunkt = anfrage.url!.lastPathComponent.replacingOccurrences(of: ".view", with: "")
                let datei: String? = {
                    schloss.lock(); defer { schloss.unlock() }
                    endpunkte.append(endpunkt)
                    guard var folge = zuordnung[endpunkt], !folge.isEmpty else { return nil }
                    let erste = folge.removeFirst()
                    if !folge.isEmpty { zuordnung[endpunkt] = folge }
                    return erste
                }()
                guard let datei else { throw URLError(.fileDoesNotExist) }
                let antwort = HTTPURLResponse(url: anfrage.url!, statusCode: 200, httpVersion: nil,
                                              headerFields: nil)!
                return (try fixture(datei), antwort)
            }
        return SubsonicQuelle(client: client)
    }
}

/// Ein Zufall, der jedes Mal gleich ausgeht.
struct FesterZufall: RandomNumberGenerator {
    var zustand: UInt64
    init(_ saat: UInt64) { zustand = saat }
    mutating func next() -> UInt64 {
        zustand &+= 0x9E37_79B9_7F4A_7C15
        var z = zustand
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func lied(_ id: String, dauer: TimeInterval? = 200) -> Lied {
    Lied(id: id, titel: "Lied \(id)", dauer: dauer)
}
