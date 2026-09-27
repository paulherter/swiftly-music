import Foundation
import Testing
@testable import SubsonicKit

@Suite("Prüfsumme für die Token-Anmeldung")
struct PruefsummeTests {

    /// Die Beispiele aus RFC 1321, Anhang A.5.
    @Test("MD5 ohne CryptoKit trifft die Beispiele aus RFC 1321",
          arguments: [
            ("", "d41d8cd98f00b204e9800998ecf8427e"),
            ("a", "0cc175b9c0f1b6a831c399e269772661"),
            ("abc", "900150983cd24fb0d6963f7d28e17f72"),
            ("message digest", "f96b697d7cb7938d525a2f31aaf161d0"),
            ("abcdefghijklmnopqrstuvwxyz", "c3fcd3d76192e4007dfb496cca67e13b"),
            ("12345678901234567890123456789012345678901234567890123456789012345678901234567890",
             "57edf4a22be3c955ac49da2e2107b67a"),
          ])
    func rfc(_ eingabe: String, _ erwartet: String) {
        #expect(MD5Rein.hex(Array(eingabe.utf8)) == erwartet)
        #expect(Pruefsumme.md5Hex(eingabe) == erwartet)
    }

    /// Das Beispiel aus der Subsonic-Beschreibung: Passwort „sesame",
    /// Salz „c19b2d".
    @Test("Das Token aus der Subsonic-Beschreibung")
    func subsonicBeispiel() {
        #expect(Pruefsumme.md5Hex("sesame" + "c19b2d") == "26719a1196d2a940705a59634eb18eab")
    }

    @Test("Umlaute und längere Eingaben rechnen beide Wege gleich")
    func beideWegeGleich() {
        for text in ["Pässwörd+ß", String(repeating: "x", count: 1000), "🎵"] {
            #expect(MD5Rein.hex(Array(text.utf8)) == Pruefsumme.md5Hex(text))
        }
    }
}

@Suite("Anmeldung und Ausweis")
struct AusweisTests {

    @Test("Mit Token stehen u, t, s, v, c und f in der Adresse — das Passwort nicht")
    func tokenAusweis() async throws {
        let attrappe = Attrappe()
        let client = attrappe.client()
        try await client.ping()
        let w = attrappe.werte(0)
        #expect(w["u"] == "demo")
        #expect(w["t"] == Pruefsumme.md5Hex("demo" + "abcdef123"))
        #expect(w["s"] == "abcdef123")
        #expect(w["v"] == "1.16.1")
        #expect(w["c"] == "Swiftly Music")
        #expect(w["f"] == "json")
        #expect(w["p"] == nil)
    }

    @Test("Mit Passwort steht es hexkodiert als enc:")
    func passwortAusweis() throws {
        let attrappe = Attrappe()
        let client = SubsonicClient(
            zugang: SubsonicZugang(server: Attrappe.server, benutzer: "demo", passwort: "sesame",
                                   weise: .passwort),
            abruf: attrappe.abruf)
        let url = try #require(client.coverAdresse(id: "al-1", groesse: 300))
        let w = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(w["p"] == "enc:736573616d65")
        #expect(w["t"] == nil)
        #expect(w["size"] == "300")
        // Bilder sind kein JSON.
        #expect(w["f"] == nil)
    }

    /// Ohne Maskierung käme „C++" beim Server als „C  " an.
    @Test("Ein Plus in der Suche wird maskiert")
    func plusMaskiert() async throws {
        let attrappe = Attrappe(["search3": ["search3"]])
        _ = try await attrappe.client().suche("C++")
        let url = try #require(attrappe.anfragen.first?.url?.absoluteString)
        #expect(url.contains("query=C%2B%2B"))
    }

    @Test("Der Server liegt unter einem Unterpfad")
    func unterpfad() throws {
        let client = SubsonicClient(
            zugang: SubsonicZugang(server: URL(string: "https://example.org/navidrome")!,
                                   benutzer: "demo", passwort: "demo"),
            abruf: Attrappe().abruf)
        let url = try #require(client.streamAdresse(id: "x", format: "raw"))
        #expect(url.path == "/navidrome/rest/stream.view")
    }

    @Test("Anmelden mit Token, wenn der Server es kann")
    func anmeldenMitToken() async throws {
        let attrappe = Attrappe(["ping": ["ping"]])
        let (client, server) = try await SubsonicClient.anmelden(
            server: Attrappe.server, benutzer: "demo", passwort: "demo", abruf: attrappe.abruf)
        #expect(client.weise == .token)
        #expect(server.type == "navidrome")
        #expect(server.openSubsonic)
        #expect(server.anzeigename == "Navidrome 0.64.0")
        #expect(attrappe.anfragen.count == 1)
    }

