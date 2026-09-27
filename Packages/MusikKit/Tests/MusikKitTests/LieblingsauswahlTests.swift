import Foundation
import Testing
@testable import MusikKit

/// **„Zu Playlist hinzufügen" → Lieblingssongs** — was die Zeile anbietet,
/// und wie viele Lieder auf einmal zum Server gehen.
@Suite("Lieblingsauswahl")
struct LieblingsauswahlTests {

    @Test("Ein einzelnes Lied: keine Zeile, auch nicht doppelt in der Playlist")
    func einzeln() {
        #expect(Lieblingsauswahl.angebot(["l1"]) { _ in false } == nil)
        #expect(Lieblingsauswahl.angebot(["l1", "l1"]) { _ in true } == nil)
        #expect(Lieblingsauswahl.angebot([]) { _ in false } == nil)
    }

    @Test("Hinzufügen schickt nur die ohne Herz, in ihrer Reihenfolge")
    func hinzufuegen() {
        let herz: Set = ["l2"]
        let a = Lieblingsauswahl.angebot(["l1", "l2", "l3", "l1"]) { herz.contains($0) }
        #expect(a == .hinzufuegen(["l1", "l3"]))
        #expect(a?.an == true)
        #expect(a?.rueckfrage == false)
    }

    @Test("Haben alle ein Herz: Entfernen für alle, ab zwei mit Rückfrage")
    func entfernen() {
        let a = Lieblingsauswahl.angebot(["l1", "l2", "l2"]) { _ in true }
        #expect(a == .entfernen(["l1", "l2"]))
        #expect(a?.an == false)
        #expect(a?.rueckfrage == true)
    }

    @Test("Bündel: Reihenfolge bleibt, das letzte ist kürzer")
    func buendel() {
        let b = Lieblingsauswahl.buendel(Array(1 ... 20), je: 8)
        #expect(b.map(\.count) == [8, 8, 4])
        #expect(b.flatMap { $0 } == Array(1 ... 20))
        #expect(Lieblingsauswahl.buendel([Int](), je: 8).isEmpty)
    }
}

/// Jellyfin: je Lied über den Herz-Weg, jedes im ``Favoritenstand`` gemerkt.
/// In der Reihe der Favoriten, weil ``Favoritstelle`` einen Stand für alle hat.
extension JellyfinFavoritTests {

    @Test("Zwölf Lieder: zwölf POST, alle gemerkt gegen das Zurücksetzen")
    func viele() async throws {
        let ids = (1 ... 12).map { "l\($0)" }
        var zuordnung: [String: String] = [:]
        for id in ids { zuordnung["/UserFavoriteItems/\(id)"] = "jf_favorit" }
        let quelle = await Favoritstelle.quelle(zuordnung)
        try await quelle.lieblingeSetzen(ids, an: true)
        let pfade = Set(Favoritstelle.anfragen.map { "\($0.httpMethod ?? "") \($0.url!.path)" })
        #expect(pfade == Set(ids.map { "POST /UserFavoriteItems/\($0)" }))
        #expect(ids.allSatisfy { quelle.favoritenstand.stand($0) == true })
    }

    @Test("Ein Lied ohne Weg: der Fehler kommt an, damit alles zurückspringt")
    func fehler() async {
        let quelle = await Favoritstelle.quelle(["/UserFavoriteItems/l1": "jf_favorit"])
        await #expect(throws: (any Error).self) { try await quelle.lieblingeSetzen(["l1", "l2"], an: false) }
    }
}

/// Subsonic: viele `id` in einem `star`, zu höchstens 50.
@Suite("Subsonic: viele Lieblingssongs")
struct SubsonicLieblingeTests {

    @Test("120 Lieder: drei Aufrufe von star, ohne Aufruf nichts")
    func sterne() async throws {
        let stelle = Subsonicstelle(["star": ["ss_getOpenSubsonicExtensions"], "unstar": ["ss_getOpenSubsonicExtensions"]])
        let quelle = stelle.quelle()
        try await quelle.lieblingeSetzen((1 ... 120).map { "l\($0)" }, an: true)
        try await quelle.lieblingeSetzen([], an: false)
        try await quelle.lieblingeSetzen(["l1", "l2"], an: false)
        #expect(stelle.endpunkte == ["star", "star", "star", "unstar"])
    }
}
