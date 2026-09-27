import Foundation
import JellyfinKit
import SubsonicKit
@testable import MusikKit
import Testing

/// Liest eine Datei aus `Fixtures/Sonos`.
private func sonosFixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures/Sonos") else {
        throw URLError(.fileDoesNotExist)
    }
    return try Data(contentsOf: url)
}

@Suite("Sonos: Schnittstelle")
struct SonosSchnittstelleTests {

    @Test("SOAP-Hülle: Dienst, Kopf, maskierte Werte in ihrer Reihenfolge")
    func huelle() throws {
        let a = SonosSoap.anfrage(.avTransport, "SetAVTransportURI",
                                  ["InstanceID": "0", "CurrentURI": "http://s/a?x=1&y=2", "CurrentURIMetaData": "<DIDL/>"])
        #expect(a.pfad == "/MediaRenderer/AVTransport/Control")
        #expect(a.soapAction == "\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"")
        #expect(a.rumpf.contains("<InstanceID>0</InstanceID><CurrentURI>http://s/a?x=1&amp;y=2</CurrentURI>"
            + "<CurrentURIMetaData>&lt;DIDL/&gt;</CurrentURIMetaData>"))
        let r = a.urlRequest(basis: URL(string: "http://192.168.1.21:1400")!)
        #expect(r.url?.absoluteString == "http://192.168.1.21:1400/MediaRenderer/AVTransport/Control")
        #expect(r.value(forHTTPHeaderField: "SOAPACTION") == a.soapAction)
        #expect(r.httpMethod == "POST")
        // Die Hülle selbst ist wohlgeformt und trägt die Werte unverfälscht.
        let baum = try #require(SonosKnoten.lesen(a.rumpf))
        #expect(baum.wert("CurrentURI") == "http://s/a?x=1&y=2")
        #expect(baum.wert("CurrentURIMetaData") == "<DIDL/>")
    }

    @Test("Antwort lesen: Stelle, Dauer, Adresse, Zustand")
    func antworten() throws {
        let p = try SonosSoap.antwort(try sonosFixture("getpositioninfo"), status: 200, aktion: "GetPositionInfo")
        #expect(SonosZeit.lesen(p["RelTime"]) == 73)
        #expect(SonosZeit.lesen(p["TrackDuration"]) == 201)
        #expect(p["TrackURI"] == "https://musik.example/Audio/l2/stream.flac?static=true&ApiKey=geheim")
        #expect(SonosDIDL.titel(p["TrackMetaData"]) == "Drift & Treiben")
        let t = try SonosSoap.antwort(try sonosFixture("gettransportinfo"), status: 200, aktion: "GetTransportInfo")
        #expect(SonosLage.Zustand(t["CurrentTransportState"]) == .pausiert)
        let m = try SonosSoap.antwort(try sonosFixture("getmediainfo"), status: 200, aktion: "GetMediaInfo")
        #expect(m["NextURI"] == "")
        let v = try SonosSoap.antwort(try sonosFixture("getvolume"), status: 200, aktion: "GetVolume")
        #expect(v["CurrentVolume"] == "23")
    }

    @Test("Fehler: UPnP-Code aus s:Fault; 714/716 heißt, er kommt nicht an die Quelle")
    func fehler() throws {
        #expect(throws: SonosFehler.abgelehnt(status: 500, upnp: 701)) {
            try SonosSoap.antwort(try sonosFixture("fault"), status: 500, aktion: "Play")
        }
        #expect(SonosFehler.abgelehnt(status: 500, upnp: 716).quelleUnerreichbar)
        #expect(!SonosFehler.abgelehnt(status: 500, upnp: 402).quelleUnerreichbar)
        #expect(throws: SonosFehler.unlesbar) {
            try SonosSoap.antwort(Data("kein xml".utf8), status: 200, aktion: "Play")
        }
    }

    @Test("Zeit: lesen und für Seek schreiben")
    func zeit() {
        #expect(SonosZeit.lesen("0:03:21") == 201)
        #expect(SonosZeit.lesen("00:00:05.500") == 5.5)
        #expect(SonosZeit.lesen("NOT_IMPLEMENTED") == nil)
        #expect(SonosZeit.lesen("") == nil)
        #expect(SonosZeit.schreiben(3725.9) == "1:02:05")
        #expect(SonosZeit.schreiben(-4) == "0:00:00")
    }

    @Test("Gruppen: Koordinator vorn, ohne Stereo-Zweitbox, Sub und Boost")
    func gruppen() throws {
        let w = try SonosSoap.antwort(try sonosFixture("getzonegroupstate"), status: 200, aktion: "GetZoneGroupState")
        let gruppen = SonosTopologie.gruppen(w["ZoneGroupState"] ?? "")
        #expect(gruppen.map(\.name) == ["Fernsehzimmer", "Schlafzimmer", "Wohnzimmer + 1"])
        let wohn = try #require(gruppen.last)
        #expect(wohn.koordinator.id == "RINCON_000E58A0000101400")
        #expect(wohn.mitglieder.map(\.name) == ["Wohnzimmer", "Küche"])
        #expect(wohn.koordinator.basis.absoluteString == "http://192.168.1.21:1400")
        #expect(gruppen[1].mitglieder.count == 1)
        #expect(gruppen[0].mitglieder.count == 1)
        #expect(SonosTopologie.lautsprecher(gruppen).map(\.name) == ["Fernsehzimmer", "Küche", "Schlafzimmer", "Wohnzimmer"])
        // Ältere Firmware ohne <ZoneGroupState> außen herum.
        let alt = try SonosSoap.antwort(try sonosFixture("getzonegroupstate_alt"), status: 200, aktion: "GetZoneGroupState")
        #expect(SonosTopologie.gruppen(alt["ZoneGroupState"] ?? "").map(\.name) == gruppen.map(\.name))
    }

    @Test("Zeilen im Blatt: Gruppe zusammen, Koordinator vorn; Vorgemerktes wandert, der nächste führt")
    func zeilen() {
        func l(_ n: String) -> SonosLautsprecher { SonosLautsprecher(id: n, name: n, basis: URL(string: "http://h")!) }
        let bad = SonosGruppe(id: "b:1", koordinator: l("Badezimmer"), mitglieder: [l("Badezimmer")])
        let kueche = SonosGruppe(id: "k:1", koordinator: l("Küche"), mitglieder: [l("Küche")])
        let wohn = SonosGruppe(id: "w:1", koordinator: l("Wohnzimmer"), mitglieder: [l("Wohnzimmer")])
        var z = Sonoszeile.zeilen([bad, kueche, wohn], ziel: "Badezimmer", vorgemerkt: [:])
        #expect(z.map(\.id) == ["Badezimmer", "Küche", "Wohnzimmer"])
        #expect(z.allSatisfy { $0.kopf && $0.ende })
        #expect(z.map(\.unser) == [true, false, false])

        // Wohnzimmer angetippt: rückt sofort unter Badezimmer, eine Karte.
        z = Sonoszeile.zeilen([bad, kueche, wohn], ziel: "Badezimmer", vorgemerkt: ["Wohnzimmer": true])
        #expect(z.map(\.id) == ["Badezimmer", "Wohnzimmer", "Küche"])
        #expect(z[0].kopf && !z[0].ende && !z[1].kopf && z[1].ende)
        #expect(z[0].gruppe.name == "Badezimmer + 1")

        // Der Koordinator geht: Wohnzimmer führt, Badezimmer steht allein.
        let beide = SonosGruppe(id: "b:2", koordinator: l("Badezimmer"), mitglieder: [l("Badezimmer"), l("Wohnzimmer")])
        z = Sonoszeile.zeilen([beide, kueche], ziel: "Badezimmer", vorgemerkt: ["Badezimmer": false])
        #expect(z.map(\.id) == ["Wohnzimmer", "Badezimmer", "Küche"])
        #expect(z.allSatisfy { $0.kopf && $0.ende })
        #expect(z.first { $0.id == "Wohnzimmer" }?.gruppe.id == "b:2")
        #expect(z.filter(\.unser).map(\.id) == ["Wohnzimmer"])
        // Auch, wenn der Spieler schon den neuen Koordinator kennt, die Gruppen noch nicht.
        let danach = Sonoszeile.zeilen([beide, kueche], ziel: "Wohnzimmer", vorgemerkt: ["Badezimmer": false])
        #expect(danach == z)
    }

    @Test("Bild aus dem Modell: Soundbar, Verstärker, tragbar, sonst Standlautsprecher")
    func zeichen() {
        #expect(SonosTopologie.zeichen(modell: "Sonos Arc Ultra") == "tv.and.hifispeaker.fill")
        #expect(SonosTopologie.zeichen(modell: "Sonos Amp") == "hifireceiver.fill")
        #expect(SonosTopologie.zeichen(modell: "Sonos Roam 2") == "speaker.fill")
        #expect(SonosTopologie.zeichen(modell: "Sonos Era 100") == "hifispeaker.fill")
        #expect(SonosTopologie.zeichen(modell: nil) == "hifispeaker.fill")
    }

    @Test("Gerätebeschreibung: Kennung ohne uuid:, Raum, Modell — nicht das Unterteil")
    func beschreibung() throws {
        let b = try #require(SonosBeschreibung.lesen(try sonosFixture("device_description")))
        #expect(b.id == "RINCON_000E58A0000101400")
        #expect(b.raum == "Wohnzimmer")
        #expect(b.modell == "Sonos One")
    }
}

