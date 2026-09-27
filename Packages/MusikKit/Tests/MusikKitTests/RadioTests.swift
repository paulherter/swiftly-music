import Foundation
import Testing
@testable import MusikKit

@Suite("Weiter mit Ähnlichem")
struct RadioTests {
    private let drei = ["a", "b", "c"].map { lied($0) }

    @Test("Nachschub erst beim vorletzten Lied, nicht bei Wiederholung, nicht ausgeschaltet")
    func wann() {
        var s = Warteschlange()
        s.setzen(drei, ab: 0, mischen: false)
        #expect(!Radioregel.brauchtNachschub(s, an: true))
        s.weiter()
        #expect(Radioregel.brauchtNachschub(s, an: true))
        #expect(!Radioregel.brauchtNachschub(s, an: false))
        s.wiederholen(.alles)
        #expect(!Radioregel.brauchtNachschub(s, an: true))
        #expect(!Radioregel.brauchtNachschub(Warteschlange(), an: true))
    }

    @Test("Hörbücher bekommen kein Radio")
    func hoerbuch() {
        var s = Warteschlange()
        var teil = lied("h")
        teil.istHoerbuch = true
        s.setzen([teil], ab: 0, mischen: false)
        #expect(!Radioregel.brauchtNachschub(s, an: true))
    }

    @Test("Angehängt wird nur, was noch nicht in der Schlange steht, jedes einmal")
    func auswahl() {
        var s = Warteschlange()
        s.setzen(drei, ab: 2, mischen: false)
        let vorschlaege = ["c", "d", "a", "e", "d", "f"].map { lied($0) }
        #expect(Radioregel.auswahl(vorschlaege, schlange: s).map(\.id) == ["d", "e", "f"])
        #expect(Radioregel.auswahl(vorschlaege, schlange: s, anzahl: 2).map(\.id) == ["d", "e"])
    }
}
