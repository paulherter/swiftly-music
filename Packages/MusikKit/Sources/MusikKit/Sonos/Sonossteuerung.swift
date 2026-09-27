import Foundation

/// **Ein Lied, fertig für den Lautsprecher**: der Eintrag in unserer
/// Schlange, die Adresse beim Server und die Metadaten dazu.
public struct Sonosspur: Sendable, Equatable {
    public let eintrag: UUID
    public let adresse: String
    public let metadaten: String

    public init(eintrag: UUID, adresse: String, metadaten: String) {
        self.eintrag = eintrag
        self.adresse = adresse
        self.metadaten = metadaten
    }

    /// Aus einem Eintrag und der Quelle — `nil`, wenn die Quelle keine
    /// Adresse für Sonos hat (``Musikquelle/sonosweg(_:)``).
    public static func aus(_ eintrag: Warteschlange.Eintrag, quelle: any Musikquelle) -> Sonosspur? {
        guard let weg = quelle.sonosweg(eintrag.lied) else { return nil }
        let huelle = eintrag.lied.bild.flatMap { quelle.bildadresse($0, kante: 600) }
        return Sonosspur(eintrag: eintrag.id, adresse: weg.adresse.absoluteString,
                         metadaten: SonosDIDL.metadaten(eintrag.lied, adresse: weg.adresse,
                                                        mime: weg.umwandlung == nil ? weg.mime : "audio/mpeg",
                                                        huelle: huelle))
    }
}

/// **Was beim Zurückholen vom Lautsprecher kommt** (``Sonossteuerung/zurueckgeben()``).
public struct Sonosrueckgabe: Sendable, Equatable {
    /// Der Eintrag unserer Schlange, der dort lief.
    public let eintrag: UUID?
    public let stelle: TimeInterval
    /// Ob er spielte — dann spielt es hier weiter, sonst steht es angehalten.
    public let lief: Bool
}

/// Was eine Abfrage ergab.
public struct Sonosabfrage: Sendable, Equatable {
    public let lage: SonosLage
    public let befund: Sonosfolge.Befund
    /// Nach ``Sonosfolge/Befund/weiter``: der Eintrag, der jetzt läuft.
    public let eintrag: UUID?
}

