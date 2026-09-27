import Foundation
import JellyfinKit
import SubsonicKit
import Testing
@testable import MusikKit

/// **Connect**: was aus dem Steuerkanal kommt, was wir anderen Geräten
/// schicken, welche Geräte in der Liste stehen, und wie der Stand eines
/// anderen Geräts gezeigt wird.
@Suite("Connect")
struct ConnectTests {

    // MARK: Steuerkanal lesen

    @Test("Play: Kennungen, Anfang, Stelle, Art")
    func play() {
        let text = #"{"MessageType":"Play","Data":{"ItemIds":["a","b","c"],"StartIndex":1,"StartPositionTicks":300000000,"PlayCommand":"PlayNow","ControllingUserId":"u1"}}"#
        #expect(Kanalnachricht.lesen(text) == .auftrag(.spielen(ids: ["a", "b", "c"], ab: 1, stelle: 30, wie: .jetzt)))
    }

    @Test("Play: PlayNext, PlayLast, PlayShuffle, und der Befehl als Zahl")
    func playArten() {
        func art(_ befehl: String) -> Fernauftrag.Einreihung? {
            let t = #"{"MessageType":"Play","Data":{"ItemIds":["a"],"PlayCommand":"# + befehl + "}}"
            if case let .auftrag(.spielen(_, _, _, wie)) = Kanalnachricht.lesen(t) { return wie }
            return nil
        }
        #expect(art(#""PlayNext""#) == .alsNaechstes)
        #expect(art(#""PlayLast""#) == .hintenAn)
        #expect(art(#""PlayShuffle""#) == .gemischt)
        #expect(art(#""PlayInstantMix""#) == .mix)
        #expect(art("2") == .hintenAn)
        #expect(art("4") == .gemischt)
    }

    @Test("Play ohne Kennungen ist kein Befehl, ein Anfang außerhalb wird geklemmt")
    func playRand() {
        #expect(Kanalnachricht.lesen(#"{"MessageType":"Play","Data":{"ItemIds":[]}}"#) == .sonstiges("Play"))
        let t = #"{"MessageType":"Play","Data":{"ItemIds":["a","b"],"StartIndex":9}}"#
        #expect(Kanalnachricht.lesen(t) == .auftrag(.spielen(ids: ["a", "b"], ab: 1, stelle: nil, wie: .jetzt)))
    }

