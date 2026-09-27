import Foundation
import Testing
@testable import MusikKit

/// **Die Anzeige läuft je Bild weich**, die Meldungen korrigieren nur.
@Suite("Stellenuhr")
struct StellenuhrTests {

    /// 120 Bilder je Sekunde.
    private static let bild = 1.0 / 120

    @Test("Zwischen zwei Meldungen rechnet sie hoch, Bild für Bild")
    func hochrechnen() {
        var uhr = Stellenuhr()
        uhr.setzen(10, rate: 1, jetzt: 100)
        #expect(abs(uhr.stelle(jetzt: 100.25) - 10.25) < 1e-9)
        #expect(abs(uhr.stelle(jetzt: 100.5) - 10.5) < 1e-9)
        // Doppelte Rate, doppelt so weit.
        uhr.setzen(10, rate: 2, jetzt: 100)
        #expect(abs(uhr.stelle(jetzt: 100.5) - 11) < 1e-9)
    }

    @Test("Meldungen im Halbsekundentakt: kein Sprung, nie rückwärts")
    func weichUndVorwaerts() {
        var uhr = Stellenuhr()
        uhr.setzen(0, rate: 1, jetzt: 0)
        // Der Player meldet alle 0,5 s, mal 60 ms hinterher, mal 40 ms voraus.
        let fehler = [0.06, -0.04, 0.05, -0.02, 0.0, 0.08, -0.06]
        var zuletzt = 0.0
        var groessterSchritt = 0.0
        var t = 0.0
        for runde in 0 ..< 28 {
            let meldezeit = Double(runde + 1) * 0.5
            while t + Self.bild <= meldezeit {
                t += Self.bild
                let s = uhr.stelle(jetzt: t)
                #expect(s >= zuletzt - 1e-9, "rückwärts bei \(t): \(s) < \(zuletzt)")
                groessterSchritt = max(groessterSchritt, s - zuletzt)
                zuletzt = s
            }
            let vorher = uhr.stelle(jetzt: meldezeit)
            uhr.melden(meldezeit - fehler[runde % fehler.count], rate: 1, jetzt: meldezeit)
            // Die Meldung selbst verschiebt die Anzeige nicht.
            #expect(abs(uhr.stelle(jetzt: meldezeit) - vorher) < 1e-9)
        }
        // Je Bild höchstens das Anderthalbfache des gewöhnlichen Schritts.
        #expect(groessterSchritt <= Self.bild * 1.5 + 1e-9, "Schritt \(groessterSchritt)")
    }

    @Test("Eine kleine Abweichung ist nach dem Angleichen ganz eingeholt")
    func eingeholt() {
        var uhr = Stellenuhr()
        uhr.setzen(5, rate: 1, jetzt: 0)
        uhr.melden(5.3, rate: 1, jetzt: 0)   // 0,3 s voraus gemeldet
        #expect(abs(uhr.stelle(jetzt: 0) - 5) < 1e-9)
        #expect(abs(uhr.stelle(jetzt: 2) - 7.3) < 1e-9)
    }

    @Test("Ein Sprung im Lied springt sofort, auch in der Pause")
    func sprung() {
        var uhr = Stellenuhr()
        uhr.setzen(30, rate: 1, jetzt: 0)
        uhr.melden(90, rate: 1, jetzt: 1)
        #expect(abs(uhr.stelle(jetzt: 1) - 90) < 1e-9)
        uhr.melden(90.2, rate: 0, jetzt: 1.2)
        uhr.melden(10, rate: 0, jetzt: 2)
        #expect(abs(uhr.stelle(jetzt: 5) - 10) < 1e-9)
    }

    @Test("Pause steht sofort, dort, wo die Anzeige gerade ist")
    func pause() {
        var uhr = Stellenuhr()
        uhr.setzen(20, rate: 1, jetzt: 0)
        uhr.anhalten(jetzt: 1)
        #expect(abs(uhr.stelle(jetzt: 1) - 21) < 1e-9)
        #expect(abs(uhr.stelle(jetzt: 9) - 21) < 1e-9)
        // Die Meldung der Pause liegt 50 ms daneben: die Anzeige bleibt stehen.
        uhr.melden(20.95, rate: 0, jetzt: 1.1)
        #expect(abs(uhr.stelle(jetzt: 3) - 21) < 1e-9)
        // Weiter: ab dort, weich zur Meldung.
        uhr.melden(20.95, rate: 1, jetzt: 3)
        #expect(abs(uhr.stelle(jetzt: 3) - 21) < 1e-9)
        #expect(abs(uhr.stelle(jetzt: 5) - 22.95) < 1e-9)
    }

    @Test("Nie unter null")
    func nieNegativ() {
        var uhr = Stellenuhr()
        uhr.setzen(0.1, rate: 1, jetzt: 0)
        uhr.melden(0, rate: 1, jetzt: 0.05)
        #expect(uhr.stelle(jetzt: 0.05) >= 0)
    }
}
