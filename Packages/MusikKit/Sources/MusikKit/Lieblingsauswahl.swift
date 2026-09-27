import Foundation

/// **„Zu Playlist hinzufügen" bietet oben die Lieblingssongs an** — für ein
/// Album, eine Playlist, einen Künstler oder mehrere Lieder (24.09.).
///
/// Ein Tipp gibt allen Liedern das Herz, die noch keins haben. Haben schon
/// alle eins, heißt die Zeile „Aus Lieblingssongs entfernen" und nimmt es
/// allen wieder — bei mehr als einem Lied erst nach einer Rückfrage, denn
/// dabei geht etwas verloren, das man einzeln gesetzt hat. Bei einem
/// einzelnen Lied steht die Zeile nicht da: dort ist das Herz am Lied selbst.
public enum Lieblingsauswahl {

    public enum Angebot: Equatable, Sendable {
        /// Die Lieder, die noch kein Herz haben — nur die gehen zum Server.
        case hinzufuegen([String])
        /// Alle; jedes hat schon ein Herz.
        case entfernen([String])

        public var ids: [String] {
            switch self {
            case let .hinzufuegen(ids), let .entfernen(ids): ids
            }
        }

        public var an: Bool {
            if case .hinzufuegen = self { return true }
            return false
        }

        /// Entfernen fragt vorher, sobald es mehr als ein Lied trifft.
        public var rueckfrage: Bool {
            if case let .entfernen(ids) = self { return ids.count > 1 }
            return false
        }
    }

    /// Was die Zeile anbietet. `nil` bei einem einzelnen Lied (doppelte
    /// Einträge einer Playlist zählen einmal).
    public static func angebot(_ ids: [String], istFavorit: (String) -> Bool) -> Angebot? {
        var gesehen = Set<String>()
        let eindeutig = ids.filter { gesehen.insert($0).inserted }
        guard eindeutig.count > 1 else { return nil }
        let ohneHerz = eindeutig.filter { !istFavorit($0) }
        return ohneHerz.isEmpty ? .entfernen(eindeutig) : .hinzufuegen(ohneHerz)
    }

    /// **Jellyfin kennt nur ein Lied je Aufruf** — so viele laufen
    /// gleichzeitig. Ein Album mit 20 Liedern braucht dann drei Runden statt
    /// zwanzig, und der Server bekommt nicht zwanzig auf einmal.
    public static let gleichzeitig = 8

    /// **Subsonic nimmt viele `id` in einem Aufruf** — so viele je Aufruf,
    /// damit die Adresse kurz genug bleibt.
    public static let jeAufruf = 50

    /// `werte` in Bündeln zu höchstens `n`, in ihrer Reihenfolge.
    public static func buendel<T>(_ werte: [T], je n: Int) -> [[T]] {
        guard n > 0 else { return [werte] }
        return stride(from: 0, to: werte.count, by: n).map { Array(werte[$0 ..< min($0 + n, werte.count)]) }
    }
}

extension JellyfinQuelle {

    /// **Je Lied über den Herz-Weg** (``favorit(_:an:)``): jedes wird im
    /// ``Favoritenstand`` gemerkt, damit eine Meldung zum laufenden Lied das
    /// Herz nicht zurücksetzt. In Bündeln zu ``Lieblingsauswahl/gleichzeitig``;
    /// der erste Fehler bricht ab und kommt an.
    public func lieblingeSetzen(_ ids: [String], an: Bool) async throws {
        for buendel in Lieblingsauswahl.buendel(ids, je: Lieblingsauswahl.gleichzeitig) {
            try await withThrowingTaskGroup(of: Void.self) { gruppe in
                for id in buendel {
                    gruppe.addTask { try await self.favorit(.lied(id), an: an) }
                }
                try await gruppe.waitForAll()
            }
        }
    }
}

extension SubsonicQuelle {

    /// **Viele `id` in einem `star`** (``Lieblingsauswahl/jeAufruf`` je Aufruf).
    public func lieblingeSetzen(_ ids: [String], an: Bool) async throws {
        for buendel in Lieblingsauswahl.buendel(ids, je: Lieblingsauswahl.jeAufruf) {
            try await client.sterne(lieder: buendel, an: an)
        }
    }
}
