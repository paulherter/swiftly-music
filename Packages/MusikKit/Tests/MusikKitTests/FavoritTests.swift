import Foundation
import JellyfinKit
import Testing
@testable import MusikKit

/// **Ein eigenes Jellyfin aus Dateien für diese Reihe** — wie
/// ``Jellyfinstelle``, aber mit eigenem Stand: die Reihen laufen
/// nebeneinander, und eine geteilte Zuordnung würde die andere Reihe mitten
/// im Test umstellen.
final class Favoritstelle: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var zuordnung: [String: String] = [:]
    nonisolated(unsafe) static var anfragen: [URLRequest] = []
    static let schloss = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }

    override func startLoading() {
        let datei = Self.schloss.withLock {
            Self.anfragen.append(request)
            return Self.zuordnung[Jellyfinstelle.schluessel(request.url!)]
        }
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
        k.protocolClasses = [Favoritstelle.self]
        let server = URL(string: "https://musik.example.de")!
        let client = JellyfinClient(baseURL: server, deviceID: "musik-geraet", deviceName: "iPhone",
                                    clientVersion: "1.0.0", programm: "Swiftly Music",
                                    urlSession: URLSession(configuration: k))
        let sitzung = Session(accessToken: "tok", userID: "u1", userName: "Anna", serverURL: server)
        await client.setSession(sitzung)
        return JellyfinQuelle(client: client, sitzung: sitzung, geraeteID: "musik-geraet")
    }
}

/// **Favoriten auf Jellyfin** — beide Wege zum Setzen, das Nachsetzen nach
/// einer Meldung und die Lieblingssongs ohne Bibliotheksgrenze
/// (``Favoritenstand``).
@Suite("Jellyfin: Favoriten", .serialized)
struct JellyfinFavoritTests {

    private func pfade() -> [String] {
        Favoritstelle.anfragen.map { "\($0.httpMethod ?? "GET") \($0.url!.path)" }
    }

    private func stand(_ id: String) -> Wiedergabestand {
        Wiedergabestand(lied: Lied(id: id, titel: "", quellID: id), position: 42, pausiert: false,
                        art: .direkt, sitzung: "s1", gemischt: false)
    }

    @Test("10.9 und neuer: UserFavoriteItems mit userId, aus mit DELETE")
    func neuerWeg() async throws {
        let quelle = await Favoritstelle.quelle(["/UserFavoriteItems/l1": "jf_favorit"])
        try await quelle.favorit(.lied("l1"), an: true)
        try await quelle.favorit(.lied("l1"), an: false)
        #expect(pfade() == ["POST /UserFavoriteItems/l1", "DELETE /UserFavoriteItems/l1"])
        #expect(Favoritstelle.anfragen.allSatisfy { Jellyfinstelle.werte($0)["userId"] == "u1" })
        #expect(!quelle.favoritenstand.alterWeg)
    }

    @Test("10.8: nach dem 404 der alte Weg, und danach gleich dieser")
    func alterWeg() async throws {
        let quelle = await Favoritstelle.quelle(["/Users/u1/FavoriteItems/l1": "jf_favorit",
                                                  "/Users/u1/FavoriteItems/al1": "jf_favorit"])
        try await quelle.favorit(.lied("l1"), an: true)
        try await quelle.favorit(.album("al1"), an: false)
        #expect(pfade() == ["POST /UserFavoriteItems/l1", "POST /Users/u1/FavoriteItems/l1",
                            "DELETE /Users/u1/FavoriteItems/al1"])
        #expect(quelle.favoritenstand.alterWeg)
    }

    @Test("Ein Lied ohne Weg: der Fehler kommt an, damit das Herz zurückspringt")
    func keinWeg() async {
        let quelle = await Favoritstelle.quelle([:])
        await #expect(throws: (any Error).self) { try await quelle.favorit(.lied("l1"), an: true) }
    }

    /// Jellyfin 12.1 schreibt mit jeder Meldung den Stand vom Start zurück —
    /// das Herz muss danach noch einmal gesetzt werden, bis `Stopped`.
    @Test("Nach Progress und Stopped wird das Herz nachgesetzt, danach nicht mehr")
    func nachsetzen() async throws {
        let quelle = await Favoritstelle.quelle(["/UserFavoriteItems/l1": "jf_favorit"])
        try await quelle.favorit(.lied("l1"), an: true)
        await quelle.melde(.fortschritt(stand("l1")))
        await quelle.melde(.fortschritt(stand("l2")))
        await quelle.melde(.ende(stand("l1")))
        await quelle.melde(.beginn(stand("l1")))
        #expect(pfade() == [
            "POST /UserFavoriteItems/l1",
            "POST /Sessions/Playing/Progress", "POST /UserFavoriteItems/l1",
            "POST /Sessions/Playing/Progress",
            "POST /Sessions/Playing/Stopped", "POST /UserFavoriteItems/l1",
            "POST /Sessions/Playing",
        ])
    }

    @Test("Herz aus wird ebenso nachgesetzt — mit DELETE")
    func nachsetzenAus() async throws {
        let quelle = await Favoritstelle.quelle(["/UserFavoriteItems/l1": "jf_favorit"])
        try await quelle.favorit(.lied("l1"), an: false)
        await quelle.melde(.ende(stand("l1")))
        #expect(pfade() == ["DELETE /UserFavoriteItems/l1", "POST /Sessions/Playing/Stopped",
                            "DELETE /UserFavoriteItems/l1"])
    }

    @Test("Ein Album mit Herz wird nicht nachgesetzt — nur Lieder laufen")
    func albumNicht() async throws {
        let quelle = await Favoritstelle.quelle(["/UserFavoriteItems/l1": "jf_favorit"])
        try await quelle.favorit(.album("l1"), an: true)
        await quelle.melde(.fortschritt(stand("l1")))
        #expect(pfade() == ["POST /UserFavoriteItems/l1", "POST /Sessions/Playing/Progress"])
    }

    @Test("Lieblingssongs: alle Lieder mit Herz, auch mit gewählter Bibliothek ohne ParentId")
    func lieblingssongs() async throws {
        let quelle = await Favoritstelle.quelle(["/Items?Audio": "jf_lieblinge"])
        quelle.bibliothek = "musik1"
        let lieder = try await quelle.lieblingssongs()
        #expect(lieder.map(\.id) == ["l1", "l9"])
        #expect(lieder.allSatisfy { $0.favorit })
        let werte = Jellyfinstelle.werte(try #require(Favoritstelle.anfragen.first))
        #expect(werte["ParentId"] == nil)
        #expect(werte["Filters"] == "IsFavorite")
        #expect(werte["Recursive"] == "true")
        #expect(werte["EnableUserData"] == "true")
        #expect(werte["userId"] == "u1")
    }
}