@Suite("Sonos: Regeln")
struct SonosRegelTests {

    @Test("Direkt: MP3, AAC, FLAC und ALAC bis 24/48; sonst MP3 320")
    func format() {
        #expect(Sonosregel.umwandlung(fuer: Tonformat(codec: "mp3", behaelter: "mp3")) == nil)
        #expect(Sonosregel.umwandlung(fuer: Tonformat(codec: "aac", behaelter: "m4a")) == nil)
        #expect(Sonosregel.umwandlung(fuer: Tonformat(codec: "alac", behaelter: "m4a", bitTiefe: 24, abtastrate: 48_000)) == nil)
        #expect(Sonosregel.umwandlung(fuer: Tonformat(codec: "flac", behaelter: "flac", bitTiefe: 16, abtastrate: 44_100)) == nil)
        #expect(Sonosregel.umwandlung(fuer: Tonformat(codec: "flac", behaelter: "flac", bitTiefe: 24, abtastrate: 96_000))
            == Umwandlung(codec: "mp3", bitrate: 320))
        #expect(Sonosregel.umwandlung(fuer: Tonformat(codec: "opus", behaelter: "ogg")) != nil)
        #expect(Sonosregel.umwandlung(fuer: Tonformat(codec: "pcm_s16le", behaelter: "wav")) != nil)
        #expect(Sonosregel.umwandlung(fuer: nil) == nil)
    }

    @Test("DIDL-Lite: Titel, Künstler*in, Album, Hülle, Adresse — alles maskiert")
    func didl() throws {
        let lied = Lied(id: "l1", titel: "Rock & Roll", kuenstler: "AC/DC", album: "<Live>", dauer: 201)
        let text = SonosDIDL.metadaten(lied, adresse: URL(string: "http://s/Audio/l1/stream.flac?static=true&ApiKey=k")!,
                                       mime: "audio/flac", huelle: URL(string: "http://s/Items/a/Images/Primary?maxWidth=600")!)
        let baum = try #require(SonosKnoten.lesen(text))
        #expect(baum.wert("title") == "Rock & Roll")
        #expect(baum.wert("creator") == "AC/DC")
        #expect(baum.wert("album") == "<Live>")
        #expect(baum.wert("albumArtURI") == "http://s/Items/a/Images/Primary?maxWidth=600")
        #expect(baum.wert("res") == "http://s/Audio/l1/stream.flac?static=true&ApiKey=k")
        #expect(baum.finde("res")?.attribute["protocolInfo"] == "http-get:*:audio/flac:*")
        #expect(baum.finde("res")?.attribute["duration"] == "0:03:21.000")
        #expect(baum.wert("class") == "object.item.audioItem.musicTrack")
    }

    private func schlange(_ n: Int, ab: Int = 0, wiederholung: Warteschlange.Wiederholung = .aus) -> Warteschlange {
        var s = Warteschlange()
        s.setzen((0 ..< n).map { Lied(id: "l\($0)", titel: "Lied \($0)", dauer: 180) }, ab: ab, mischen: false)
        s.wiederholen(wiederholung)
        return s
    }

    @Test("Das nächste für Sonos: das nächste der Schlange, bei „ein Lied“ dasselbe")
    func naechster() {
        #expect(Sonosfolge.naechster(schlange(3))?.lied.id == "l1")
        #expect(Sonosfolge.naechster(schlange(3, ab: 2)) == nil)
        #expect(Sonosfolge.naechster(schlange(3, ab: 2, wiederholung: .alles))?.lied.id == "l0")
        let eines = schlange(3, ab: 1, wiederholung: .eines)
        #expect(Sonosfolge.naechster(eines)?.id == eines.aktuell?.id)
    }

    @Test("Befund: gleich, weiter, fremd, leer — auch bei zweimal derselben Adresse")
    func befund() {
        let a = UUID(), b = UUID()
        let g = SonosGesendet(adresse: "http://s/1?x=%2C", eintrag: a, naechsteAdresse: "http://s/2", naechsterEintrag: b)
        func lage(_ spur: String?, naechstes: String? = nil) -> SonosLage {
            SonosLage(zustand: .spielt, spur: spur, geladen: spur, naechstesGeladen: naechstes, stelle: 3, dauer: 180)
        }
        func befund(_ l: SonosLage, _ gesendet: SonosGesendet = g) -> Sonosfolge.Befund {
            Sonosfolge.befund(l, gesendet: gesendet)
        }
        let b1 = befund(lage("http://s/1?x=%2C", naechstes: "http://s/2"))
        let b2 = befund(lage("http://s/1?x=,"))
        let b3 = befund(lage("http://s/2"))
        let b4 = befund(lage("x-sonos-spotify:abc"))
        let b5 = befund(lage(nil))
        #expect(b1 == .gleich)
        #expect(b2 == .gleich)
        #expect(b3 == .weiter)
        #expect(b4 == .fremd)
        #expect(b5 == .leer)
        let gleich = SonosGesendet(adresse: "http://s/1", eintrag: a, naechsteAdresse: "http://s/1", naechsterEintrag: a)
        let b6 = befund(lage("http://s/1", naechstes: "http://s/1"), gleich)
        let b7 = befund(lage("http://s/1", naechstes: nil), gleich)
        #expect(b6 == .gleich)
        #expect(b7 == .weiter)
    }

    @Test("Der Stand als Sitzung: unsere Schlange, die Stelle von drüben; Fernstand rechnet weiter")
    func sitzung() {
        let s = schlange(3, ab: 1)
        let jetzt = Date()
        let lage = SonosLage(zustand: .spielt, spur: "x", geladen: "x", naechstesGeladen: nil, stelle: 42, dauer: 180)
        let sitzung = Sonosfolge.sitzung(id: "sonos:A", name: "Wohnzimmer", schlange: s, lage: lage,
                                         unser: true, abgefragt: jetzt)
        #expect(sitzung.lied?.id == "l1")
        #expect(sitzung.index == 1)
        #expect(!sitzung.angehalten)
        var stand = Fernstand(sitzung, jetzt: jetzt)
        #expect(stand.stelle(jetzt: jetzt.addingTimeInterval(2)) == 44)
        // Ein eigener Befehl gilt sofort; die Abfrage davor überholt ihn nicht.
        let marke = stand.marke(jetzt: jetzt)
        stand.vormerken(.pause, jetzt: jetzt.addingTimeInterval(2))
        _ = stand.abgleichen([sitzung], marke: marke, jetzt: jetzt.addingTimeInterval(2.5))
        #expect(stand.angehalten)
        // Läuft dort etwas anderes, bleibt unser Lied stehen — angehalten.
        let fremd = Sonosfolge.sitzung(id: "sonos:A", name: "Wohnzimmer", schlange: s, lage: lage,
                                       unser: false, abgefragt: jetzt)
        var zweiter = Fernstand(sitzung, jetzt: jetzt)
        _ = zweiter.abgleichen([fremd], jetzt: jetzt.addingTimeInterval(1))
        #expect(zweiter.gestoppt)
        #expect(zweiter.lied?.id == "l1")
    }

    @Test("Anlauf: spielt er nach der Frist nicht, ist der Server von dort nicht erreichbar")
    func anlauf() {
        let t = Date()
        var a = Sonosanlauf()
        a.gestartet(jetzt: t)
        let steht = SonosLage(zustand: .gestoppt, spur: "x", geladen: "x", naechstesGeladen: nil, stelle: 0, dauer: nil)
        let e1 = a.gescheitert(steht, jetzt: t.addingTimeInterval(3))
        #expect(!e1)
        let e2 = a.gescheitert(steht, jetzt: t.addingTimeInterval(Sonosanlauf.frist))
        #expect(e2)
        let e3 = a.gescheitert(steht, jetzt: t.addingTimeInterval(30))
        #expect(!e3)
        var b = Sonosanlauf()
        b.gestartet(jetzt: t)
        let spielt = SonosLage(zustand: .spielt, spur: "x", geladen: "x", naechstesGeladen: nil, stelle: 1, dauer: nil)
        let e4 = b.gescheitert(spielt, jetzt: t.addingTimeInterval(2))
        #expect(!e4)
        let e5 = b.gescheitert(steht, jetzt: t.addingTimeInterval(20))
        #expect(!e5)
    }

    @Test("Geräteliste: nur Swiftly Music, wenn so verlangt")
    func nurSwiftly() {
        func s(_ id: String, _ programm: String) -> Musiksitzung {
            Musiksitzung(id: id, benutzerID: "u1", geraeteID: id, geraetename: id, programm: programm)
        }
        let alle = [s("web", "Jellyfin Web"), s("ipad", "Swiftly Music"), s("finamp", "Finamp")]
        #expect(Geraeteliste.auswahl(alle, eigeneGeraeteID: "ich", eigeneBenutzerID: "u1",
                                     programme: Geraeteliste.swiftlyProgramme).map(\.id) == ["ipad"])
        #expect(Geraeteliste.auswahl(alle, eigeneGeraeteID: "ich", eigeneBenutzerID: "u1").count == 3)
    }
}