    @Test("Playstate: jeder Befehl, Springen in Sekunden")
    func playstate() {
        func auftrag(_ befehl: String, _ extra: String = "") -> Kanalnachricht? {
            Kanalnachricht.lesen(#"{"MessageType":"Playstate","Data":{"Command":""# + befehl + "\"" + extra + "}}")
        }
        #expect(auftrag("Pause") == .auftrag(.pause))
        #expect(auftrag("Unpause") == .auftrag(.weiter))
        #expect(auftrag("PlayPause") == .auftrag(.umschalten))
        #expect(auftrag("Stop") == .auftrag(.stopp))
        #expect(auftrag("NextTrack") == .auftrag(.naechstes))
        #expect(auftrag("PreviousTrack") == .auftrag(.voriges))
        #expect(auftrag("FastForward") == .auftrag(.vor))
        #expect(auftrag("Rewind") == .auftrag(.zurueck))
        #expect(auftrag("Seek", #","SeekPositionTicks":1250000000"#) == .auftrag(.springen(125)))
        #expect(auftrag("Seek") == .sonstiges("Playstate"))
        #expect(auftrag("Tanzen") == .sonstiges("Playstate"))
    }

    @Test("GeneralCommand: Lautstärke als Text, Wiederholen, Mischen, Stumm")
    func allgemein() {
        func auftrag(_ name: String, _ werte: String = "{}") -> Kanalnachricht? {
            Kanalnachricht.lesen(#"{"MessageType":"GeneralCommand","Data":{"Name":""# + name + #"","Arguments":"# + werte + "}}")
        }
        #expect(auftrag("SetVolume", #"{"Volume":"40"}"#) == .auftrag(.lautstaerke(40)))
        #expect(auftrag("SetVolume", #"{"Volume":"140"}"#) == .auftrag(.lautstaerke(100)))
        #expect(auftrag("SetRepeatMode", #"{"RepeatMode":"RepeatOne"}"#) == .auftrag(.wiederholung(.eines)))
        #expect(auftrag("SetRepeatMode", #"{"RepeatMode":"RepeatNone"}"#) == .auftrag(.wiederholung(.aus)))
        #expect(auftrag("SetShuffleQueue", #"{"ShuffleMode":"Shuffle"}"#) == .auftrag(.mischen(true)))
        #expect(auftrag("SetShuffleQueue", #"{"ShuffleMode":"Sorted"}"#) == .auftrag(.mischen(false)))
        #expect(auftrag("ToggleMute") == .auftrag(.stumm(nil)))
        #expect(auftrag("DisplayMessage") == .sonstiges("GeneralCommand"))
    }

    @Test("Lebenszeichen, Fremdes und Unsinn")
    func sonstiges() {
        #expect(Kanalnachricht.lesen(#"{"MessageType":"ForceKeepAlive","Data":60}"#) == .lebenszeichenVerlangt)
        #expect(Kanalnachricht.lesen(#"{"MessageType":"UserDataChanged","Data":{}}"#) == .sonstiges("UserDataChanged"))
        #expect(Kanalnachricht.lesen("kein json") == nil)
    }

    @Test("Gemeldete Fähigkeiten: nur Audio, jeder Befehl ein GeneralCommandType")
    func faehigkeiten() throws {
        let roh = try #require(try JSONSerialization.jsonObject(with: Musikfaehigkeiten.rumpf()) as? [String: Any])
        #expect(roh["PlayableMediaTypes"] as? [String] == ["Audio"])
        #expect(roh["SupportsMediaControl"] as? Bool == true)
        // Abgeglichen mit Jellyfins `GeneralCommandType`; ein falscher Name
        // lässt den Server die ganze Meldung verwerfen.
        let bekannt: Set = ["Play", "PlayState", "PlayNext", "SetVolume", "Mute", "Unmute", "ToggleMute",
                            "SetRepeatMode", "SetShuffleQueue", "PlayMediaSource", "DisplayMessage"]
        for b in try #require(roh["SupportedCommands"] as? [String]) { #expect(bekannt.contains(b), "\(b)") }
    }

    @Test("Wartezeit nach Abrissen: 2, 4, 8, 16, dann 30")
    func wartezeit() {
        #expect((1 ... 7).map(Kanalregel.wartezeit(nachAbrissen:)) == [2, 4, 8, 16, 30, 30, 30])
    }

    // MARK: Befehle an andere Geräte

    @Test("Wiedergabebefehle gehen auf Playing/{Befehl}")
    func befehle() {
        #expect(Fernbedienung.anfrage(.pause, an: "s").pfad == "Sessions/s/Playing/Pause")
        #expect(Fernbedienung.anfrage(.weiter, an: "s").pfad == "Sessions/s/Playing/Unpause")
        #expect(Fernbedienung.anfrage(.umschalten, an: "s").pfad == "Sessions/s/Playing/PlayPause")
        #expect(Fernbedienung.anfrage(.naechstes, an: "s").pfad == "Sessions/s/Playing/NextTrack")
        #expect(Fernbedienung.anfrage(.voriges, an: "s").pfad == "Sessions/s/Playing/PreviousTrack")
        #expect(Fernbedienung.anfrage(.stopp, an: "s").pfad == "Sessions/s/Playing/Stop")
        let seek = Fernbedienung.anfrage(.springen(61.5), an: "s")
        #expect(seek.pfad == "Sessions/s/Playing/Seek")
        #expect(seek.abfrage == [URLQueryItem(name: "seekPositionTicks", value: "615000000")])
    }

    @Test("Wiederholen und Mischen als GeneralCommand im Rumpf")
    func allgemeinHinaus() throws {
        let a = Fernbedienung.anfrage(.wiederholung(.alles), an: "s")
        #expect(a.pfad == "Sessions/s/Command")
        let rumpf = try #require(a.rumpf)
        let roh = try #require(try JSONSerialization.jsonObject(with: rumpf) as? [String: Any])
        #expect(roh["Name"] as? String == "SetRepeatMode")
        #expect((roh["Arguments"] as? [String: String])?["RepeatMode"] == "RepeatAll")
        let m = Fernbedienung.anfrage(.mischen(false), an: "s")
        let mrumpf = try #require(m.rumpf)
        let mroh = try #require(try JSONSerialization.jsonObject(with: mrumpf) as? [String: Any])
        #expect((mroh["Arguments"] as? [String: String])?["ShuffleMode"] == "Sorted")
    }

    @Test("Übergeben: Schlange, Anfang und Stelle in der Adresse")
    func uebergeben() {
        let a = Fernbedienung.anfrage(.spielen(ids: ["a", "b", "c"], ab: 2, stelle: 12), an: "s")
        #expect(a.pfad == "Sessions/s/Playing")
        #expect(a.abfrage == [.init(name: "playCommand", value: "PlayNow"),
                              .init(name: "itemIds", value: "a,b,c"),
                              .init(name: "startIndex", value: "2"),
                              .init(name: "startPositionTicks", value: "120000000")])
        let ohne = Fernbedienung.anfrage(.spielen(ids: ["a"], ab: 0, stelle: 0), an: "s")
        #expect(!ohne.abfrage.contains { $0.name == "startPositionTicks" })
        #expect(Fernbedienung.anfrage(.alsNaechstes(["x"]), an: "s").abfrage.first?.value == "PlayNext")
        #expect(Fernbedienung.anfrage(.hintenAn(["x"]), an: "s").abfrage.first?.value == "PlayLast")
    }

