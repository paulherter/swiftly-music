import Foundation
import Testing
@testable import MusikKit

/// **Kein Flackern am Abspielknopf**: kurzes Warten bleibt unsichtbar.
@Suite("Ladeanzeige")
struct LadeanzeigeTests {

    @Test("Kurzes Warten nach Abspielen zeigt nichts")
    func kurzesWarten() {
        var l = Ladeanzeige()
        // Abspielen bei 10 s, der Player wartet 120 ms und spielt dann.
        l.melden(wartet: true, jetzt: 10)
        for t in stride(from: 10.0, through: 10.12, by: 1.0 / 120) {
            #expect(!l.sichtbar(jetzt: t))
        }
        l.melden(wartet: false, jetzt: 10.12)
        #expect(!l.sichtbar(jetzt: 10.5))
        #expect(l.faellig == nil)
    }

    @Test("Langes Puffern zeigt die Anzeige erst nach der Schwelle")
    func langesWarten() {
        var l = Ladeanzeige()
        l.melden(wartet: true, jetzt: 5)
        #expect(l.faellig == 5 + Ladeanzeige.schwelle)
        #expect(!l.sichtbar(jetzt: 5.39))
        #expect(l.sichtbar(jetzt: 5.4))
        #expect(l.sichtbar(jetzt: 7))
        l.melden(wartet: false, jetzt: 7.2)
        #expect(!l.sichtbar(jetzt: 7.2))
    }

    @Test("Wiederholte Wartemeldungen verschieben den Beginn nicht")
    func wiederholteMeldungen() {
        var l = Ladeanzeige()
        l.melden(wartet: true, jetzt: 1)
        l.melden(wartet: true, jetzt: 1.3)
        l.melden(wartet: true, jetzt: 1.35)
        #expect(l.wartetSeit == 1)
        #expect(l.sichtbar(jetzt: 1.41))
    }

    @Test("Pause oder Spielen dazwischen beginnt neu")
    func neuerAnlauf() {
        var l = Ladeanzeige()
        l.melden(wartet: true, jetzt: 0)
        l.melden(wartet: false, jetzt: 0.3)
        l.melden(wartet: true, jetzt: 0.35)
        #expect(!l.sichtbar(jetzt: 0.5))
        #expect(l.sichtbar(jetzt: 0.75))
    }
}
