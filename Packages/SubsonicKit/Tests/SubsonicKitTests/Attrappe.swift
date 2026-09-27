import Foundation
@testable import SubsonicKit

/// **Ein Server aus Dateien.** Jede Anfrage bekommt die Datei, die zum
/// Endpunkt gehört — kein Netz in den Tests. Die Antworten stammen, wo nicht
/// anders vermerkt, vom öffentlichen Navidrome-Demo (demo.navidrome.org,
/// 23.09.2026, gekürzt).
final class Attrappe: @unchecked Sendable {
    private let schloss = NSLock()
    private var _anfragen: [URLRequest] = []
    /// Endpunkt → Dateiname ohne Endung; fehlt einer, gilt der Endpunkt selbst.
    private var zuordnung: [String: [String]] = [:]

    init(_ zuordnung: [String: [String]] = [:]) {
        self.zuordnung = zuordnung
    }

    var anfragen: [URLRequest] {
        schloss.lock(); defer { schloss.unlock() }
        return _anfragen
    }

    /// Die Abfragewerte der n-ten Anfrage als Wörterbuch.
    func werte(_ n: Int) -> [String: String] {
        guard n < anfragen.count, let url = anfragen[n].url,
              let teile = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return [:] }
        var ergebnis: [String: String] = [:]
        for w in teile.queryItems ?? [] { ergebnis[w.name] = w.value ?? "" }
        return ergebnis
    }

    var abruf: SubsonicClient.Abruf {
        { [self] anfrage in
            let endpunkt = anfrage.url?.lastPathComponent
                .replacingOccurrences(of: ".view", with: "") ?? ""
            let datei: String = {
                schloss.lock(); defer { schloss.unlock() }
                _anfragen.append(anfrage)
                // Mehrere Dateien je Endpunkt: der Reihe nach, die letzte bleibt.
                if var folge = zuordnung[endpunkt], !folge.isEmpty {
                    let naechste = folge.removeFirst()
                    if !folge.isEmpty { zuordnung[endpunkt] = folge }
                    return naechste
                }
                return endpunkt
            }()
            let daten = try Self.datei(datei)
            let antwort = HTTPURLResponse(url: anfrage.url!, statusCode: 200,
                                          httpVersion: "HTTP/1.1", headerFields: nil)!
            return (daten, antwort)
        }
    }

    static func datei(_ name: String) throws -> Data {
        let teile = name.split(separator: ".")
        let (stamm, endung) = teile.count > 1
            ? (String(teile[0]), String(teile[1])) : (name, "json")
        guard let url = Bundle.module.url(forResource: stamm, withExtension: endung,
                                          subdirectory: "Fixtures") else {
            throw URLError(.fileDoesNotExist)
        }
        return try Data(contentsOf: url)
    }

    static let server = URL(string: "https://musik.example.org")!

    func client(weise: SubsonicZugang.Weise = .token) -> SubsonicClient {
        SubsonicClient(zugang: SubsonicZugang(server: Self.server, benutzer: "demo",
                                              passwort: "demo", weise: weise),
                       salz: "abcdef123", abruf: abruf)
    }
}
