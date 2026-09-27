import Foundation
import Testing
@testable import MusikKit

@Suite("Mit Jellyfin aushandeln")
struct AushandelnTests {
    private let flac = Tonformat(codec: "flac", behaelter: "flac")
    private let aac = Tonformat(codec: "aac", behaelter: "m4a", bitrate: 128)

    @Test("Die Antwort: kein Direktspielen, Rate aus der TranscodingUrl")
    func lesen() throws {
        let e = try #require(Serverentscheid.lesen(try fixture("jf_playbackinfo")))
        #expect(!e.direkt)
        #expect(e.hoechstrate == 192)
        #expect(Serverentscheid.lesen(Data("{}".utf8)) == nil)
    }

    @Test("Die strengere Grenze gilt; verbietet der Server Direkt, wird umgewandelt")
    func zusammen() {
        let erlaubt = Serverentscheid(direkt: true, hoechstrate: nil)
        let gedeckelt = Serverentscheid(direkt: true, hoechstrate: 128)
        let verboten = Serverentscheid(direkt: false, hoechstrate: nil)
        #expect(Serverentscheid.umwandlung(fuer: flac, hoechstens: nil, server: erlaubt) == nil)
        #expect(Serverentscheid.umwandlung(fuer: flac, hoechstens: 256, server: gedeckelt)?.bitrate == 128)
        #expect(Serverentscheid.umwandlung(fuer: aac, hoechstens: nil, server: verboten)?.bitrate == 320)
        #expect(Serverentscheid.umwandlung(fuer: aac, hoechstens: 192, server: nil) == nil)
    }

    @Test("Das Geräteprofil nennt dieselben Behälter wie die eigene Regel")
    func profil() throws {
        let rumpf = try #require(try JSONSerialization.jsonObject(with: Geraeteprofil.rumpf(hoechstens: 192))
                                 as? [String: Any])
        let profil = try #require(rumpf["DeviceProfile"] as? [String: Any])
        #expect(profil["MaxStreamingBitrate"] as? Int == 192_000)
        let direkt = try #require((profil["DirectPlayProfiles"] as? [[String: Any]])?.first)
        #expect((direkt["Container"] as? String)?.contains("flac") == true)
    }
}

extension JellyfinQuelleTests {
    @Test("Jellyfin: nach dem Aushandeln gilt, was der Server sagt")
    func aushandeln() async throws {
        let quelle = await Jellyfinstelle.quelle(["/Items/l1/PlaybackInfo": "jf_playbackinfo"])
        let lied = Lied(id: "l1", titel: "", format: Tonformat(codec: "flac", behaelter: "flac"))
        #expect(quelle.abspielweg(lied, sitzung: "s")?.art == .direkt)
        await quelle.vorbereiten([lied], hoechstens: nil)
        let anfrage = try #require(Jellyfinstelle.anfragen.last)
        #expect(anfrage.httpMethod == "POST")
        let weg = try #require(quelle.abspielweg(lied, sitzung: "s"))
        #expect(weg.art == .umgewandelt)
        #expect(Jellyfinstelle.werte(URLRequest(url: weg.adresse))["audioBitRate"] == "192000")
        // Geladen wird trotzdem das Original.
        #expect(quelle.ladeweg(lied)?.art == .direkt)
    }
}