/// **Gegen einen Schein-Haushalt über echtes HTTP** — Laden, Weiter,
/// Lautstärke und Gruppieren, so wie die App es tut.
@Suite("Sonos: Ablauf mit Schein-Lautsprechern", .serialized)
struct SonosAblaufTests {

    private func spur(_ e: Warteschlange.Eintrag) -> Sonosspur {
        let url = URL(string: "http://server.example/Audio/\(e.lied.id)/stream.flac?static=true&ApiKey=k")!
        return Sonosspur(eintrag: e.id, adresse: url.absoluteString,
                         metadaten: SonosDIDL.metadaten(e.lied, adresse: url, mime: "audio/flac", huelle: nil))
    }

    private func schlange() -> Warteschlange {
        var s = Warteschlange()
        s.setzen((0 ..< 3).map { Lied(id: "l\($0)", titel: "Lied \($0)", dauer: 180) }, ab: 0, mischen: false)
        return s
    }

    @Test("Laden, spielen, pausieren, springen; von selbst ins nächste; das nächste nachziehen")
    func abspielen() async throws {
        let haus = try await ScheinHaushalt(["Wohnzimmer"])
        let wohn = haus.lautsprecher("Wohnzimmer")
        let st = Sonossteuerung(koordinator: wohn)
        var s = schlange()
        try await st.laden(spur(s.aktuell!), naechste: Sonosfolge.naechster(s).map(spur), stelle: 42, spielen: true)
        var z = haus.zustand("Wohnzimmer")
        #expect(z.zustand == "PLAYING")
        #expect(z.adresse.contains("/Audio/l0/"))
        #expect(z.naechste.contains("/Audio/l1/"))
        #expect(z.stelle == 42)
        #expect(SonosDIDL.titel(z.metadaten) == "Lied 0")
        #expect(haus.aktionen.prefix(5) == ["SetPlayMode", "SetAVTransportURI", "SetNextAVTransportURI", "Seek", "Play"])

        var a = try await st.abfragen()
        #expect(a.befund == .gleich)
        #expect(a.lage.laeuft)
        #expect(a.lage.stelle == 42)

        try await st.pausieren()
        #expect(haus.zustand("Wohnzimmer").zustand == "PAUSED_PLAYBACK")
        try await st.springen(90)
        #expect(haus.zustand("Wohnzimmer").stelle == 90)
        try await st.abspielen()

        // Das Lied ist aus: Sonos geht ins nächste, wir rücken nach.
        haus.liedZuEnde("Wohnzimmer")
        a = try await st.abfragen()
        #expect(a.befund == .weiter)
        let zweites = try #require(s.naechster)
        #expect(a.eintrag == zweites.id)
        s.springe(zu: zweites.id)
        try await st.naechsteSetzen(Sonosfolge.naechster(s).map(spur))
        z = haus.zustand("Wohnzimmer")
        #expect(z.adresse.contains("/Audio/l1/"))
        #expect(z.naechste.contains("/Audio/l2/"))
        a = try await st.abfragen()
        #expect(a.befund == .gleich)
        #expect(a.eintrag == zweites.id)

        // Ein zweites Mal dasselbe nächste schickt nichts.
        let vorher = haus.aktionen.count
        try await st.naechsteSetzen(Sonosfolge.naechster(s).map(spur))
        #expect(haus.aktionen.count == vorher)

        // Am Ende der Schlange: kein nächstes, er hält an.
        s.weiter()
        try await st.laden(spur(s.aktuell!), naechste: Sonosfolge.naechster(s).map(spur), stelle: 0, spielen: true)
        #expect(haus.zustand("Wohnzimmer").naechste == "")
        haus.liedZuEnde("Wohnzimmer")
        a = try await st.abfragen()
        #expect(a.befund == .leer)
        #expect(!a.lage.laeuft)
    }

