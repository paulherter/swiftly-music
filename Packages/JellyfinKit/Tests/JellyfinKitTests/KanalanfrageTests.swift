import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JellyfinKit

/// Der Steuerkanal von Swiftly Music muss sich ausweisen wie jeder andere
/// Aufruf — sonst führt Jellyfin ihn unter einer zweiten Sitzung.
@Suite("Anfrage für den Steuerkanal")
struct KanalanfrageTests {

    private func client(_ adresse: String) async -> JellyfinClient {
        let c = JellyfinClient(baseURL: URL(string: adresse)!,
                               deviceID: "musik-1", deviceName: "iPhone",
                               clientVersion: "1.0.0", programm: "Swiftly Music")
        await c.setSession(Session(accessToken: "tok", userID: "u1", userName: "n",
                                   serverURL: URL(string: adresse)!))
        return c
    }

    @Test("wss, ApiKey und Gerätekennung, derselbe Ausweis")
    func sicher() async throws {
        let req = try await client("https://musik.example.de/jf").steuerkanalAnfrage()
        let url = try #require(req.url)
        #expect(url.scheme == "wss")
        #expect(url.path == "/jf/socket")
        let werte = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(werte.contains(URLQueryItem(name: "ApiKey", value: "tok")))
        #expect(werte.contains(URLQueryItem(name: "deviceId", value: "musik-1")))
        let kopf = try #require(req.value(forHTTPHeaderField: "Authorization"))
        #expect(kopf.contains(#"Client="Swiftly Music""#))
        #expect(kopf.contains(#"DeviceId="musik-1""#))
        #expect(kopf.contains(#"Token="tok""#))
    }

    @Test("http wird ws")
    func unverschluesselt() async throws {
        let req = try await client("http://192.168.1.5:8096").steuerkanalAnfrage()
        #expect(req.url?.scheme == "ws")
    }

    @Test("Ohne Anmeldung wirft es")
    func ohneSitzung() async {
        let c = JellyfinClient(baseURL: URL(string: "https://x.de")!, deviceID: "d",
                               deviceName: "iPhone", clientVersion: "1", programm: "Swiftly Music")
        await #expect(throws: (any Error).self) { try await c.steuerkanalAnfrage() }
    }
}
