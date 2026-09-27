import Foundation

/// **Was läuft und was danach kommt.**
///
/// Ein Wert ohne Wiedergabe: der Player fragt ihn, was als Nächstes kommt,
/// und sagt ihm, wenn es so weit ist. So lässt sich jede Regel hier prüfen,
/// ohne dass ein Ton spielt.
///
/// Jeder Eintrag hat eine eigene Kennung — dasselbe Lied darf zweimal in der
/// Schlange stehen („Als Nächstes" auf das laufende Lied), und dann muss
/// klar sein, welches von beiden gemeint ist.
public struct Warteschlange: Sendable, Equatable, Codable {

    /// **Wiederholen in drei Stufen**, wie jeder Spieler es kennt: aus →
    /// die ganze Schlange → ein Lied → aus.
    public enum Wiederholung: String, Sendable, CaseIterable, Codable {
        case aus, alles, eines

        /// Die Stufe nach einem Tipp auf den Knopf.
        public var naechste: Wiederholung {
            switch self {
            case .aus: .alles
            case .alles: .eines
            case .eines: .aus
            }
        }
    }

    public struct Eintrag: Identifiable, Sendable, Hashable, Codable {
        public let id: UUID
        public let lied: Lied

        public init(id: UUID = UUID(), lied: Lied) {
            self.id = id
            self.lied = lied
        }
    }

    public private(set) var eintraege: [Eintrag] = []
    /// Die Stelle des laufenden Eintrags; `nil` bei leerer Schlange.
    public private(set) var position: Int?
    public private(set) var gemischt = false
    /// Gilt über ein neues Füllen hinaus — wer Wiederholen anstellt, will es
    /// auch beim nächsten Album.
    public private(set) var wiederholung: Wiederholung = .aus
    /// Die Reihenfolge ohne Mischen, als Kennungen — dorthin kehrt das
    /// Ausschalten zurück.
    private var ursprung: [UUID] = []

    public init() {}

    public var istLeer: Bool { eintraege.isEmpty }

    public var aktuell: Eintrag? {
        position.flatMap { eintraege.indices.contains($0) ? eintraege[$0] : nil }
    }

    /// Wohin „Weiter" führt. Am Ende mit Wiederholung wieder an den Anfang —
    /// aber nie auf sich selbst: steht nur ein Lied in der Schlange, gibt es
    /// kein nächstes, es beginnt von vorn (``wiederholtLaufendes``).
    public var naechster: Eintrag? {
        guard let position, !eintraege.isEmpty else { return nil }
        if position + 1 < eintraege.count { return eintraege[position + 1] }
        guard wiederholung != .aus, eintraege.count > 1 else { return nil }
        return eintraege[0]
    }

    /// Wohin „Zurück" führt; am Anfang mit Wiederholung ans Ende.
    public var vorheriger: Eintrag? {
        guard let position, !eintraege.isEmpty else { return nil }
        if position > 0 { return eintraege[position - 1] }
        guard wiederholung != .aus, eintraege.count > 1 else { return nil }
        return eintraege[eintraege.count - 1]
    }

    /// **Ob das laufende Lied an seinem Ende von vorn beginnt** — bei „ein
    /// Lied", und bei „alles", wenn die Schlange nur dieses eine hat.
    /// „Weiter" von Hand geht trotzdem zum nächsten.
    public var wiederholtLaufendes: Bool {
        guard aktuell != nil else { return false }
        return wiederholung == .eines || (wiederholung == .alles && eintraege.count == 1)
    }

    /// Was nach dem laufenden kommt.
    public var kommende: [Eintrag] {
        guard let position else { return [] }
        return Array(eintraege[(position + 1)...])
    }

    /// Was schon lief.
    public var gespielt: [Eintrag] {
        guard let position else { return [] }
        return Array(eintraege[..<position])
    }

    // MARK: - Füllen

    /// **Neu füllen und bei `start` anfangen.**
    ///
    /// Gemischt steht das gewählte Lied vorn und der Rest danach in zufälliger
    /// Folge — wer auf ein Lied tippt, will dieses hören. Ohne gewähltes Lied
    /// (`start == nil`, „Zufall" auf einer Albumseite) ist auch das erste
    /// zufällig.
    public mutating func setzen<G: RandomNumberGenerator>(
        _ lieder: [Lied], ab start: Int?, mischen: Bool, generator: inout G
    ) {
        let neu = lieder.map { Eintrag(lied: $0) }
        ursprung = neu.map(\.id)
        gemischt = mischen
        guard !neu.isEmpty else {
            eintraege = []
            position = nil
            return
        }
        let anfang = start.map { min(max($0, 0), neu.count - 1) }
        if mischen {
            if let anfang {
                var rest = neu
                let erster = rest.remove(at: anfang)
                rest.shuffle(using: &generator)
                eintraege = [erster] + rest
            } else {
                eintraege = neu.shuffled(using: &generator)
            }
            position = 0
        } else {
            eintraege = neu
            position = anfang ?? 0
        }
    }