    @Test("Fenster: kurze Schlangen ganz, lange um das laufende Lied")
    func fenster() {
        let kurz = ["a", "b", "c"]
        #expect(Uebergabe.fenster(kurz, ab: 1).ids == kurz)
        #expect(Uebergabe.fenster(kurz, ab: 7).ab == 2)
        #expect(Uebergabe.fenster([], ab: 0).ids.isEmpty)
        let lang = (0 ..< 500).map(String.init)
        let mitte = Uebergabe.fenster(lang, ab: 250)
        #expect(mitte.ids.count == 200)
        #expect(mitte.ids[mitte.ab] == "250")
        #expect(mitte.ab == 20)                       // 20 Lieder Rückblick
        let ende = Uebergabe.fenster(lang, ab: 490)
        #expect(ende.ids.last == "499")
        #expect(ende.ids[ende.ab] == "490")
        let anfang = Uebergabe.fenster(lang, ab: 3)
        #expect(anfang.ids.first == "0")
        #expect(anfang.ab == 3)
    }

    @Test("Übergeben oder steuern")
    func art() {
        #expect(Uebergabe.art(hierSpielt: true, hierIstSchlange: true, dortSpielt: true) == .uebergeben)
        #expect(Uebergabe.art(hierSpielt: false, hierIstSchlange: true, dortSpielt: true) == .steuern)
        #expect(Uebergabe.art(hierSpielt: false, hierIstSchlange: true, dortSpielt: false) == .uebergeben)
        #expect(Uebergabe.art(hierSpielt: false, hierIstSchlange: false, dortSpielt: false) == .steuern)
    }

    @Test("Fehlt ein Lied, rückt der Anfang mit")
    func indexOhneLuecke() {
        let ids = ["a", "b", "c", "d"]
        let gefunden = [Lied(id: "a", titel: "A"), Lied(id: "c", titel: "C"), Lied(id: "d", titel: "D")]
        #expect(Uebergabe.index(von: 2, in: ids, gefunden: gefunden) == 1)   // c
        #expect(Uebergabe.index(von: 1, in: ids, gefunden: gefunden) == 1)   // b fehlt → c
        #expect(Uebergabe.index(von: 3, in: ids, gefunden: gefunden) == 2)
        #expect(Uebergabe.index(von: 0, in: ids, gefunden: []) == 0)
    }

    // MARK: Geräte

    private func sitzungen() throws -> [Musiksitzung] {
        let roh = try JSONDecoder().decode([Vielleicht<JSitzung>].self, from: fixture("jf_sessions"))
        return roh.compactMap(\.wert).map { $0.musiksitzung { e in Lied(id: e.id, titel: e.name) } }
    }

    @Test("Sitzung lesen: Lied, Stand, Schlange, Schalter")
    func lesenSitzung() throws {
        let alle = try sitzungen()
        #expect(alle.count == 5)                    // der Eintrag ohne Text-Kennung fällt heraus
        let web = try #require(alle.first { $0.id == "s-web" })
        #expect(web.lied?.id == "l2")
        #expect(web.stelle == 73.5)
        #expect(web.spielt)
        #expect(web.wiederholung == .alles)
        #expect(web.gemischt)
        #expect(web.lautstaerke == 80)
        #expect(web.schlange == ["l1", "l2", "l3"])
        #expect(web.index == 1)
        #expect(web.befehle.contains("Play"))
        #expect(web.letzteMeldung != nil)
        let tv = try #require(alle.first { $0.id == "s-tv" })
        #expect(tv.lied == nil)
        #expect(tv.laeuftAnderes)
        #expect(tv.geraeteart == .fernseher)
    }

