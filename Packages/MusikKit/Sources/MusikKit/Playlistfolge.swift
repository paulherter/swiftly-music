import Foundation

/// **Was eine Änderung an einer Playlist aus ihrer Folge macht** — damit die
/// Seite sofort richtig steht, bevor der Server antwortet, und sich bei
/// einem Fehler genau zurückdrehen lässt.
public enum Playlistfolge {

    /// Ein Eintrag wandert von `von` an die Stelle `nach` der neuen Folge.
    public static func verschoben<T>(_ liste: [T], von: Int, nach: Int) -> [T] {
        guard liste.indices.contains(von) else { return liste }
        var neu = liste
        let eintrag = neu.remove(at: von)
        neu.insert(eintrag, at: min(max(nach, 0), neu.count))
        return neu
    }

    /// Ohne die Einträge an diesen Stellen.
    public static func ohne<T>(_ liste: [T], stellen: Set<Int>) -> [T] {
        liste.enumerated().filter { !stellen.contains($0.offset) }.map(\.element)
    }

    /// Welche der neuen Lieder schon darin stehen — dann fragt die App,
    /// bevor sie ein zweites Mal hinzufügt.
    public static func schonDarin(_ neue: [Lied], in vorhanden: [Lied]) -> [Lied] {
        let da = Set(vorhanden.map(\.id))
        return neue.filter { da.contains($0.id) }
    }

    /// **Höchstens 50 Kennungen je Aufruf** — sie stehen in der Adresse, und
    /// die hat eine Länge (Feishins `MAX_ITEMS_PER_PLAYLIST_ADD`).
    public static let buendelgroesse = 50

    public static func buendel<T>(_ liste: [T], groesse: Int = buendelgroesse) -> [[T]] {
        stride(from: 0, to: liste.count, by: max(groesse, 1)).map { Array(liste[$0 ..< min($0 + groesse, liste.count)]) }
    }

    /// `onMove` in SwiftUI nennt das Ziel **vor** dem Herausnehmen; die
    /// Server wollen die Stelle in der neuen Folge.
    public static func zielstelle(von: Int, vorStelle: Int) -> Int {
        vorStelle > von ? vorStelle - 1 : vorStelle
    }
}