    public mutating func setzen(_ lieder: [Lied], ab start: Int?, mischen: Bool) {
        var g = SystemRandomNumberGenerator()
        setzen(lieder, ab: start, mischen: mischen, generator: &g)
    }

    /// **Die Schlange eines anderen Geräts, zum Zeigen** (``Fernstand``).
    ///
    /// Die Folge ist schon die, in der das Gerät spielt — gemischt wird
    /// dort, nicht hier; `gemischt` ist nur der Schalter im Blatt. Bleiben die
    /// Lieder dieselben, behalten die Einträge ihre Kennungen: sonst bekäme
    /// „Als Nächstes" bei jeder Abfrage neue Zeilen und flackerte.
    public mutating func spiegeln(_ lieder: [Lied], aktuell: Int?, gemischt: Bool,
                                  wiederholung: Wiederholung) {
        if lieder.map(\.id) == eintraege.map(\.lied.id) {
            eintraege = zip(eintraege, lieder).map { Eintrag(id: $0.id, lied: $1) }
        } else {
            eintraege = lieder.map { Eintrag(lied: $0) }
        }
        ursprung = eintraege.map(\.id)
        position = eintraege.isEmpty ? nil : aktuell.map { min(max($0, 0), eintraege.count - 1) }
        self.gemischt = gemischt
        self.wiederholung = wiederholung
    }

    /// Direkt nach dem laufenden — in der Reihenfolge, in der sie übergeben
    /// werden. Auch in die ungemischte Reihenfolge, damit sie nach dem
    /// Ausschalten des Mischens weiter als Nächstes stehen.
    public mutating func alsNaechstes(_ lieder: [Lied]) {
        let neu = lieder.map { Eintrag(lied: $0) }
        guard !neu.isEmpty else { return }
        guard let position else {
            eintraege = neu
            ursprung = neu.map(\.id)
            self.position = 0
            return
        }
        eintraege.insert(contentsOf: neu, at: position + 1)
        if let laufend = aktuell?.id, let i = ursprung.firstIndex(of: laufend) {
            ursprung.insert(contentsOf: neu.map(\.id), at: i + 1)
        } else {
            ursprung.append(contentsOf: neu.map(\.id))
        }
    }

    /// Ans Ende.
    public mutating func hintenAn(_ lieder: [Lied]) {
        let neu = lieder.map { Eintrag(lied: $0) }
        guard !neu.isEmpty else { return }
        eintraege.append(contentsOf: neu)
        ursprung.append(contentsOf: neu.map(\.id))
        if position == nil { position = 0 }
    }

    // MARK: - Weitergehen

    /// Zum nächsten; am Ende ohne Wiederholung `nil`, und die Position
    /// bleibt stehen.
    @discardableResult
    public mutating func weiter() -> Eintrag? {
        guard let ziel = naechster, let i = eintraege.firstIndex(where: { $0.id == ziel.id }) else { return nil }
        position = i
        return aktuell
    }

    /// Zum vorigen; am Anfang ohne Wiederholung `nil`.
    @discardableResult
    public mutating func zurueck() -> Eintrag? {
        guard let ziel = vorheriger, let i = eintraege.firstIndex(where: { $0.id == ziel.id }) else { return nil }
        position = i
        return aktuell
    }

    /// **Weiter zum nächsten Lied, das spielbar ist** — ohne Netz sind das
    /// die geladenen. Gezählt wird wie bei ``weiter()``, also mit
    /// Wiederholung über das Ende hinaus, aber nie im Kreis: gibt es keins,
    /// bleibt die Stelle, und das Ergebnis ist `nil`.
    @discardableResult
    public mutating func weiterZuSpielbarem(_ spielbar: (Lied) -> Bool) -> Eintrag? {
        guard let anfang = position else { return nil }
        var probe = self
        for _ in eintraege.indices {
            guard let neu = probe.weiter(), probe.position != anfang else { break }
            if spielbar(neu.lied) {
                position = probe.position
                return aktuell
            }
        }
        return nil
    }

    // MARK: - Wiederholen

    public mutating func wiederholen(_ neu: Wiederholung) {
        wiederholung = neu
    }

    /// Ein Tipp auf den Knopf: aus → alles → ein Lied → aus.
    public mutating func wiederholungWeiterschalten() {
        wiederholung = wiederholung.naechste
    }