    @Test("Geräteliste: nicht wir, nicht fremde Konten, nur was Befehle nimmt; was spielt zuerst")
    func liste() throws {
        let liste = Geraeteliste.auswahl(try sitzungen(), eigeneGeraeteID: "ich", eigeneBenutzerID: "u1")
        #expect(liste.map(\.id) == ["s-web", "s-tv"])
    }

    @Test("Läuft woanders: das eigene Gerät, das spielt und sich gemeldet hat")
    func woanders() throws {
        let jetzt = try #require(Zeitangabe.lesen("2026-09-24T10:00:30Z"))
        let alle = try sitzungen()
        let treffer = Geraeteliste.laeuftWoanders(alle, eigeneGeraeteID: "ich", eigeneBenutzerID: "u1", jetzt: jetzt)
        #expect(treffer?.id == "s-web")
        let spaeter = jetzt.addingTimeInterval(600)
        #expect(Geraeteliste.laeuftWoanders(alle, eigeneGeraeteID: "ich", eigeneBenutzerID: "u1", jetzt: spaeter) == nil)
        // Vom Gerät selbst aus gesehen läuft nichts woanders.
        #expect(Geraeteliste.laeuftWoanders(alle, eigeneGeraeteID: "web-1", eigeneBenutzerID: "u1", jetzt: jetzt) == nil)
    }

    // MARK: Stand eines anderen Geräts

    private func web(stelle: TimeInterval = 73.5, angehalten: Bool = false, lied: String = "l2",
                     meldung: Date? = nil, index: String = "playlistItem1") -> Musiksitzung {
        Musiksitzung(id: "s-web", benutzerID: "u1", geraeteID: "web-1", geraetename: "Firefox",
                     programm: "Jellyfin Web", lied: Lied(id: lied, titel: lied, dauer: 200),
                     angehalten: angehalten, stelle: stelle, schlange: ["l1", "l2", "l3"],
                     schlangeneintraege: ["playlistItem0", "playlistItem1", "playlistItem2"],
                     eintragID: index, letzteMeldung: meldung)
    }

