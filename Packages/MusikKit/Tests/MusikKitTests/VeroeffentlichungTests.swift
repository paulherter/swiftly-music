import Foundation
import Testing
@testable import MusikKit

@Suite("Singles statt Mini-Alben")
struct VeroeffentlichungTests {

    private func album(_ titel: String, lieder: Int?, minuten: Double? = nil, art: Albumart? = nil) -> Album {
        Album(id: titel, titel: titel, liedzahl: lieder, dauer: minuten.map { $0 * 60 }, art: art)
    }

    @Test("Ein Lied, oder der Titel sagt es: Single")
    func single() {
        #expect(Veroeffentlichung.art(album("A", lieder: 1)) == .single)
        #expect(Veroeffentlichung.art(album("A - Single", lieder: 3, minuten: 9)) == .single)
        #expect(Veroeffentlichung.art(album("A (Single)", lieder: 2)) == .single)
        #expect(Veroeffentlichung.art(album("Heimweh", lieder: 2), liedtitel: ["Heimweh", "Heimweh (Remix)"]) == .single)
    }

    @Test("Zwei bis sechs Lieder unter 30 Minuten: EP; sonst Album")
    func epUndAlbum() {
        #expect(Veroeffentlichung.art(album("B", lieder: 4, minuten: 15)) == .ep)
        #expect(Veroeffentlichung.art(album("B", lieder: 6, minuten: 31)) == .album)
        #expect(Veroeffentlichung.art(album("B", lieder: 12, minuten: 45)) == .album)
        #expect(Veroeffentlichung.art(album("B [EP]", lieder: 8, minuten: 40)) == .ep)
        #expect(Veroeffentlichung.art(album("B", lieder: nil)) == .album)
    }

    @Test("Sagt der Server die Art, gilt sie — ein sauber getaggtes Album bleibt eins")
    func server() {
        #expect(Veroeffentlichung.art(album("C", lieder: 1, art: .album)) == .album)
        #expect(Veroeffentlichung.art(album("C", lieder: 12, art: .single)) == .single)
    }

    @Test("Subsonic: releaseTypes vor der Regel, ohne Angabe die Regel")
    func subsonic() {
        #expect(SubsonicQuelle.albumart(["album"], zusammenstellung: nil) == .album)
        #expect(SubsonicQuelle.albumart([], zusammenstellung: nil) == nil)
    }

    @Test("Singles desselben Künstlers vom selben Tag werden eine Kachel")
    func buendeln() {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = TimeZone(identifier: "UTC")!
        let tag = Date(timeIntervalSince1970: 1_758_000_000)
        let posten: [(id: String, single: Bool, k: String, t: Date)] = [
            ("a", true, "Ikkimel", tag),
            ("b", false, "Ikkimel", tag),
            ("c", true, "ikkimel", tag.addingTimeInterval(3600)),
            ("d", true, "Ikkimel", tag.addingTimeInterval(86_400 * 2)),
            ("e", true, "Andere", tag),
        ]
        let b = Singlebuendel.buendeln(posten, single: { $0.single }, kuenstler: { ($0.k, nil) },
                                       tag: { $0.t }, kalender: k)
        #expect(b.count == 4)
        guard case let .singles(name, _, liste) = b[0] else { Issue.record("keine Gruppe"); return }
        #expect(name == "Ikkimel")
        #expect(liste.map(\.id) == ["a", "c"])
        guard case let .einzeln(zweites) = b[1] else { Issue.record(); return }
        #expect(zweites.id == "b")
    }
}

extension JellyfinQuelleTests {
    @Test("Jellyfin: Ein-Lied-Alben werden Singles, ohne Albumkünstler gilt der Liedkünstler")
    func singles() async throws {
        let quelle = await Jellyfinstelle.quelle(["/Items?MusicAlbum": "jf_singles"])
        let alben = try await quelle.zuletztHinzugefuegt(anzahl: 10)
        #expect(alben.map(\.art) == [.single, .single, .ep, .album, .single])
        #expect(alben[4].kuenstlernamen == ["nocashfromparents"])
        #expect(alben[4].kuenstlerID == "k3")
    }
}
