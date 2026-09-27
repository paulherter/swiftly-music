import Foundation
import Testing
@testable import MusikKit

@Suite("Nachtragen ohne Netz")
struct NachtragTests {

    @Test("Gemerkt wird jeder Lauf einmal, der Reihe nach")
    func merken() {
        var liste = Nachtragsliste()
        let spaet = Nachtrag(liedID: "b", titel: "B", zeit: Date(timeIntervalSince1970: 200))
        let frueh = Nachtrag(liedID: "a", titel: "A", zeit: Date(timeIntervalSince1970: 100))
        liste.merken(spaet)
        liste.merken(frueh)
        liste.merken(spaet)
        #expect(liste.eintraege == [frueh, spaet])
        liste.erledigt(frueh)
        #expect(liste.eintraege == [spaet])
    }

    @Test("Mehr als die Grenze: die ältesten fallen")
    func grenze() {
        var liste = Nachtragsliste()
        for i in 0 ..< Nachtragsliste.hoechstens + 3 {
            liste.merken(Nachtrag(liedID: "\(i)", titel: "", zeit: Date(timeIntervalSince1970: Double(i))))
        }
        #expect(liste.eintraege.count == Nachtragsliste.hoechstens)
        #expect(liste.eintraege.first?.liedID == "3")
    }

    @Test("Subsonic: der Nachtrag scrobbelt mit Zeitpunkt, ein Fehler kommt an")
    func subsonic() async throws {
        let stelle = Subsonicstelle(["scrobble": ["ss_ping"]])
        try await stelle.quelle().scrobbeln(lied("x"), beginn: Date(timeIntervalSince1970: 1000),
                                            nachtraeglich: true)
        #expect(stelle.endpunkte == ["scrobble"])
        await #expect(throws: (any Error).self) {
            try await Subsonicstelle([:]).quelle().scrobbeln(lied("y"), beginn: Date(), nachtraeglich: true)
        }
    }
}

// Jellyfin teilt die Attrappe mit den anderen Jellyfin-Tests — also in
// deren Reihe, nicht nebenher.
extension JellyfinQuelleTests {

    @Test("Jellyfin: Nachtrag — live nichts, nachträglich als gespielt markieren")
    func jellyfin() async throws {
        let quelle = await Jellyfinstelle.quelle(["/UserPlayedItems/l1": "ss_ping"])
        try await quelle.scrobbeln(lied("l1"), beginn: Date(), nachtraeglich: false)
        #expect(Jellyfinstelle.anfragen.isEmpty)
        try await quelle.scrobbeln(lied("l1"), beginn: Date(timeIntervalSince1970: 0), nachtraeglich: true)
        let anfrage = try #require(Jellyfinstelle.anfragen.first)
        #expect(anfrage.httpMethod == "POST")
        #expect(Jellyfinstelle.werte(anfrage)["datePlayed"] == "1970-01-01T00:00:00Z")
    }
}
