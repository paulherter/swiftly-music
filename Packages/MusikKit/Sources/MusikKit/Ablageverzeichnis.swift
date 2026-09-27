import Foundation

/// **Was auf dem Gerät liegt — das Verzeichnis, nicht die Dateien.**
///
/// Geladen wird je Sammlung (Album, Playlist, Hörbuch). Ein Lied kann in
/// mehreren stehen — ein Album und eine Playlist teilen sich dann dieselbe
/// Datei, und sie verschwindet erst, wenn keine Sammlung sie mehr braucht.
///
/// Es gehört einem Konto (``Kontokennung``); die App legt eins je Konto ab.
/// Die Dateien selbst schreibt und löscht die App — hier steht nur, welche
/// es gibt und wer sie braucht, damit sich das ohne Gerät prüfen lässt.
public struct Ablageverzeichnis: Sendable, Equatable, Codable {

    public struct Datei: Sendable, Equatable, Codable {
        public var lied: Lied
        /// Relativ zum Ablageordner des Kontos.
        public var pfad: String
        public var groesse: Int64
        public var art: Abspielart
        /// Der Medientyp der abgelegten Datei.
        public var mime: String?
        public var geladen: Date

        public init(lied: Lied, pfad: String, groesse: Int64, art: Abspielart, mime: String?,
                    geladen: Date) {
            self.lied = lied
            self.pfad = pfad
            self.groesse = groesse
            self.art = art
            self.mime = mime
            self.geladen = geladen
        }