    @discardableResult
    public mutating func springe(zu id: UUID) -> Eintrag? {
        guard let i = eintraege.firstIndex(where: { $0.id == id }) else { return nil }
        position = i
        return aktuell
    }

    // MARK: - Ändern

    /// Nimmt einen Eintrag heraus. Den laufenden nicht — der geht über
    /// ``weiter()``, sonst hätte der Player nichts mehr, was er spielt.
    public mutating func entfernen(_ id: UUID) {
        guard let i = eintraege.firstIndex(where: { $0.id == id }), i != position else { return }
        eintraege.remove(at: i)
        ursprung.removeAll { $0 == id }
        if let position, i < position { self.position = position - 1 }
    }

    /// Verschiebt einen kommenden Eintrag an eine andere Stelle unter den
    /// kommenden (`ziel` zählt ab dem ersten kommenden, 0 = als Nächstes).
    public mutating func verschieben(_ id: UUID, nach ziel: Int) {
        guard let position, let i = eintraege.firstIndex(where: { $0.id == id }), i > position
        else { return }
        let eintrag = eintraege.remove(at: i)
        let stelle = min(max(position + 1 + ziel, position + 1), eintraege.count)
        eintraege.insert(eintrag, at: stelle)
    }

    /// Leert alles, was nach dem laufenden kommt.
    public mutating func kommendeLeeren() {
        guard let position else { return }
        let raus = Set(eintraege[(position + 1)...].map(\.id))
        eintraege.removeSubrange((position + 1)...)
        ursprung.removeAll { raus.contains($0) }
    }

    // MARK: - Mischen

    /// **Mischen an- oder ausschalten, ohne dass das laufende Lied abbricht.**
    ///
    /// An: nur was noch kommt, wird gemischt; was schon lief, bleibt stehen.
    /// Aus: zurück in die ursprüngliche Folge, und es geht mit dem Lied weiter,
    /// das dort auf das laufende folgt — so machen es die großen Spieler auch.
    public mutating func mischen<G: RandomNumberGenerator>(_ an: Bool, generator: inout G) {
        guard an != gemischt else { return }
        gemischt = an
        guard let position else { return }
        if an {
            var rest = Array(eintraege[(position + 1)...])
            rest.shuffle(using: &generator)
            eintraege.replaceSubrange((position + 1)..., with: rest)
        } else {
            guard let laufend = aktuell?.id else { return }
            let nachKennung = Dictionary(eintraege.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var geordnet = ursprung.compactMap { nachKennung[$0] }
            // Was im Ursprung fehlt (sollte es nicht geben), hängt hinten an.
            let bekannt = Set(ursprung)
            geordnet.append(contentsOf: eintraege.filter { !bekannt.contains($0.id) })
            eintraege = geordnet
            self.position = eintraege.firstIndex { $0.id == laufend } ?? 0
        }
    }

    public mutating func mischen(_ an: Bool) {
        var g = SystemRandomNumberGenerator()
        mischen(an, generator: &g)
    }

    /// Ersetzt ein Lied überall, wo es steht — etwa nachdem der Favorit
    /// umgeschaltet wurde. Kennungen und Stelle bleiben.
    public mutating func aktualisieren(_ lied: Lied) {
        for i in eintraege.indices where eintraege[i].lied.id == lied.id {
            eintraege[i] = Eintrag(id: eintraege[i].id, lied: lied)
        }
    }
}

/// **Die Schlange samt Stelle, zum Ablegen** — damit nach einem Neustart
/// dasselbe Lied an derselben Stelle bereitsteht (Finamps `SavedQueueState`,
/// Supersonics gespeicherte Schlange).
public struct Schlangenstand: Sendable, Codable, Equatable {
    public var schlange: Warteschlange
    /// Sekunden im laufenden Lied.
    public var stelle: TimeInterval
    public var herkunft: Sammlungsverweis?
    public var zeit: Date

    public init(schlange: Warteschlange, stelle: TimeInterval, herkunft: Sammlungsverweis?, zeit: Date = Date()) {
        self.schlange = schlange
        self.stelle = stelle
        self.herkunft = herkunft
        self.zeit = zeit
    }

    /// Ob sich das Wiederherstellen lohnt: es gibt ein laufendes Lied.
    public var taugt: Bool { schlange.aktuell != nil }

    /// Die Stelle, an der es weitergeht. Kurz vor dem Ende eines Liedes
    /// lieber von vorn — sonst ist es nach dem Tippen auf Abspielen sofort
    /// vorbei.
    public var fortsetzen: TimeInterval {
        guard stelle > 1 else { return 0 }
        if let dauer = schlange.aktuell?.lied.dauer, stelle > dauer - 5 { return 0 }
        return stelle
    }
}
