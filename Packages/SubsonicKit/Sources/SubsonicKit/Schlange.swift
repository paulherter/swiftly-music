import Foundation

/// **Die Schlange auf dem Server** — `getPlayQueue`/`savePlayQueue`.
///
/// Subsonic kennt keinen Kanal vom Server zu den Apps: niemand kann eine
/// laufende Wiedergabe auf einem anderen Gerät anhalten oder steuern. Was
/// es gibt, ist eine abgelegte Schlange je Konto — Lieder, das laufende, die
/// Stelle, und welches Programm sie wann abgelegt hat. Damit lässt sich auf
/// einem Gerät weiterhören, wo ein anderes aufgehört hat; mehr nicht.
public struct SubsonicSchlange: Sendable, Equatable, Decodable {
    public let lieder: [SubsonicLied]
    /// Kennung des laufenden Liedes.
    public let aktuell: String?
    /// Millisekunden im laufenden Lied.
    public let stelle: Int
    public let benutzer: String?
    public let geaendert: Date?
    /// Der Programmname (`c`) dessen, der sie abgelegt hat — bei uns
    /// „Swiftly Music", bei anderen etwa „Feishin" oder „Symfonium".
    public let geaendertVon: String?

    public init(lieder: [SubsonicLied], aktuell: String?, stelle: Int, benutzer: String? = nil,
                geaendert: Date?, geaendertVon: String?) {
        self.lieder = lieder
        self.aktuell = aktuell
        self.stelle = stelle
        self.benutzer = benutzer
        self.geaendert = geaendert
        self.geaendertVon = geaendertVon
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        lieder = c.liste("entry")
        aktuell = c.text("current")
        stelle = c.zahl("position") ?? 0
        benutzer = c.text("username")
        geaendert = c.zeit("changed")
        geaendertVon = c.text("changedBy")
    }
}

struct SchlangenNutzlast: Nutzlast {
    static let schluessel: String? = "playQueue"
    static var leer: SchlangenNutzlast { SchlangenNutzlast(wert: nil) }
    let wert: SubsonicSchlange?
    init(wert: SubsonicSchlange?) { self.wert = wert }
    init(from decoder: any Decoder) throws { wert = try SubsonicSchlange(from: decoder) }
}

extension SubsonicClient {

    /// `getPlayQueue` — `nil`, wenn keine abgelegt ist.
    public func schlange() async throws -> SubsonicSchlange? {
        let wert = try await holen("getPlayQueue", als: SchlangenNutzlast.self).wert
        guard let wert, !wert.lieder.isEmpty else { return nil }
        return wert
    }

    /// `savePlayQueue` — die Lieder in ihrer Folge, das laufende und die
    /// Stelle in Millisekunden. Ohne Lieder löscht der Server die Schlange.
    public func schlangeSpeichern(liedIDs: [String], aktuell: String?, stelleMs: Int) async throws {
        var werte = liedIDs.map { URLQueryItem(name: "id", value: $0) }
        if let aktuell, !liedIDs.isEmpty {
            werte.append(.init(name: "current", value: aktuell))
            werte.append(.init(name: "position", value: String(max(0, stelleMs))))
        }
        _ = try await holen("savePlayQueue", werte, als: OhneNutzlast.self)
    }
}