    @Test("Jemand anderes übernimmt: fremd")
    func fremd() async throws {
        let haus = try await ScheinHaushalt(["Küche"])
        let st = Sonossteuerung(koordinator: haus.lautsprecher("Küche"))
        let s = schlange()
        try await st.laden(spur(s.aktuell!), naechste: nil, stelle: 0, spielen: true)
        haus.fremdSpielen("Küche")
        let befund = try await st.abfragen().befund
        #expect(befund == .fremd)
    }

    @Test("Eine Adresse, an die er nicht herankommt: er steht, der Anlauf merkt es")
    func unerreichbar() async throws {
        let haus = try await ScheinHaushalt(["Bad"])
        let st = Sonossteuerung(koordinator: haus.lautsprecher("Bad"))
        let e = schlange().aktuell!
        let s = Sonosspur(eintrag: e.id, adresse: "http://unerreichbar.local/a.flac", metadaten: "")
        try await st.laden(s, naechste: nil, stelle: 0, spielen: true)
        let lage = try await st.abfragen().lage
        var anlauf = Sonosanlauf()
        let t = Date()
        anlauf.gestartet(jetzt: t)
        let e6 = anlauf.gescheitert(lage, jetzt: t.addingTimeInterval(Sonosanlauf.frist))
        #expect(e6)
    }

