import Foundation
import Testing
@testable import MusikKit

@Suite("Genaue Fassung gestreamter FLAC-Dateien")
struct GenaufassungTests {

    private let flac = Tonformat(codec: "flac", behaelter: "flac")

    private func weg(_ adresse: String, art: Abspielart = .direkt, format: Tonformat? = nil,
                     mime: String? = nil) -> Abspielweg {
        Abspielweg(adresse: URL(string: adresse)!, mime: mime, art: art, format: format)
    }

    @Test("Jellyfin und Subsonic: FLAC direkt vom Server")
    func betrifft() {
        #expect(Genaufassung.betrifft(weg("https://s/Audio/1/stream.flac?static=true", format: flac)))
        #expect(Genaufassung.betrifft(weg("https://s/rest/stream.view?id=1&format=raw", format: flac)))
        #expect(Genaufassung.betrifft(weg("https://s/rest/stream.view?id=1&format=raw", mime: "audio/flac")))
    }

    @Test("Nicht: auf dem Gerät, umgewandelt, anderes Format")
    func betrifftNicht() {
        #expect(!Genaufassung.betrifft(weg("file:///ablage/1.flac", format: flac)))
        #expect(!Genaufassung.betrifft(weg("https://s/Audio/1/stream.mp3", art: .umgewandelt, format: flac)))
        #expect(!Genaufassung.betrifft(weg("https://s/Audio/1/stream.m4a",
                                           format: Tonformat(codec: "flac", behaelter: "m4a"))))
        #expect(!Genaufassung.betrifft(weg("https://s/Audio/1/stream.mp3",
                                           format: Tonformat(codec: "mp3", behaelter: "mp3"))))
    }

    @Test("Laden nur im WLAN, nicht im Datensparmodus")
    func netz() {
        #expect(Genaufassung.darfLaden(.wlan, sparsam: false))
        #expect(!Genaufassung.darfLaden(.wlan, sparsam: true))
        #expect(!Genaufassung.darfLaden(.mobil, sparsam: false))
        #expect(!Genaufassung.darfLaden(.keine, sparsam: false))
    }

    @Test("Nicht nachladen, was den genauen Zugriff schon hat")
    func nachladen() {
        let w = weg("https://s/Audio/1/stream.flac?static=true", format: flac)
        #expect(Genaufassung.nachladen(w, schonGenau: false, verbindung: .wlan, sparsam: false))
        #expect(!Genaufassung.nachladen(w, schonGenau: true, verbindung: .wlan, sparsam: false))
        #expect(!Genaufassung.nachladen(w, schonGenau: false, verbindung: .mobil, sparsam: false))
    }

    @Test("Einwechseln: in der Pause, nicht während eines Sprungs, nicht kurz vor dem Ende")
    func einwechseln() {
        func e(_ stelle: Double, _ dauer: Double?, springt: Bool = false, bereit: Bool = true,
               laeuft: Bool = false, verrutscht: Bool = false) -> Genaufassung.Einwechseln {
            Genaufassung.einwechseln(stelle: stelle, dauer: dauer, springt: springt, bereit: bereit,
                                     laeuft: laeuft, verrutscht: verrutscht)
        }
        #expect(e(30, 200) == .jetzt)
        #expect(e(30, nil) == .jetzt)
        #expect(e(30, 200, springt: true) == .spaeter)
        #expect(e(30, 200, bereit: false) == .spaeter)
        #expect(e(197, 200) == .nicht)
        #expect(e(197, 200, laeuft: true, verrutscht: true) == .nicht)
    }

    @Test("Im Spielen nur, wenn ein ungenauer Sprung Ton und Anzeige getrennt hat")
    func imSpielen() {
        #expect(Genaufassung.einwechseln(stelle: 30, dauer: 200, springt: false, bereit: true,
                                         laeuft: true, verrutscht: false) == .spaeter)
        #expect(Genaufassung.einwechseln(stelle: 30, dauer: 200, springt: false, bereit: true,
                                         laeuft: true, verrutscht: true) == .jetzt)
    }

    @Test("Vorlauf nur, während es läuft")
    func vorlauf() {
        #expect(Genaufassung.vorlauf(laeuft: false) == 0)
        #expect(Genaufassung.vorlauf(laeuft: true) > 0)
        #expect(Genaufassung.vorlauf(laeuft: true) < 1)
    }

    @Test("Ein Sprung wartet nur, wenn die Datei in unter einer Sekunde da ist")
    func sprungAbwarten() {
        #expect(Genaufassung.sprungAbwarten(restzeit: 0.4))
        #expect(!Genaufassung.sprungAbwarten(restzeit: 1.5))
        #expect(!Genaufassung.sprungAbwarten(restzeit: nil))
    }

    @Test("Restzeit gleichmäßig weitergerechnet, erst wenn sie etwas taugt")
    func restzeit() {
        #expect(Genaufassung.restzeit(anteil: 0.5, seit: 4) == 4)
        #expect(Genaufassung.restzeit(anteil: 0.9, seit: 9)!.isApproximatelyEqual(to: 1))
        #expect(Genaufassung.restzeit(anteil: 1, seit: 3) == 0)
        #expect(Genaufassung.restzeit(anteil: 0, seit: 3) == nil)
        #expect(Genaufassung.restzeit(anteil: 0.5, seit: 0.1) == nil)
    }
}

private extension Double {
    func isApproximatelyEqual(to other: Double) -> Bool { abs(self - other) < 1e-9 }
}
