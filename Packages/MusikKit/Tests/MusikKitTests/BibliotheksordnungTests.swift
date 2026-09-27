import Foundation
import Testing
@testable import MusikKit

@Suite("Reihenfolge der Bibliothek")
struct BibliotheksordnungTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private var eintraege: [Bibliothekseintrag] {
        [
            .album(Album(id: "a", titel: "Zebra", zuletztGespielt: t0)),
            .album(Album(id: "b", titel: "Album 10", hinzugefuegt: t0.addingTimeInterval(50))),
            .album(Album(id: "c", titel: "Album 9", hinzugefuegt: t0.addingTimeInterval(10))),
            .playlist(Playlist(id: "p", name: "Mittag", geaendert: t0.addingTimeInterval(30))),
            .kuenstler(Kuenstler(id: "k", name: "Beta")),
        ]
    }

    @Test("A–Z sortiert wie Menschen")
    func name() {
        #expect(Bibliotheksordnung.ordnen(eintraege, nach: .name).map(\.name)
                == ["Album 9", "Album 10", "Beta", "Mittag", "Zebra"])
    }

    @Test("Zuletzt hinzugefügt: neueste zuerst, ohne Datum nach Namen")
    func hinzugefuegt() {
        #expect(Bibliotheksordnung.ordnen(eintraege, nach: .zuletztHinzugefuegt).map(\.name)
                == ["Album 10", "Mittag", "Album 9", "Beta", "Zebra"])
    }

    @Test("Zuletzt gespielt: Gespieltes zuerst, Server- oder Gerätezeit, dann nach Namen")
    func gespielt() {
        let geraet = ["kuenstler:k": t0.addingTimeInterval(500), "playlist:p": t0.addingTimeInterval(-5)]
        #expect(Bibliotheksordnung.ordnen(eintraege, nach: .zuletztGespielt, gespielt: geraet).map(\.name)
                == ["Beta", "Zebra", "Mittag", "Album 9", "Album 10"])
    }

    @Test("Die Fächer behalten die Reihenfolge der ganzen Liste")
    func faecher() {
        let geordnet = Bibliotheksordnung.ordnen(eintraege, nach: .zuletztHinzugefuegt)
        let f = Bibliotheksfaecher(geordnet)
        #expect(f.alben.map(\.name) == ["Album 10", "Album 9", "Zebra"])
        #expect(f.playlists.map(\.name) == ["Mittag"])
        #expect(f.kuenstler.map(\.name) == ["Beta"])
        #expect(f.lieder.isEmpty)
        #expect(f.alben.map(\.id) == Bibliotheksordnung.ordnen(eintraege.filter {
            if case .album = $0 { true } else { false }
        }, nach: .zuletztHinzugefuegt).map(\.id))
    }
}