    @Test("Lautstärke: je Lautsprecher und für die Gruppe")
    func lautstaerke() async throws {
        let haus = try await ScheinHaushalt(["Wohnzimmer", "Küche"])
        let wohn = SonosClient(basis: haus.lautsprecher("Wohnzimmer").basis)
        let kueche = SonosClient(basis: haus.lautsprecher("Küche").basis)
        try await wohn.lautstaerkeSetzen(35)
        #expect(try await wohn.lautstaerke() == 35)
        try await wohn.lautstaerkeSetzen(140)
        #expect(try await wohn.lautstaerke() == 100)
        try await kueche.beitreten(haus.id("Wohnzimmer"))
        try await wohn.gruppenlautstaerkeSetzen(30)
        #expect(try await wohn.gruppenlautstaerke() == 30)
        #expect(try await kueche.lautstaerke() == 30)
        #expect(haus.aktionen.contains("SnapshotGroupVolume"))
    }

    @Test("Gruppieren: dazuholen, lösen, und der Koordinator geht — die Gruppe spielt weiter")
    func gruppieren() async throws {
        let haus = try await ScheinHaushalt(["Wohnzimmer", "Küche", "Bad"])
        let wohn = SonosClient(basis: haus.lautsprecher("Wohnzimmer").basis)
        let kueche = SonosClient(basis: haus.lautsprecher("Küche").basis)
        let bad = SonosClient(basis: haus.lautsprecher("Bad").basis)
        #expect(try await wohn.gruppen().count == 3)
        #expect(try await wohn.beschreibung().raum == "Wohnzimmer")

        try await kueche.beitreten(haus.id("Wohnzimmer"))
        try await bad.beitreten(haus.id("Wohnzimmer"))
        var gruppen = try await bad.gruppen()
        #expect(gruppen.map(\.name) == ["Wohnzimmer + 2"])
        #expect(gruppen[0].mitglieder.map(\.name) == ["Wohnzimmer", "Bad", "Küche"])

        // Ein Mitglied lösen.
        try await bad.alleinstellen()
        gruppen = try await wohn.gruppen()
        #expect(Set(gruppen.map(\.name)) == ["Bad", "Wohnzimmer + 1"])

        // Der Koordinator geht, während es läuft: die Küche spielt weiter.
        let st = Sonossteuerung(koordinator: haus.lautsprecher("Wohnzimmer"))
        let s = schlange()
        try await st.laden(spur(s.aktuell!), naechste: nil, stelle: 10, spielen: true)
        try await wohn.alleinstellen()
        gruppen = try await wohn.gruppen()
        #expect(Set(gruppen.map(\.name)) == ["Bad", "Küche", "Wohnzimmer"])
        #expect(haus.zustand("Küche").zustand == "PLAYING")
        #expect(haus.zustand("Küche").adresse.contains("/Audio/l0/"))
        #expect(haus.zustand("Wohnzimmer").zustand == "STOPPED")
    }
}

@Suite("Sonos: Adressen beim Server")
struct SonosAdressenTests {