/// **Die Wiedergabe auf einer Sonos-Gruppe** — alle Befehle gehen an den
/// Koordinator.
///
/// **Die Schlange liegt in der Sonos-Warteschlange** (bis zu
/// ``Sonosfolge/hoechstens`` Lieder um das laufende), und der Lautsprecher
/// spielt sie selbst durch — auch wenn das iPhone gesperrt ist oder die App
/// im Hintergrund schläft. Unsere ``Warteschlange`` bleibt die Quelle: was
/// sich hier ändert, wird drüben hinter dem laufenden Lied angeglichen
/// (``nachziehen(aktuell:kommende:naechste:wiederholung:)``), und die Abfrage
/// liest über die Nummer (`Track`) zurück, wo er steht.
///
/// **Rückfall**, falls der Lautsprecher die Warteschlange ablehnt: einzelne
/// Adressen, das laufende Lied und das nächste (`SetNextAVTransportURI`).
/// Dann braucht es das Telefon für jedes weitere Lied.
public actor Sonossteuerung {
    public nonisolated let koordinator: SonosLautsprecher
    let client: SonosClient
    /// Im Rückfall: das laufende und das nächste Lied.
    public private(set) var gesendet: SonosGesendet?
    /// Mit Warteschlange: was dort liegt.
    public private(set) var schlange: Sonosschlange?

    public init(koordinator: SonosLautsprecher, sitzung: URLSession = SonosClient.standardsitzung) {
        self.koordinator = koordinator
        client = SonosClient(basis: koordinator.basis, sitzung: sitzung)
    }

    public var mitWarteschlange: Bool { schlange != nil }

    /// **Übernehmen**: die Lieder in die Warteschlange, bei `ab` anfangen,
    /// an der Stelle, und spielen, wenn gewollt. Scheitert die Warteschlange
    /// an einer Ablehnung, geht es mit einzelnen Adressen weiter.
    public func uebernehmen(_ spuren: [Sonosspur], ab: Int, stelle: TimeInterval, spielen: Bool,
                            wiederholung: Warteschlange.Wiederholung) async throws {
        guard spuren.indices.contains(ab) else { return }
        do {
            try await client.schlangeLeeren()
            try await client.anfuegen(spuren.map { ($0.adresse, $0.metadaten) })
            try await client.schlangeWaehlen(koordinator.id)
            try? await client.spielmodus(Sonosfolge.spielmodus(wiederholung))
            try await client.zuNummer(ab + 1)
            schlange = Sonosschlange(folge: spuren.map(\.eintrag), adressen: spuren.map(\.adresse),
                                     aktuell: ab, wiederholung: wiederholung)
            gesendet = nil
        } catch let f as SonosFehler where f != .nichtErreichbar && !f.quelleUnerreichbar {
            // Keine Warteschlange (manche Quellen, alte Firmware): einzeln.
            schlange = nil
            let naechste = wiederholung == .eines ? spuren[ab]
                : spuren.indices.contains(ab + 1) ? spuren[ab + 1]
                : (wiederholung == .alles && spuren.count > 1 ? spuren[0] : nil)
            try await laden(spuren[ab], naechste: naechste, stelle: stelle, spielen: spielen)
            return
        }
        if stelle > 1 { try? await client.springen(stelle) }
        if spielen { try await client.abspielen() }
    }

    /// **Ein anderes Lied unserer Schlange** — liegt es in der Warteschlange,
    /// nur dorthin springen. `false`: es liegt nicht dort (oder es gibt keine),
    /// dann muss neu übernommen werden.
    public func springen(zu eintrag: UUID, stelle: TimeInterval, spielen: Bool) async throws -> Bool {
        guard let i = schlange?.folge.firstIndex(of: eintrag) else { return false }
        try await client.zuNummer(i + 1)
        schlange?.aktuell = i
        if stelle > 1 { try? await client.springen(stelle) }
        if spielen { try await client.abspielen() }
        return true
    }

    /// **Hinter dem laufenden Lied angleichen**, nach einer Änderung hier
    /// (Als Nächstes, Umsortieren, Mischen, Wiederholen) oder nachdem er
    /// weitergespielt hat (hinten nachfüllen). `kommende`: was laut unserer
    /// Schlange nach dem laufenden kommt; `naechste`: dasselbe für den Rückfall.
    public func nachziehen(aktuell eintrag: UUID, kommende: [Sonosspur], naechste: Sonosspur?,
                           wiederholung: Warteschlange.Wiederholung) async throws {
        guard let s = schlange else {
            try await naechsteSetzen(naechste)
            return
        }
        // Läuft drüben gerade ein anderes Lied als hier, kommt erst der Sprung.
        guard s.eintrag == eintrag else { return }
        // Nach jedem Warten wird am jetzigen Stand geändert, nicht an einer
        // Kopie von vorher — eine Abfrage kann dazwischen `aktuell` setzen.
        if s.wiederholung != wiederholung {
            try await client.spielmodus(Sonosfolge.spielmodus(wiederholung))
            schlange?.wiederholung = wiederholung
        }
        switch s.angleich(kommende.map(\.eintrag)) {
        case .nichts:
            break
        case let .anfuegen(ab):
            let neu = Array(kommende[ab...])
            try await client.anfuegen(neu.map { ($0.adresse, $0.metadaten) })
            schlange?.folge += neu.map(\.eintrag)
            schlange?.adressen += neu.map(\.adresse)
        case let .ersetzen(ab, anzahl):
            try await client.bereichEntfernen(ab: ab, anzahl: anzahl)
            schlange?.folge.removeLast(anzahl)
            schlange?.adressen.removeLast(anzahl)
            try await client.anfuegen(kommende.map { ($0.adresse, $0.metadaten) })
            schlange?.folge += kommende.map(\.eintrag)
            schlange?.adressen += kommende.map(\.adresse)
        }
    }

    // MARK: Rückfall: einzelne Adressen

    /// **Ein Lied laden und (wenn gewollt) abspielen**, das nächste
    /// dahinter. Die Stelle erst nach dem Laden — vorher gibt es nichts zu
    /// springen, und Sonos lehnt `Seek` dann ab.
    public func laden(_ spur: Sonosspur, naechste: Sonosspur?, stelle: TimeInterval, spielen: Bool) async throws {
        try? await client.normalerLauf()
        try await client.laden(spur.adresse, metadaten: spur.metadaten)
        schlange = nil
        gesendet = SonosGesendet(adresse: spur.adresse, eintrag: spur.eintrag)
        try await naechsteSetzen(naechste)
        if stelle > 1 { try? await client.springen(stelle) }
        if spielen { try await client.abspielen() }
    }

    /// **Das nächste Lied nachziehen**, wenn sich die Schlange geändert hat.
    /// Dasselbe noch einmal zu schicken lässt es.
    public func naechsteSetzen(_ spur: Sonosspur?) async throws {
        guard var g = gesendet else { return }
        guard g.naechsteAdresse != spur?.adresse || g.naechsterEintrag != spur?.eintrag else { return }
        try await client.naechstesLaden(spur?.adresse ?? "", metadaten: spur?.metadaten ?? "")
        g.naechsteAdresse = spur?.adresse
        g.naechsterEintrag = spur?.eintrag
        gesendet = g
    }

    /// **Der Koordinator geht aus der Gruppe**: vorher die Gruppe an `neuer`
    /// abgeben, damit Warteschlange und Stelle mitwandern. Ohne das nahm der
    /// gehende Lautsprecher die Warteschlange mit, und der bleibende spielte
    /// ein anderes Lied (Test 25.09.). Zurück kommt die Steuerung für den
    /// neuen Koordinator, mit dem Wissen, was dort liegt.
    public func koordinationUebergeben(an neuer: SonosLautsprecher) async throws -> Sonossteuerung {
        try await client.koordinationAbgeben(an: neuer.id)
        let neu = Sonossteuerung(koordinator: neuer, sitzung: client.sitzung)
        await neu.stand(schlange: schlange, gesendet: gesendet)
        return neu
    }

    private func stand(schlange: Sonosschlange?, gesendet: SonosGesendet?) {
        self.schlange = schlange
        self.gesendet = gesendet
    }

    public func abspielen() async throws { try await client.abspielen() }
    public func pausieren() async throws { try await client.pausieren() }
    public func stoppen() async throws { try await client.stoppen() }
    public func springen(_ sekunden: TimeInterval) async throws { try await client.springen(sekunden) }

    /// **Nachsehen, was drüben läuft.** Mit Warteschlange zeigt die Nummer
    /// auf unseren Eintrag; im Rückfall rückt ``gesendet`` mit, wenn er ins
    /// nächste Lied gegangen ist. `eintrag` ist der, der jetzt läuft.
    public func abfragen() async throws -> Sonosabfrage {
        let lage = try await client.lage()
        if let s = schlange {
            let (befund, index) = Sonosfolge.befund(lage, schlange: s, koordinator: koordinator.id)
            guard let index else { return Sonosabfrage(lage: lage, befund: befund, eintrag: nil) }
            schlange?.aktuell = index
            return Sonosabfrage(lage: lage, befund: befund, eintrag: s.folge[index])
        }
        guard let g = gesendet else { return Sonosabfrage(lage: lage, befund: .fremd, eintrag: nil) }
        let befund = Sonosfolge.befund(lage, gesendet: g)
        if befund == .weiter, let naechste = g.naechsteAdresse, let eintrag = g.naechsterEintrag {
            gesendet = SonosGesendet(adresse: naechste, eintrag: eintrag)
            return Sonosabfrage(lage: lage, befund: .weiter, eintrag: eintrag)
        }
        return Sonosabfrage(lage: lage, befund: befund, eintrag: befund == .gleich ? g.eintrag : nil)
    }

    /// **Zurück aufs Telefon**: frisch fragen, wo er steht, und anhalten —
    /// nur, wenn dort unsere Musik läuft. Zurück kommt Lied, Stelle und ob
    /// er eben spielte; hier geht es genau so weiter (pausiert bleibt
    /// pausiert). `nil`: dort läuft nichts von uns, dann gilt der gemerkte
    /// Stand und fremde Musik läuft weiter.
    ///
    /// Erst lesen, dann anhalten: die Stelle nach `Pause` ist dieselbe, aber
    /// der Zustand wäre dann immer „pausiert".
    public func zurueckgeben() async throws -> Sonosrueckgabe? {
        let a = try await abfragen()
        guard a.befund == .gleich || a.befund == .weiter else { return nil }
        if a.lage.laeuft { try await client.pausieren() }
        return Sonosrueckgabe(eintrag: a.eintrag, stelle: a.lage.stelle, lief: a.lage.laeuft)
    }

    /// Vergessen, was geschickt war — nach dem Loslassen.
    public func vergessen() {
        gesendet = nil
        schlange = nil
    }
}

/// **Kommt der Lautsprecher an den Server?** Das merkt man erst beim
/// Abspielen: er nimmt die Adresse an, versucht es, und steht nach ein paar
/// Sekunden still. Spielt er nach ``frist`` noch nicht, war es das.
public struct Sonosanlauf: Sendable, Equatable {
    public static let frist: TimeInterval = 12
    private var seit: Date?

    public init() {}

    /// Abspielen wurde verlangt.
    public mutating func gestartet(jetzt: Date = Date()) { seit = jetzt }
    /// Pause oder Loslassen: nicht mehr warten.
    public mutating func beenden() { seit = nil }

    /// `true`, wenn er nach der Frist nicht spielt — einmal, dann ist Ruhe.
    public mutating func gescheitert(_ lage: SonosLage, jetzt: Date = Date()) -> Bool {
        guard let seit else { return false }
        if lage.zustand == .spielt, lage.stelle > 0 {
            self.seit = nil
            return false
        }
        guard jetzt.timeIntervalSince(seit) >= Self.frist else { return false }
        self.seit = nil
        return lage.zustand != .spielt
    }
}
