import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JellyfinKit

/// `rohdaten` ist der Weg, über den Swiftly Music eigene Endpunkte fragt.
/// Er muss denselben Ausweis tragen wie jeder andere Aufruf — sonst führt der
/// Server die Anfrage unter einer zweiten Sitzung.
@Suite("Rohe Anfrage", .serialized)
struct RohabfrageTests {

    final class Mitschnitt: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var anfrage: URLRequest?
        nonisolated(unsafe) static var status = 200

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }

        override func startLoading() {
            var req = request
            if req.httpBody == nil, let strom = req.httpBodyStream {
                strom.open()
                var daten = Data()
                let puffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                while strom.hasBytesAvailable {
                    let gelesen = strom.read(puffer, maxLength: 4096)
                    if gelesen <= 0 { break }
                    daten.append(puffer, count: gelesen)
                }
                puffer.deallocate()
                strom.close()
                req.httpBody = daten
            }
            Self.anfrage = req
            let antwort = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                          httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: antwort, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"Items":[]}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func client() async -> JellyfinClient {
        let k = URLSessionConfiguration.ephemeral
        k.protocolClasses = [Mitschnitt.self]
        let c = JellyfinClient(baseURL: URL(string: "https://musik.example.de")!,
                               deviceID: "musik-1", deviceName: "iPhone",
                               clientVersion: "1.0.0", programm: "Swiftly Music",
                               urlSession: URLSession(configuration: k))
        await c.setSession(Session(accessToken: "tok", userID: "u1", userName: "n",
                                   serverURL: URL(string: "https://musik.example.de")!))
        return c
    }

    @Test("Trägt Pfad, Abfrage und denselben Ausweis wie jeder Aufruf")
    func ausweis() async throws {
        Mitschnitt.status = 200
        let daten = try await client().rohdaten("Items/a1/InstantMix",
                                                abfrage: [.init(name: "Limit", value: "50")])
        #expect(String(data: daten, encoding: .utf8) == #"{"Items":[]}"#)
        let req = try #require(Mitschnitt.anfrage)
        #expect(req.url?.path == "/Items/a1/InstantMix")
        #expect(req.url?.query == "Limit=50")
        #expect(req.httpMethod == "GET")
        let kopf = try #require(req.value(forHTTPHeaderField: "Authorization"))
        #expect(kopf.contains(#"Client="Swiftly Music""#))
        #expect(kopf.contains(#"DeviceId="musik-1""#))
        #expect(kopf.contains(#"Token="tok""#))
    }

    @Test("Ein Rumpf geht als JSON hinaus")
    func rumpf() async throws {
        Mitschnitt.status = 204
        _ = try await client().rohdaten("Sessions/Playing", methode: "POST",
                                        rumpf: Data(#"{"ItemId":"x"}"#.utf8))
        let req = try #require(Mitschnitt.anfrage)
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(req.httpBody == Data(#"{"ItemId":"x"}"#.utf8))
    }

    @Test("Ein Status außerhalb von 2xx wirft mit Status")
    func fehlerstatus() async throws {
        Mitschnitt.status = 404
        do {
            _ = try await client().rohdaten("Audio/x/Lyrics")
            Issue.record("hätte werfen müssen")
        } catch let JellyfinError.http(status, _) {
            #expect(status == 404)
        }
    }
}