    /// Code 41: LDAP-Konten können kein Token. Dann einmal mit Passwort.
    @Test("Lehnt der Server das Token ab (41), gilt das Passwort")
    func rueckfallAufPasswort() async throws {
        let attrappe = Attrappe(["ping": ["fehler41", "ping"]])
        let (client, _) = try await SubsonicClient.anmelden(
            server: Attrappe.server, benutzer: "demo", passwort: "demo", abruf: attrappe.abruf)
        #expect(client.weise == .passwort)
        #expect(client.geltenderZugang.weise == .passwort)
        #expect(attrappe.anfragen.count == 2)
        #expect(attrappe.werte(1)["p"] == "enc:64656d6f")
    }

    /// Ein falsches Passwort wird nicht ein zweites Mal geschickt.
    @Test("Falsches Passwort (40) wirft ohne zweiten Versuch")
    func falschesPasswort() async throws {
        let attrappe = Attrappe(["ping": ["fehler40"]])
        await #expect(throws: SubsonicFehler.self) {
            _ = try await SubsonicClient.anmelden(
                server: Attrappe.server, benutzer: "demo", passwort: "falsch", abruf: attrappe.abruf)
        }
        #expect(attrappe.anfragen.count == 1)
        do {
            _ = try await SubsonicClient.anmelden(
                server: Attrappe.server, benutzer: "demo", passwort: "falsch",
                abruf: Attrappe(["ping": ["fehler40"]]).abruf)
        } catch let fehler as SubsonicFehler {
            #expect(fehler.istFalscheAnmeldung)
        }
    }

    /// Lehnt ein Server das Token erst **nach** der Anmeldung ab, wechselt der
    /// laufende Client die Weise, statt jede weitere Anfrage scheitern zu lassen.
    @Test("Rückfall auf das Passwort auch mitten in der Sitzung")
    func rueckfallImLauf() async throws {
        let attrappe = Attrappe(["getAlbum": ["fehler41", "getAlbum"]])
        let client = attrappe.client()
        let album = try await client.album(id: "4QZO6nBGty9odiq7pUok5n")
        #expect(album.name == "Love (All I Was Able To Say)")
        #expect(client.weise == .passwort)
        #expect(attrappe.werte(1)["p"] != nil)
    }

    @Test("Ein Subsonic-Server verrät sich auch ohne Anmeldung")
    func erkennen() async throws {
        let attrappe = Attrappe(["ping": ["fehler10_ohneAnmeldung"]])
        let server = try await SubsonicClient.erkennen(server: Attrappe.server,
                                                       abruf: attrappe.abruf)
        #expect(server.type == "navidrome")
        #expect(attrappe.werte(0)["u"] == nil)
    }

    @Test("Eine Webseite ist kein Subsonic")
    func keinSubsonic() async throws {
        let attrappe = Attrappe(["ping": ["keinSubsonic.html"]])
        await #expect(throws: SubsonicFehler.keinSubsonic) {
            _ = try await SubsonicClient.erkennen(server: Attrappe.server, abruf: attrappe.abruf)
        }
    }

    @Test("Ein Subsonic ohne OpenSubsonic heißt nach der Schnittstelle")
    func alterServer() async throws {
        let attrappe = Attrappe(["ping": ["ping_subsonic"]])
        let server = try await attrappe.client().ping()
        #expect(!server.openSubsonic)
        #expect(server.anzeigename == "Subsonic 1.16.1")
    }

    /// Eine alte Ablage ohne `weise` bleibt lesbar.
    @Test("Der Zugang liest eine Ablage ohne Anmeldeweise")
    func alteAblage() throws {
        let json = #"{"server":"https://musik.example.org","benutzer":"demo","passwort":"x"}"#
        let zugang = try JSONDecoder().decode(SubsonicZugang.self, from: Data(json.utf8))
        #expect(zugang.weise == .token)
        let wieder = try JSONDecoder().decode(SubsonicZugang.self,
                                              from: JSONEncoder().encode(zugang))
        #expect(wieder == zugang)
    }

    @Test("Das Salz ist sechzehn Hexzeichen lang und wechselt")
    func salz() {
        let a = Salz.neu(), b = Salz.neu()
        #expect(a.count == 16)
        #expect(a.allSatisfy { $0.isHexDigit })
        #expect(a != b)
    }
}