    @Test("Die Stelle gilt zur Abfrage, weiter läuft sie ab da, nie über das Ende")
    func weiterrechnen() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        // Der Server hat die zwei Sekunden seit der Meldung schon gezählt;
        // nur der Bruchteil der angefangenen fehlt ihm.
        let stand = Fernstand(web(meldung: t0.addingTimeInterval(-2.4)), jetzt: t0)
        #expect(abs(stand.stelle(jetzt: t0) - 73.9) < 0.001)
        #expect(abs(stand.stelle(jetzt: t0.addingTimeInterval(10)) - 83.9) < 0.001)
        #expect(stand.stelle(jetzt: t0.addingTimeInterval(59)) <= 200)
        let halt = Fernstand(web(angehalten: true, meldung: t0.addingTimeInterval(-5)), jetzt: t0)
        #expect(halt.stelle(jetzt: t0.addingTimeInterval(30)) == 73.5)
    }

    @Test("Läuft nur mit Lied, nicht angehalten")
    func laeuft() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        #expect(Fernstand(web(), jetzt: t0).laeuft)
        #expect(!Fernstand(web(angehalten: true), jetzt: t0).laeuft)
    }

    @Test("Ohne Meldezeit: dieselbe Stelle heißt nichts Neues, die Rechnung läuft weiter")
    func ohneMeldezeit() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var stand = Fernstand(web(), jetzt: t0)
        #expect(stand.abgleichen([web()], jetzt: t0.addingTimeInterval(5)) == .gleich)
        #expect(abs(stand.stelle(jetzt: t0.addingTimeInterval(5)) - 78.5) < 0.001)
        _ = stand.abgleichen([web(stelle: 90)], jetzt: t0.addingTimeInterval(6))
        #expect(stand.stelle(jetzt: t0.addingTimeInterval(6)) == 90)
    }

    @Test("Ein eigener Befehl gilt sofort und schlägt jede Abfrage, die ihn nicht kennen kann")
    func vorrang() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var stand = Fernstand(web(), jetzt: t0)
        let nummer = stand.vormerken(.pause, jetzt: t0)
        #expect(stand.angehalten)
        _ = stand.abgleichen([web()], jetzt: t0.addingTimeInterval(1))
        #expect(stand.angehalten)                   // noch nicht beim Server
        stand.erledigt(nummer, jetzt: t0.addingTimeInterval(1.2))
        _ = stand.abgleichen([web()], jetzt: t0.addingTimeInterval(2))
        #expect(stand.angehalten)                   // angekommen, aber das Gerät braucht noch
        let marke = stand.marke(jetzt: t0.addingTimeInterval(1.2 + Fernstand.nachlauf + 0.1))
        _ = stand.abgleichen([web()], marke: marke, jetzt: t0.addingTimeInterval(4))
        #expect(!stand.angehalten)                  // danach gilt wieder, was das Gerät sagt
        stand.vormerken(.springen(500), jetzt: t0)
        #expect(stand.stelle(jetzt: t0) == 200)     // nie hinter das Ende
    }

    @Test("Eine Abfrage, die vor dem letzten Tipp begann, überschreibt ihn nicht")
    func folgenummer() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var stand = Fernstand(web(), jetzt: t0)
        // Pause, erledigt, Nachlauf vorbei — dann beginnt eine Abfrage …
        let eins = stand.vormerken(.pause, jetzt: t0)
        stand.erledigt(eins, jetzt: t0)
        let marke = stand.marke(jetzt: t0.addingTimeInterval(3))
        // … und während sie läuft, kommt Abspielen.
        _ = stand.vormerken(.weiter, jetzt: t0.addingTimeInterval(3.1))
        _ = stand.abgleichen([web(angehalten: true)], marke: marke, jetzt: t0.addingTimeInterval(3.3))
        #expect(!stand.angehalten)
    }

    @Test("Ein Befehl ohne Antwort zählt höchstens die Vorrangfrist")
    func vorrangfrist() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var stand = Fernstand(web(), jetzt: t0)
        stand.vormerken(.pause, jetzt: t0)
        _ = stand.abgleichen([web()], jetzt: t0.addingTimeInterval(Fernstand.vorrang - 1))
        #expect(stand.angehalten)
        _ = stand.abgleichen([web()], jetzt: t0.addingTimeInterval(Fernstand.vorrang + 1))
        #expect(!stand.angehalten)
    }

    @Test("Meldet das Gerät kurz kein Lied, bleibt das letzte stehen, angehalten")
    func keinLied() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var stand = Fernstand(web(), jetzt: t0)
        let leer = Musiksitzung(id: "s-web", benutzerID: "u1", geraeteID: "web-1", geraetename: "Firefox",
                                programm: "Jellyfin Web")
        _ = stand.abgleichen([leer], jetzt: t0.addingTimeInterval(2))
        #expect(stand.lied?.id == "l2")
        #expect(stand.angehalten)
        #expect(stand.gestoppt)
        #expect(stand.rueckholung(jetzt: t0.addingTimeInterval(2))?.ab == 1)
        // Abspielen fängt dann drüben die Schlange neu an, an der Stelle.
        guard case let .spielen(ids, ab, _)? = stand.aufloesen(.umschalten) else {
            Issue.record("kein Neuanfang"); return
        }
        #expect(ids == ["l1", "l2", "l3"])
        #expect(ab == 1)
        _ = stand.abgleichen([web()], jetzt: t0.addingTimeInterval(9))
        #expect(!stand.gestoppt)
    }

    @Test("Umschalten wird zu Pause oder Weiter, nach dem gezeigten Stand")
    func umschalten() {
        var stand = Fernstand(web())
        #expect(stand.aufloesen(.umschalten) == .pause)
        stand.vormerken(.pause)
        #expect(stand.aufloesen(.umschalten) == .weiter)
        #expect(stand.aufloesen(.weiter) == .weiter)
        #expect(stand.aufloesen(.naechstes) == .naechstes)
    }

    @Test("Befehle der Reihe nach: einer unterwegs, Gleiches wird ersetzt")
    func befehlsfolge() {
        var folge = Fernbefehlsfolge()
        folge.einreihen(.pause, nummer: 1)
        #expect(folge.naechster()?.aktion == .pause)
        #expect(folge.naechster() == nil)              // einer ist unterwegs
        folge.einreihen(.weiter, nummer: 2)
        folge.einreihen(.naechstes, nummer: 3)
        folge.einreihen(.pause, nummer: 4)             // wie unterwegs: nichts Neues
        #expect(folge.wartend.map(\.aktion) == [.naechstes])
        #expect(folge.fertig()?.nummer == 4)           // erledigt auch die 4
        folge.einreihen(.weiter, nummer: 5)
        folge.einreihen(.springen(10), nummer: 6)
        folge.einreihen(.springen(20), nummer: 7)
        #expect(folge.naechster()?.aktion == .naechstes)
        folge.fertig()
        #expect(folge.naechster()?.aktion == .weiter)
        folge.fertig()
        #expect(folge.naechster() == Fernbefehlsfolge.Befehl(nummer: 7, aktion: .springen(20)))
        folge.fertig()
        #expect(folge.leer)
    }

    @Test("Gerätenamen: verbogenes UTF-8 und Prozentzeichen werden zurückgelesen")
    func geraetename() {
        #expect(Geraetename.lesbar("Anna\u{E2}\u{80}\u{99}s MacBook") == "Anna\u{2019}s MacBook")
        #expect(Geraetename.lesbar("Annaâ€™s MacBook") == "Anna\u{2019}s MacBook")
        #expect(Geraetename.lesbar("Anna%E2%80%99s%20MacBook") == "Anna\u{2019}s MacBook")
        #expect(Geraetename.lesbar("Anna%27s MacBook") == "Anna's MacBook")
        #expect(Geraetename.lesbar("Anna's MacBook") == "Anna's MacBook")
        // Wörtliche Prozentzeichen bleiben stehen: ein Name mit Leerzeichen
        // und „%20" daneben ist nicht kodiert, und kaputtes UTF-8 auch nicht.
        #expect(Geraetename.lesbar("R%20D Lab") == "R%20D Lab")
        #expect(Geraetename.lesbar("Wohnzimmer%20TV") == "Wohnzimmer TV")
        #expect(Geraetename.lesbar("100%FF Ton") == "100%FF Ton")
        #expect(Geraetename.lesbar("Anna\u{2019}s MacBook") == "Anna\u{2019}s MacBook")
        #expect(Geraetename.lesbar("Café Küche") == "Café Küche")
        #expect(Geraetename.lesbar("100% Wohnzimmer") == "100% Wohnzimmer")
        #expect(Geraetename.lesbar("") == "")
    }

    @Test("Gerätename aus /Sessions geht durch die Reparatur")
    func geraetenameGelesen() throws {
        let text = #"[{"Id":"s1","UserId":"u1","DeviceId":"d1","DeviceName":"Anna\u00e2\u0080\u0099s MacBook","Client":"Jellyfin Media Player","SupportsRemoteControl":true,"PlayableMediaTypes":["Audio"]}]"#
        let roh = try JSONDecoder().decode([JSitzung].self, from: Data(text.utf8))
        let s = try #require(roh.first).musiksitzung { Lied(id: $0.id, titel: "") }
        #expect(s.geraetename == "Anna\u{2019}s MacBook")
    }

    @Test("Nach dem Übergeben zählt die alte Antwort des Geräts nicht")
    func erwartung() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var stand = Fernstand(web(stelle: 10, lied: "l3", index: "playlistItem2"), jetzt: t0)
        stand.erwarten("l3", jetzt: t0)
        #expect(stand.abgleichen([web()], jetzt: t0.addingTimeInterval(1)) == .gleich)
        #expect(stand.lied?.id == "l3")
        #expect(stand.abgleichen([web(stelle: 11, lied: "l3", index: "playlistItem2")],
                                 jetzt: t0.addingTimeInterval(2)) != .schlange)
        // Meldet es nach der Frist noch das alte, gilt das alte.
        var spaet = Fernstand(web(lied: "l3", index: "playlistItem2"), jetzt: t0)
        spaet.erwarten("l3", jetzt: t0)
        _ = spaet.abgleichen([web()], jetzt: t0.addingTimeInterval(Fernstand.uebergabefrist + 1))
        #expect(spaet.lied?.id == "l2")
    }

    @Test("Weg erst nach drei fehlenden Abfragen")
    func weg() {
        var stand = Fernstand(web())
        #expect(stand.abgleichen([]) == .gleich)
        #expect(stand.abgleichen([]) == .gleich)
        #expect(stand.abgleichen([]) == .weg)
        var zweiter = Fernstand(web())
        _ = zweiter.abgleichen([])
        _ = zweiter.abgleichen([web()])             // ein Aussetzer zählt nicht weiter
        _ = zweiter.abgleichen([])
        #expect(zweiter.abgleichen([]) == .gleich)
    }

    @Test("Zurückholen: Schlange, Stelle darin, weitergerechnete Stelle")
    func rueckholung() throws {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let stand = Fernstand(web(meldung: t0), jetzt: t0)
        let r = try #require(stand.rueckholung(jetzt: t0.addingTimeInterval(4)))
        #expect(r.ids == ["l1", "l2", "l3"])
        #expect(r.ab == 1)
        #expect(abs(r.stelle - 77.5) < 0.001)
        let leer = Fernstand(Musiksitzung(id: "x", benutzerID: "u1", geraeteID: "d", geraetename: "TV", programm: nil))
        #expect(leer.rueckholung() == nil)
    }

    @Test("Spiegeln behält die Einträge, solange die Lieder dieselben sind")
    func spiegeln() {
        let lieder = ["a", "b", "c"].map { Lied(id: $0, titel: $0) }
        var s = Warteschlange()
        s.spiegeln(lieder, aktuell: 0, gemischt: true, wiederholung: .alles)
        let vorher = s.eintraege.map(\.id)
        #expect(s.aktuell?.lied.id == "a")
        #expect(s.gemischt)
        #expect(s.wiederholung == .alles)
        s.spiegeln(lieder, aktuell: 2, gemischt: false, wiederholung: .aus)
        #expect(s.eintraege.map(\.id) == vorher)
        #expect(s.aktuell?.lied.id == "c")
        s.spiegeln(Array(lieder.prefix(2)), aktuell: 1, gemischt: false, wiederholung: .aus)
        #expect(s.eintraege.map(\.id) != Array(vorher.prefix(2)))
        s.spiegeln([], aktuell: 0, gemischt: false, wiederholung: .aus)
        #expect(s.aktuell == nil)
    }

    // MARK: Subsonic

    private func server(von: String? = "Feishin", zeit: Date?, lied: String = "b",
                        stelle: TimeInterval = 40) -> Gespeicherteschlange {
        Gespeicherteschlange(lieder: [Lied(id: "a", titel: "A"), Lied(id: lied, titel: "B")], aktuell: 1,
                             stelle: stelle, geaendert: zeit, von: von)
    }

    @Test("Schlange des Servers: nur, was nach der eigenen Sicherung kam")
    func neuerAls() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        #expect(Schlangenvergleich.lohntAngebot(server(zeit: t0.addingTimeInterval(60)), eigeneSicherung: t0,
                                                hier: nil, hierSpielt: false))
        // Die eigene Sicherung, wiedergelesen: kein Angebot — auch nicht bei etwas Uhrversatz.
        #expect(!Schlangenvergleich.lohntAngebot(server(von: "Swiftly Music", zeit: t0.addingTimeInterval(4)),
                                                 eigeneSicherung: t0, hier: nil, hierSpielt: false))
        // Ein zweites iPhone mit Swiftly Music heißt genauso — die Zeit entscheidet.
        #expect(Schlangenvergleich.lohntAngebot(server(von: "Swiftly Music", zeit: t0.addingTimeInterval(300)),
                                                eigeneSicherung: t0, hier: nil, hierSpielt: false))
        // Nie selbst gesichert: alles ist neuer.
        #expect(Schlangenvergleich.lohntAngebot(server(zeit: t0), eigeneSicherung: nil, hier: nil, hierSpielt: false))
    }

    @Test("Kein Angebot, wenn hier etwas läuft oder dasselbe bereitsteht")
    func keinAngebot() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let neu = server(zeit: t0.addingTimeInterval(60))
        #expect(!Schlangenvergleich.lohntAngebot(neu, eigeneSicherung: t0, hier: nil, hierSpielt: true))
        #expect(!Schlangenvergleich.lohntAngebot(neu, eigeneSicherung: t0, hier: ("b", 45), hierSpielt: false))
        #expect(Schlangenvergleich.lohntAngebot(neu, eigeneSicherung: t0, hier: ("b", 120), hierSpielt: false))
        #expect(!Schlangenvergleich.lohntAngebot(server(zeit: nil), eigeneSicherung: t0, hier: nil, hierSpielt: false))
    }
}