    private func werte(_ url: URL) -> [String: String] {
        var w: [String: String] = [:]
        for q in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] { w[q.name] = q.value }
        return w
    }

    @Test("Jellyfin: direkt mit ApiKey, zu viel für Sonos als MP3; mit Metadaten als Spur")
    func jellyfin() throws {
        let quelle = JellyfinQuelle(
            client: JellyfinClient(baseURL: URL(string: "https://musik.example.de")!, deviceID: "g",
                                   deviceName: "iPhone", programm: "Swiftly Music"),
            sitzung: Session(accessToken: "tok", userID: "u1", userName: "n",
                             serverURL: URL(string: "https://musik.example.de")!),
            geraeteID: "g")
        #expect(quelle.sonosMoeglich)
        let cd = Lied(id: "l1", titel: "A", format: Tonformat(codec: "flac", behaelter: "flac", bitTiefe: 16, abtastrate: 44_100))
        let weg = try #require(quelle.sonosweg(cd))
        #expect(weg.art == .direkt)
        #expect(weg.adresse.path == "/Audio/l1/stream.flac")
        #expect(werte(weg.adresse)["ApiKey"] == "tok")
        #expect(werte(weg.adresse)["playSessionId"] == nil)
        let hires = Lied(id: "l2", titel: "B", format: Tonformat(codec: "flac", behaelter: "flac", bitTiefe: 24, abtastrate: 192_000))
        let um = try #require(quelle.sonosweg(hires))
        #expect(um.art == .umgewandelt)
        #expect(um.adresse.path == "/Audio/l2/stream.mp3")
        #expect(werte(um.adresse)["ApiKey"] == "tok")

        var s = Warteschlange()
        s.setzen([cd], ab: 0, mischen: false)
        let spur = try #require(Sonosspur.aus(s.aktuell!, quelle: quelle))
        #expect(spur.adresse == weg.adresse.absoluteString)
        #expect(SonosDIDL.titel(spur.metadaten) == "A")
    }

    @Test("Subsonic: nur mit Token, nie mit Passwort in der Adresse")
    func subsonic() throws {
        func quelle(_ weise: SubsonicZugang.Weise) -> SubsonicQuelle {
            SubsonicQuelle(client: SubsonicClient(
                zugang: SubsonicZugang(server: URL(string: "https://musik.example.org")!, benutzer: "demo",
                                       passwort: "geheim", weise: weise),
                salz: "abc") { _ in throw URLError(.notConnectedToInternet) })
        }
        let lied = Lied(id: "s1", titel: "A", format: Tonformat(codec: "mp3", behaelter: "mp3"))
        let token = quelle(.token)
        let weg = try #require(token.sonosweg(lied))
        let w = werte(weg.adresse)
        #expect(w["t"] != nil)
        #expect(w["s"] == "abc")
        #expect(w["p"] == nil)
        #expect(w["format"] == "raw")
        #expect(!weg.adresse.absoluteString.contains("geheim"))
        let passwort = quelle(.passwort)
        #expect(!passwort.sonosMoeglich)
        #expect(passwort.sonosweg(lied) == nil)
    }
}

@Suite("Sonos: Warteschlange")
struct SonosWarteschlangeTests {

    private func schlange(_ n: Int, ab: Int = 0) -> Warteschlange {
        var s = Warteschlange()
        s.setzen((0 ..< n).map { Lied(id: "l\($0)", titel: "Lied \($0)", dauer: 180) }, ab: ab, mischen: false)
        return s
    }

    private func spur(_ e: Warteschlange.Eintrag) -> Sonosspur {
        let url = URL(string: "http://server.example/Audio/\(e.lied.id)/stream.flac?static=true&ApiKey=k")!
        return Sonosspur(eintrag: e.id, adresse: url.absoluteString,
                         metadaten: SonosDIDL.metadaten(e.lied, adresse: url, mime: "audio/flac", huelle: nil))
    }

    /// Was nach dem laufenden kommt, als Spuren — wie die App es schickt.
    private func kommende(_ s: Warteschlange) -> [Sonosspur] {
        let (e, ab) = Sonosfolge.fenster(s)
        return e.dropFirst(ab + 1).map(spur)
    }

    @Test("Fenster: höchstens 200 um das laufende, das laufende an seiner Stelle")
    func fenster() {
        let s = schlange(500, ab: 300)
        let (e, ab) = Sonosfolge.fenster(s)
        #expect(e.count == Sonosfolge.hoechstens)
        #expect(e[ab].id == s.aktuell?.id)
        #expect(ab == 20)
        let klein = schlange(3, ab: 2)
        #expect(Sonosfolge.fenster(klein).eintraege.count == 3)
        #expect(Sonosfolge.fenster(klein).ab == 2)
    }