        private enum K: String, CodingKey { case lied, pfad, groesse, art, mime, geladen }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            lied = try c.decode(Lied.self, forKey: .lied)
            pfad = try c.decode(String.self, forKey: .pfad)
            groesse = (try? c.decodeIfPresent(Int64.self, forKey: .groesse)) ?? 0
            art = (try? c.decodeIfPresent(Abspielart.self, forKey: .art)) ?? .direkt
            mime = try? c.decodeIfPresent(String.self, forKey: .mime)
            geladen = (try? c.decodeIfPresent(Date.self, forKey: .geladen)) ?? .distantPast
        }
    }

    public struct Sammlung: Sendable, Equatable, Codable, Identifiable {
        public var verweis: Sammlungsverweis
        /// Alle Lieder der Sammlung in ihrer Reihenfolge — auch die, die noch
        /// nicht fertig geladen sind.
        public var lieder: [Lied]
        public var angelegt: Date

        public var id: String { verweis.id }

        public init(verweis: Sammlungsverweis, lieder: [Lied], angelegt: Date) {
            self.verweis = verweis
            self.lieder = lieder
            self.angelegt = angelegt
        }

        private enum K: String, CodingKey { case verweis, lieder, angelegt }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            verweis = try c.decode(Sammlungsverweis.self, forKey: .verweis)
            lieder = (try? c.decodeIfPresent([Lied].self, forKey: .lieder)) ?? []
            angelegt = (try? c.decodeIfPresent(Date.self, forKey: .angelegt)) ?? .distantPast
        }
    }

    /// Lied-Kennung → Datei.
    public private(set) var dateien: [String: Datei] = [:]
    /// Sammlungs-Kennung (``Sammlungsverweis/id``) → Sammlung.
    public private(set) var sammlungen: [String: Sammlung] = [:]

    public init() {}

    private enum K: String, CodingKey { case dateien, sammlungen }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        dateien = (try? c.decodeIfPresent([String: Datei].self, forKey: .dateien)) ?? [:]
        sammlungen = (try? c.decodeIfPresent([String: Sammlung].self, forKey: .sammlungen)) ?? [:]
    }

    // MARK: - Fragen

    public func datei(fuer liedID: String) -> Datei? { dateien[liedID] }
    public func istGeladen(_ liedID: String) -> Bool { dateien[liedID] != nil }

    /// Wie weit eine Sammlung geladen ist.
    public enum Stand: Equatable, Sendable {
        case nicht
        /// Angefangen: so viele von so vielen.
        case teilweise(fertig: Int, von: Int)
        case ganz
    }

    public func stand(_ verweisID: String) -> Stand {
        guard let s = sammlungen[verweisID] else { return .nicht }
        let fertig = s.lieder.filter { dateien[$0.id] != nil }.count
        if fertig == s.lieder.count, fertig > 0 { return .ganz }
        return .teilweise(fertig: fertig, von: s.lieder.count)
    }

    /// Welche Lieder einer Sammlung noch fehlen, in ihrer Reihenfolge.
    public func fehlend(_ verweisID: String) -> [Lied] {
        sammlungen[verweisID]?.lieder.filter { dateien[$0.id] == nil } ?? []
    }

    /// Alles, was noch zu laden ist, Sammlung für Sammlung in der Reihenfolge,
    /// in der sie angelegt wurden — jedes Lied einmal.
    public var warteschlange: [Lied] {
        var gesehen = Set<String>()
        var liste: [Lied] = []
        for s in sammlungen.values.sorted(by: { $0.angelegt < $1.angelegt }) {
            for lied in s.lieder where dateien[lied.id] == nil && !gesehen.contains(lied.id) {
                gesehen.insert(lied.id)
                liste.append(lied)
            }
        }
        return liste
    }

    public var belegt: Int64 { dateien.values.reduce(0) { $0 + $1.groesse } }

    /// Die geladenen Sammlungen einer Art, zuletzt angelegte zuerst.
    public func sammlungen(_ art: Sammlungsart) -> [Sammlung] {
        sammlungen.values.filter { $0.verweis.art == art }.sorted { $0.angelegt > $1.angelegt }
    }

    // MARK: - Ändern

    /// Merkt eine Sammlung zum Laden vor. Steht sie schon da, gilt die neue
    /// Liederliste (ein Album kann Lieder dazubekommen haben).
    public mutating func vormerken(_ verweis: Sammlungsverweis, lieder: [Lied], jetzt: Date = Date()) {
        let angelegt = sammlungen[verweis.id]?.angelegt ?? jetzt
        sammlungen[verweis.id] = Sammlung(verweis: verweis, lieder: lieder, angelegt: angelegt)
    }

    /// Eine fertig geladene Datei eintragen.
    public mutating func eintragen(_ datei: Datei) {
        dateien[datei.lied.id] = datei
    }

    /// Eine Datei gilt nicht mehr als geladen (sie fehlt auf der Platte). Die
    /// Sammlungen bleiben — das Lied steht damit wieder in der Warteschlange.
    public mutating func vergessen(liedID: String) {
        dateien[liedID] = nil
    }

    /// **Nimmt eine Sammlung heraus und sagt, welche Dateien weg dürfen** —
    /// nur die, die keine andere Sammlung mehr braucht.
    public mutating func entfernen(_ verweisID: String) -> [Datei] {
        guard let raus = sammlungen.removeValue(forKey: verweisID) else { return [] }
        let nochGebraucht = Set(sammlungen.values.flatMap { $0.lieder.map(\.id) })
        var frei: [Datei] = []
        for lied in raus.lieder where !nochGebraucht.contains(lied.id) {
            if let d = dateien.removeValue(forKey: lied.id) { frei.append(d) }
        }
        return frei
    }

    /// Alles weg — etwa beim Abmelden. Gibt die Dateien zurück.
    public mutating func leeren() -> [Datei] {
        let alle = Array(dateien.values)
        dateien = [:]
        sammlungen = [:]
        return alle
    }

    /// Dateien, zu denen es keine Sammlung mehr gibt (nach einem Abbruch).
    public mutating func verwaisteEntfernen() -> [Datei] {
        let gebraucht = Set(sammlungen.values.flatMap { $0.lieder.map(\.id) })
        var frei: [Datei] = []
        for (id, d) in dateien where !gebraucht.contains(id) {
            dateien.removeValue(forKey: id)
            frei.append(d)
        }
        return frei
    }
}
