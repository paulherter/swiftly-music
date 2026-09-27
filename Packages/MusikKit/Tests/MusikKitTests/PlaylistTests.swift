import Foundation
import Testing
@testable import MusikKit

@Suite("Playlists bearbeiten")
struct PlaylistfolgeTests {
    @Test("Verschieben und Entfernen ändern die Folge wie erwartet")
    func folge() {
        let l = ["a", "b", "c", "d"]
        #expect(Playlistfolge.verschoben(l, von: 0, nach: 2) == ["b", "c", "a", "d"])
        #expect(Playlistfolge.verschoben(l, von: 3, nach: 0) == ["d", "a", "b", "c"])
        #expect(Playlistfolge.verschoben(l, von: 9, nach: 0) == l)
        #expect(Playlistfolge.ohne(l, stellen: [1, 3]) == ["a", "c"])
    }

    @Test("SwiftUI zählt das Ziel vor dem Herausnehmen")
    func zielstelle() {
        #expect(Playlistfolge.zielstelle(von: 0, vorStelle: 3) == 2)
        #expect(Playlistfolge.zielstelle(von: 3, vorStelle: 0) == 0)
    }

    @Test("Bündel zu höchstens 50")
    func buendel() {
        let teile = Playlistfolge.buendel(Array(0 ..< 120))
        #expect(teile.map(\.count) == [50, 50, 20])
        #expect(Playlistfolge.buendel([Int]()).isEmpty)
    }

    @Test("Schon darin: nur die, die es gibt")
    func doppelt() {
        let da = [lied("a"), lied("b")]
        #expect(Playlistfolge.schonDarin([lied("b"), lied("c")], in: da).map(\.id) == ["b"])
    }

    @Test("Subsonic: Verschieben schreibt die ganze Folge neu, Entfernen nach Stelle")
    func subsonic() async throws {
        let stelle = Subsonicstelle(["createPlaylist": ["ss_ping"], "updatePlaylist": ["ss_ping"]])
        let quelle = stelle.quelle()
        let vorher = Playlistdetail(playlist: Playlist(id: "p", name: "P"), lieder: [lied("a"), lied("b"), lied("c")])
        try await quelle.playlistVerschieben("p", von: 2, nach: 0, vorher: vorher)
        try await quelle.playlistEntfernen("p", stellen: [1], vorher: vorher)
        #expect(stelle.endpunkte.prefix(2) == ["createPlaylist", "updatePlaylist"])
    }
}

extension JellyfinQuelleTests {
    @Test("Jellyfin: Einträge tragen ihre PlaylistItemId; entfernt und verschoben wird darüber")
    func playlistEintraege() async throws {
        let quelle = await Jellyfinstelle.quelle([
            "/Items/p1": "jf_playlist_kopf", "/Playlists/p1/Items": "jf_playlist_items",
            "/Playlists/p1/Items/e3/Move/0": "jf_playlist_neu", "/Playlists": "jf_playlist_neu",
        ])
        let detail = try await quelle.playlist("p1")
        #expect(detail.lieder.map(\.id) == ["a", "b", "a"])
        #expect(detail.eintraege == ["e1", "e2", "e3"])

        try await quelle.playlistEntfernen("p1", stellen: [2], vorher: detail)
        let loeschen = try #require(Jellyfinstelle.anfragen.last)
        #expect(loeschen.httpMethod == "DELETE")
        #expect(Jellyfinstelle.werte(loeschen)["entryIds"] == "e3")

        try await quelle.playlistVerschieben("p1", von: 2, nach: 0, vorher: detail)
        #expect(Jellyfinstelle.anfragen.last?.url?.path == "/Playlists/p1/Items/e3/Move/0")

        let neu = try await quelle.playlistAnlegen(name: "Sommer", lieder: [lied("a")])
        #expect(neu.id == "p9")
        let anlegen = try #require(Jellyfinstelle.anfragen.last)
        #expect(anlegen.httpMethod == "POST")
    }
}