    @Test("Angleichen: nichts, hinten anfügen oder hinter dem laufenden ersetzen")
    func angleich() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let s = Sonosschlange(folge: [a, b, c], adressen: ["a", "b", "c"], aktuell: 0, wiederholung: .aus)
        #expect(s.angleich([b, c]) == .nichts)
        #expect(s.angleich([b, c, d]) == .anfuegen(ab: 2))
        #expect(s.angleich([d, b, c]) == .ersetzen(ab: 2, anzahl: 2))
        #expect(s.angleich([]) == .ersetzen(ab: 2, anzahl: 2))
    }

    @Test("Befund aus der Nummer: gleich, weiter (auch zurück), fremd bei anderer Adresse oder Quelle")
    func befund() {
        let a = UUID(), b = UUID()
        let s = Sonosschlange(folge: [a, b], adressen: ["http://s/a", "http://s/b"], aktuell: 0, wiederholung: .aus)
        func lage(_ nummer: Int?, _ spur: String?, geladen: String? = "x-rincon-queue:RINCON_X#0") -> SonosLage {
            SonosLage(zustand: .spielt, spur: spur, geladen: geladen, naechstesGeladen: nil, stelle: 5, dauer: 180, nummer: nummer)
        }
        let b1 = Sonosfolge.befund(lage(1, "http://s/a"), schlange: s, koordinator: "RINCON_X")
        let b2 = Sonosfolge.befund(lage(2, "http://s/b"), schlange: s, koordinator: "RINCON_X")
        let b3 = Sonosfolge.befund(lage(2, "http://anders"), schlange: s, koordinator: "RINCON_X")
        let b4 = Sonosfolge.befund(lage(1, "x", geladen: "x-sonos-spotify:1"), schlange: s, koordinator: "RINCON_X")
        let b5 = Sonosfolge.befund(lage(9, "http://s/a"), schlange: s, koordinator: "RINCON_X")
        let b6 = Sonosfolge.befund(lage(nil, nil, geladen: nil), schlange: s, koordinator: "RINCON_X")
        #expect(b1.befund == .gleich && b1.index == 0)
        #expect(b2.befund == .weiter && b2.index == 1)
        #expect(b3.befund == .fremd)
        #expect(b4.befund == .fremd)
        #expect(b5.befund == .fremd)
        #expect(b6.befund == .leer)
    }

    @Test("Zurückholen: pausiert bei 1:23 bleibt pausiert bei 1:23; spielend spielt weiter, Sonos hält an")
    func zurueckholen() async throws {
        let haus = try await ScheinHaushalt(["Wohnzimmer"])
        let st = Sonossteuerung(koordinator: haus.lautsprecher("Wohnzimmer"))
        let s = schlange(3, ab: 1)
        let (e, ab) = Sonosfolge.fenster(s)
        try await st.uebernehmen(e.map(spur), ab: ab, stelle: 0, spielen: true, wiederholung: .aus)
        try await st.springen(83)
        try await st.pausieren()

        var r = try #require(try await st.zurueckgeben())
        #expect(r.eintrag == s.eintraege[1].id)
        #expect(r.stelle == 83)
        #expect(!r.lief)
        #expect(haus.zustand("Wohnzimmer").zustand == "PAUSED_PLAYBACK")

        // Spielend, über eine Stunde hinaus („1:02:05"): hier spielt es weiter, drüben steht es.
        try await st.springen(3725)
        try await st.abspielen()
        r = try #require(try await st.zurueckgeben())
        #expect(r.stelle == 3725)
        #expect(r.lief)
        #expect(haus.zustand("Wohnzimmer").zustand == "PAUSED_PLAYBACK")

        // Spielt dort etwas anderes: nichts von uns, und das Fremde läuft weiter.
        haus.fremdSpielen("Wohnzimmer")
        #expect(try await st.zurueckgeben() == nil)
        #expect(haus.zustand("Wohnzimmer").zustand == "PLAYING")
    }

    @Test("Der Koordinator geht: die Gruppe geht vorher über, Lied, Stelle und Warteschlange wandern mit")
    func koordinatorGeht() async throws {
        let haus = try await ScheinHaushalt(["Badezimmer", "Wohnzimmer"])
        let st = Sonossteuerung(koordinator: haus.lautsprecher("Badezimmer"))
        let s = schlange(4, ab: 2)
        let (e, ab) = Sonosfolge.fenster(s)
        try await st.uebernehmen(e.map(spur), ab: ab, stelle: 50, spielen: true, wiederholung: .alles)
        let wohn = SonosClient(basis: haus.lautsprecher("Wohnzimmer").basis)
        try await wohn.beitreten(haus.id("Badezimmer"))
        #expect(try await wohn.gruppen().map(\.name) == ["Badezimmer + 1"])

        let neu = try await st.koordinationUebergeben(an: haus.lautsprecher("Wohnzimmer"))
        #expect(Set(try await wohn.gruppen().map(\.name)) == ["Badezimmer", "Wohnzimmer"])
        let z = haus.zustand("Wohnzimmer")
        #expect(z.zustand == "PLAYING")
        #expect(z.nummer == ab + 1)
        #expect(z.modus == "REPEAT_ALL")
        #expect(haus.zustand("Badezimmer").zustand == "STOPPED")
        let a = try await neu.abfragen()
        #expect(a.befund == .gleich)
        #expect(a.eintrag == s.eintraege[2].id)
        #expect(a.lage.stelle == 50)

        // Der gegangene meldet `Track` 1 ohne Lied: das ist kein „weiter".
        let alt = try await st.abfragen()
        #expect(alt.befund != .weiter)
        #expect(alt.eintrag == nil)
    }

    @Test("Er spielt ohne das Telefon die ganze Schlange durch; danach stimmen Lied und Stelle")
    func durchspielen() async throws {
        let haus = try await ScheinHaushalt(["Wohnzimmer"])
        let st = Sonossteuerung(koordinator: haus.lautsprecher("Wohnzimmer"))
        let s = schlange(4, ab: 1)
        let (e, ab) = Sonosfolge.fenster(s)
        try await st.uebernehmen(e.map(spur), ab: ab, stelle: 30, spielen: true, wiederholung: .aus)
        #expect(await st.mitWarteschlange)
        var z = haus.zustand("Wohnzimmer")
        #expect(z.warteschlange.count == 4)
        #expect(z.warteschlange.map { SonosDIDL.titel($0.metadaten) } == ["Lied 0", "Lied 1", "Lied 2", "Lied 3"])
        #expect(z.adresse == "x-rincon-queue:\(haus.id("Wohnzimmer"))#0")
        #expect(z.nummer == 2)
        #expect(z.stelle == 30)
        #expect(z.zustand == "PLAYING")

        // Das Telefon schläft: kein Befehl, er spielt weiter.
        let befehle = haus.aktionen.count
        haus.liedZuEnde("Wohnzimmer")
        haus.liedZuEnde("Wohnzimmer")
        haus.weiterlaufen("Wohnzimmer", sekunden: 42)
        #expect(haus.aktionen.count == befehle)
        z = haus.zustand("Wohnzimmer")
        #expect(z.nummer == 4)
        #expect(z.zustand == "PLAYING")

        // Zurück in der App: die Abfrage liest Lied und Stelle zurück.
        let a = try await st.abfragen()
        #expect(a.befund == .weiter)
        #expect(a.eintrag == s.eintraege[3].id)
        #expect(a.lage.stelle == 42)
        #expect(a.lage.laeuft)
        var folge = s
        folge.springe(zu: a.eintrag!)
        let sitzung = Sonosfolge.sitzung(id: "sonos:W", name: "Wohnzimmer", schlange: folge, lage: a.lage,
                                         unser: true, abgefragt: Date())
        let stand = Fernstand(sitzung)
        #expect(stand.lied?.id == "l3")
        #expect(stand.rueckholung()?.ab == 3)
        #expect(abs((stand.rueckholung()?.stelle ?? 0) - 42) < 1)

        // Am Ende hält er an.
        haus.liedZuEnde("Wohnzimmer")
        #expect(haus.zustand("Wohnzimmer").zustand == "STOPPED")
    }

    @Test("Änderungen hier: Als Nächstes ersetzt hinter dem laufenden, Hinten an fügt nur an; das laufende spielt weiter")
    func nachziehen() async throws {
        let haus = try await ScheinHaushalt(["Küche"])
        let st = Sonossteuerung(koordinator: haus.lautsprecher("Küche"))
        var s = schlange(3)
        let (e, ab) = Sonosfolge.fenster(s)
        try await st.uebernehmen(e.map(spur), ab: ab, stelle: 0, spielen: true, wiederholung: .aus)
        haus.weiterlaufen("Küche", sekunden: 50)

        s.alsNaechstes([Lied(id: "neu", titel: "Neu", dauer: 100)])
        try await st.nachziehen(aktuell: s.aktuell!.id, kommende: kommende(s), naechste: nil, wiederholung: .aus)
        var z = haus.zustand("Küche")
        #expect(z.warteschlange.map { SonosDIDL.titel($0.metadaten) } == ["Lied 0", "Neu", "Lied 1", "Lied 2"])
        #expect(z.nummer == 1)
        #expect(z.stelle == 50)
        #expect(z.zustand == "PLAYING")

        let vorher = haus.aktionen.count
        s.hintenAn([Lied(id: "ende", titel: "Ende", dauer: 100)])
        try await st.nachziehen(aktuell: s.aktuell!.id, kommende: kommende(s), naechste: nil, wiederholung: .aus)
        let neu = haus.aktionen.dropFirst(vorher)
        #expect(!neu.contains("RemoveTrackRangeFromQueue"))
        #expect(haus.zustand("Küche").warteschlange.count == 5)

        // Wiederholen macht Sonos selbst: ein Lied bleibt ein Lied.
        s.wiederholen(.eines)
        try await st.nachziehen(aktuell: s.aktuell!.id, kommende: kommende(s), naechste: nil, wiederholung: .eines)
        #expect(haus.zustand("Küche").modus == "REPEAT_ONE")
        haus.liedZuEnde("Küche")
        #expect(haus.zustand("Küche").nummer == 1)

        // Ein Lied der Schlange wählen: nur springen.
        let dritter = s.eintraege[2].id
        let gesprungen = try await st.springen(zu: dritter, stelle: 0, spielen: true)
        #expect(gesprungen)
        z = haus.zustand("Küche")
        #expect(z.nummer == 3)
        #expect(SonosDIDL.titel(z.spurMetadaten) == "Lied 1")
        let fehlt = try await st.springen(zu: UUID(), stelle: 0, spielen: true)
        #expect(!fehlt)
    }

    @Test("Rückfall: ohne Warteschlange das laufende und das nächste einzeln")
    func rueckfall() async throws {
        let haus = try await ScheinHaushalt(["Bad"])
        haus.ohneWarteschlange = true
        let st = Sonossteuerung(koordinator: haus.lautsprecher("Bad"))
        let s = schlange(3)
        let (e, ab) = Sonosfolge.fenster(s)
        try await st.uebernehmen(e.map(spur), ab: ab, stelle: 0, spielen: true, wiederholung: .aus)
        #expect(!(await st.mitWarteschlange))
        let z = haus.zustand("Bad")
        #expect(z.adresse.contains("/Audio/l0/"))
        #expect(z.naechste.contains("/Audio/l1/"))
        #expect(z.zustand == "PLAYING")
    }

    @Test("Mit Warteschlange: etwas anderes gestartet heißt fremd")
    func fremd() async throws {
        let haus = try await ScheinHaushalt(["Flur"])
        let st = Sonossteuerung(koordinator: haus.lautsprecher("Flur"))
        let s = schlange(2)
        try await st.uebernehmen(Sonosfolge.fenster(s).eintraege.map(spur), ab: 0, stelle: 0, spielen: true,
                                 wiederholung: .aus)
        haus.fremdSpielen("Flur")
        let befund = try await st.abfragen().befund
        #expect(befund == .fremd)
    }
}
