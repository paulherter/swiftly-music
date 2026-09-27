import Foundation
import Testing
@testable import MusikKit

@Suite("Lautstärke angleichen")
struct LautheitTests {

    @Test("Ohne Pegel bleibt die volle Lautstärke")
    func ohne() {
        #expect(Lautheitsregel.lautstaerke(nil, albumweise: false) == 1)
        #expect(Lautheitsregel.lautstaerke(Lautheit(), albumweise: true) == 1)
    }

    @Test("−6 dB sind etwa die halbe Lautstärke")
    func absenken() {
        let v = Lautheitsregel.lautstaerke(Lautheit(lied: -6), albumweise: false)
        #expect(abs(v - 0.501) < 0.01)
    }

    @Test("Anheben geht über 1 nicht hinaus")
    func anheben() {
        #expect(Lautheitsregel.lautstaerke(Lautheit(lied: 4), albumweise: false) == 1)
    }

    @Test("Albumweise nimmt den Albumwert, sonst den des Liedes; fehlt einer, gilt der andere")
    func auswahl() {
        let l = Lautheit(lied: -3, album: -9)
        #expect(Lautheitsregel.pegel(l, albumweise: true)?.dB == -9)
        #expect(Lautheitsregel.pegel(l, albumweise: false)?.dB == -3)
        #expect(Lautheitsregel.pegel(Lautheit(album: -9), albumweise: false)?.dB == -9)
        #expect(Lautheitsregel.pegel(Lautheit(lied: -3), albumweise: true)?.dB == -3)
    }

    @Test("Der Spitzenpegel begrenzt")
    func spitze() {
        // −2 dB wären 0,79 — mit Spitze 1,6 höchstens 0,625.
        let v = Lautheitsregel.lautstaerke(Lautheit(lied: -2, liedspitze: 1.6), albumweise: false)
        #expect(abs(v - 0.625) < 0.001)
    }

    @Test("Subsonic: replayGain wird zur Lautheit, ohne Werte zu nichts")
    func subsonic() {
        #expect(SubsonicQuelle.lautheit(nil) == nil)
    }

    @Test("Der Pegel übersteht das Ablegen")
    func ablegen() throws {
        let lied = Lied(id: "1", titel: "x", lautheit: Lautheit(lied: -4.5, album: -6))
        let zurueck = try JSONDecoder().decode(Lied.self, from: JSONEncoder().encode(lied))
        #expect(zurueck.lautheit == Lautheit(lied: -4.5, album: -6))
    }

    @Test("Jellyfin: NormalizationGain wird gelesen")
    func jellyfin() throws {
        let e = try JSONDecoder().decode(JEintrag.self,
                                         from: Data(#"{"Id":"a","Name":"x","NormalizationGain":-7.5}"#.utf8))
        #expect(e.pegel == -7.5)
    }
}
