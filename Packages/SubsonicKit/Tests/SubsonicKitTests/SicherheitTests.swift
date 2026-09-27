import Foundation
import Testing
@testable import SubsonicKit

/// **Die Anfrage-URL trägt die Anmeldung** (`u=`/`t=`/`s=`, im Rückfall
/// `p=enc:<hex>`) — ein `URLError`, wie ihn `URLSession` wirft, hält sie in
/// seinem `userInfo` (`NSErrorFailingURLStringKey`). `Fehlertext.lesbar`
/// schreibt jeden Fehler ins Protokoll; ohne diese Schranke stünde die
/// Anmeldung dort, sobald „Protokoll teilen" ihn zeigt.
@Suite("Kein Zugang in einem Netzfehler")
struct SicherheitTests {

    @Test("Ein URLError von abruf verliert seine Anfrage-URL, bevor der Client ihn wirft")
    func urlErrorOhneAdresse() async throws {
        let client = SubsonicClient(
            zugang: SubsonicZugang(server: URL(string: "https://musik.example.org")!,
                                   benutzer: "demo", passwort: "geheimespasswort"),
            salz: "abcdef123",
            abruf: { anfrage in
                throw URLError(.timedOut, userInfo: [
                    NSURLErrorFailingURLErrorKey: anfrage.url!,
                ])
            })
        do {
            _ = try await client.ping()
            Issue.record("Hätte werfen müssen.")
        } catch let fehler as URLError {
            #expect(fehler.code == .timedOut)
            #expect(fehler.userInfo[NSURLErrorFailingURLErrorKey] == nil)
            let beschreibung = String(describing: fehler as Error)
            #expect(!beschreibung.contains("t="))
            #expect(!beschreibung.contains("s=abcdef123"))
        } catch {
            Issue.record("Falscher Fehlertyp: \(error)")
        }
    }

    @Test("Eine NSError mit Anfrage-URL im userInfo verliert nur diesen Schlüssel")
    func nsErrorOhneAdresse() {
        let mitAdresse = NSError(domain: "Test", code: 1, userInfo: [
            NSURLErrorFailingURLErrorKey: URL(string: "https://musik.example.org/rest/ping.view?u=demo&t=geheim&s=abc")!,
            "anderer": "bleibt",
        ])
        let bereinigt = SubsonicClient.ohneAnfrageAdresse(mitAdresse) as NSError
        #expect(bereinigt.userInfo[NSURLErrorFailingURLErrorKey] == nil)
        #expect(bereinigt.userInfo["anderer"] as? String == "bleibt")
    }

    @Test("Ein Fehler ohne Anfrage-URL kommt unverändert durch")
    func ohneAdresseUnveraendert() {
        let harmlos = SubsonicFehler.keinSubsonic
        let ergebnis = SubsonicClient.ohneAnfrageAdresse(harmlos) as? SubsonicFehler
        #expect(ergebnis == harmlos)
    }
}
