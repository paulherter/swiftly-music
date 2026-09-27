import Foundation
import Testing
@testable import MusikKit

@Suite("Eine Bibliothek wählen")
struct BibliothekTests {
    @Test("Jellyfin grenzt Alben, Lieder und Künstler ein — Playlists, Kennungen und Ordner nicht")
    func eingrenzen() {
        func typ(_ t: String) -> [URLQueryItem] { [.init(name: "IncludeItemTypes", value: t)] }
        #expect(JellyfinQuelle.eingegrenzt(typ("MusicAlbum"), "m1").contains { $0.name == "ParentId" && $0.value == "m1" })
        #expect(JellyfinQuelle.eingegrenzt(typ("Audio"), "m1").contains { $0.name == "ParentId" })
        #expect(!JellyfinQuelle.eingegrenzt(typ("Playlist"), "m1").contains { $0.name == "ParentId" })
        #expect(!JellyfinQuelle.eingegrenzt(typ("AudioBook"), "m1").contains { $0.name == "ParentId" })
        #expect(JellyfinQuelle.eingegrenzt(typ("Audio") + [.init(name: "ParentId", value: "a")], "m1")
                    .filter { $0.name == "ParentId" }.map(\.value) == ["a"])
        #expect(!JellyfinQuelle.eingegrenzt(typ("MusicAlbum") + [.init(name: "Ids", value: "x")], "m1")
                    .contains { $0.name == "ParentId" })
        #expect(!JellyfinQuelle.eingegrenzt(typ("MusicAlbum"), nil).contains { $0.name == "ParentId" })
    }
}

extension JellyfinQuelleTests {
    @Test("Jellyfin: nur Bibliotheken der Art Musik, die Wahl gilt für Listen")
    func bibliotheken() async throws {
        let quelle = await Jellyfinstelle.quelle(["/UserViews": "jf_userviews", "/Items?MusicAlbum&ParentId=m2": "jf_alben_ids"])
        let liste = try await quelle.bibliotheken()
        #expect(liste.map(\.name) == ["Musik", "Klassik"])
        quelle.bibliothek = "m2"
        _ = try await quelle.zuletztHinzugefuegt(anzahl: 5)
        let anfrage = try #require(Jellyfinstelle.anfragen.last)
        #expect(Jellyfinstelle.werte(anfrage)["ParentId"] == "m2")
    }
}
