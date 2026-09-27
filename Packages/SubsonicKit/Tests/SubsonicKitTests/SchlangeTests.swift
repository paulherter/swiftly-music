import Foundation
import Testing
@testable import SubsonicKit

/// `getPlayQueue`/`savePlayQueue` — die einzige Brücke zwischen zwei Geräten,
/// die Subsonic kennt. Die Antwort ist von Hand nach Navidromes Form
/// geschrieben.
@Suite("Schlange auf dem Server")
struct SchlangeTests {

    @Test("getPlayQueue: Lieder, laufendes, Stelle, wer und wann")
    func lesen() async throws {
        let s = try #require(try await Attrappe().client().schlange())
        #expect(s.lieder.map(\.id) == ["0eAAnXekI5EhEZaTc7fEwe", "3fBzYpG1Mx8Tn2AqWcLd0e"])
        #expect(s.aktuell == "3fBzYpG1Mx8Tn2AqWcLd0e")
        #expect(s.stelle == 73_500)
        #expect(s.geaendertVon == "Feishin")
        #expect(s.geaendert == Zeitangabe.lesen("2026-09-24T09:12:03.52Z"))
    }

    @Test("Keine abgelegte Schlange ist nil, kein Fehler")
    func leer() async throws {
        let attrappe = Attrappe(["getPlayQueue": ["getPlayQueue_leer"]])
        #expect(try await attrappe.client().schlange() == nil)
    }

    @Test("savePlayQueue: jede Kennung einzeln, dazu current und position")
    func speichern() async throws {
        let attrappe = Attrappe()
        try await attrappe.client().schlangeSpeichern(liedIDs: ["a", "b", "c"], aktuell: "b", stelleMs: 12_345)
        let url = try #require(attrappe.anfragen.first?.url)
        #expect(url.lastPathComponent == "savePlayQueue.view")
        let werte = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(werte.filter { $0.name == "id" }.map(\.value) == ["a", "b", "c"])
        #expect(attrappe.werte(0)["current"] == "b")
        #expect(attrappe.werte(0)["position"] == "12345")
        #expect(attrappe.werte(0)["c"] == "Swiftly Music")
    }
}
