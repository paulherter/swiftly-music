import Foundation
import SubsonicKit

/// **Weiterhören über die Schlange des Servers** — der Weg für Navidrome
/// und jeden anderen Subsonic-Server.
///
/// **Keine Live-Steuerung, und das ist keine Lücke in Swiftly Music.**
/// Subsonic hat keinen Kanal vom Server zu den Apps: kein Gerät erfährt, dass
/// ein anderes etwas will, also kann niemand eine laufende Wiedergabe
/// anderswo anhalten, weiterschalten oder sehen. Was die Schnittstelle
/// bietet, ist eine abgelegte Schlange je Konto (`savePlayQueue`,
/// `getPlayQueue`). Swiftly Music legt sie beim Pausieren, beim Liedwechsel,
/// beim Gang in den Hintergrund und alle 30 Sekunden ab — und bietet beim
/// Start an, dort weiterzuhören, wo ein anderes Gerät aufgehört hat.
public protocol Serverschlange: AnyObject, Sendable {
    func schlangeSichern(ids: [String], aktuell: String?, stelle: TimeInterval) async throws
    func schlangeHolen() async throws -> Gespeicherteschlange?
}

/// Was auf dem Server liegt, in unseren Begriffen.
public struct Gespeicherteschlange: Sendable, Equatable {
    public let lieder: [Lied]
    public let aktuell: Int
    /// Sekunden.
    public let stelle: TimeInterval
    public let geaendert: Date?
    /// Der Programmname dessen, der sie abgelegt hat.
    public let von: String?

    public init(lieder: [Lied], aktuell: Int, stelle: TimeInterval, geaendert: Date?, von: String?) {
        self.lieder = lieder
        self.aktuell = aktuell
        self.stelle = stelle
        self.geaendert = geaendert
        self.von = von
    }

    public var lied: Lied? { lieder.indices.contains(aktuell) ? lieder[aktuell] : nil }
}

extension SubsonicQuelle: Serverschlange {

    /// Höchstens ``Uebergabe/hoechstens`` Lieder um das laufende — die
    /// Kennungen stehen in der Adresse.
    public func schlangeSichern(ids: [String], aktuell: String?, stelle: TimeInterval) async throws {
        let ab = aktuell.flatMap { ids.firstIndex(of: $0) } ?? 0
        let (teil, _) = Uebergabe.fenster(ids, ab: ab)
        try await client.schlangeSpeichern(liedIDs: teil, aktuell: aktuell,
                                           stelleMs: Int((max(0, stelle) * 1000).rounded()))
    }

    public func schlangeHolen() async throws -> Gespeicherteschlange? {
        guard let s = try await client.schlange() else { return nil }
        let lieder = s.lieder.map(liedAus)
        let aktuell = s.aktuell.flatMap { id in lieder.firstIndex { $0.id == id } } ?? 0
        return Gespeicherteschlange(lieder: lieder, aktuell: aktuell, stelle: TimeInterval(s.stelle) / 1000,
                                    geaendert: s.geaendert, von: s.geaendertVon)
    }
}

/// **Ob die Schlange des Servers ein Angebot wert ist.**
public enum Schlangenvergleich {

    /// So viel darf die Uhr des Servers von der eigenen abweichen, ohne dass
    /// die eigene Sicherung als fremd gilt.
    public static let spielraum: TimeInterval = 10

    /// **Nur, was ein anderes Gerät nach uns abgelegt hat.**
    ///
    /// Der Programmname reicht dafür nicht: zwei iPhones mit Swiftly Music
    /// heißen beide „Swiftly Music". Entscheidend ist die Zeit — liegt die
    /// Änderung auf dem Server deutlich nach der letzten eigenen Sicherung,
    /// war es jemand anders.
    ///
    /// - Parameters:
    ///   - eigeneSicherung: wann dieses Gerät zuletzt abgelegt hat; `nil`, wenn nie.
    ///   - hier: das Lied und die Stelle, die hier bereitstehen.
    ///   - hierSpielt: läuft hier gerade etwas, wird nichts angeboten.
    public static func lohntAngebot(_ server: Gespeicherteschlange, eigeneSicherung: Date?,
                                    hier: (liedID: String, stelle: TimeInterval)?,
                                    hierSpielt: Bool) -> Bool {
        guard !hierSpielt, let lied = server.lied, let geaendert = server.geaendert else { return false }
        if let eigeneSicherung, geaendert <= eigeneSicherung.addingTimeInterval(spielraum) { return false }
        // Steht hier schon dasselbe an fast derselben Stelle, gibt es nichts zu holen.
        if let hier, hier.liedID == lied.id, abs(hier.stelle - server.stelle) < 15 { return false }
        return true
    }
}
