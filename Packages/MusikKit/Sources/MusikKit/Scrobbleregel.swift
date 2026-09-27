import Foundation

/// **Wann ein Lied als gehört zählt:** nach der Hälfte oder nach vier
/// Minuten, je nachdem, was zuerst kommt — die Regel von Last.fm, nach der
/// sich auch Navidromes Zählung richtet.
public enum Scrobbleregel {

    /// Vier Minuten.
    public static let hoechstens: TimeInterval = 240

    /// Die Schwelle für ein Lied dieser Dauer. Ohne bekannte Dauer gelten
    /// die vier Minuten.
    public static func schwelle(dauer: TimeInterval?) -> TimeInterval {
        guard let dauer, dauer > 0 else { return hoechstens }
        return min(hoechstens, dauer / 2)
    }

    public static func erreicht(gehoert: TimeInterval, dauer: TimeInterval?) -> Bool {
        gehoert >= schwelle(dauer: dauer)
    }
}

/// **Die tatsächlich gehörte Zeit eines Liedes.**
///
/// Nicht die Stelle: wer ans Ende spult, hat das Lied nicht gehört. Gezählt
/// wird nur, was zwischen zwei Messungen im Lauf vergangen ist, und nur in
/// kleinen Schritten — ein Sprung nach vorn oder zurück fällt heraus.
public struct Hoerzeit: Sendable, Equatable {
    public private(set) var gehoert: TimeInterval = 0
    private var zuletzt: TimeInterval?

    /// Größer als das hier ist kein Fortschritt mehr, sondern ein Sprung.
    /// Die Messung kommt zweimal je Sekunde; drei Sekunden lassen einem
    /// stockenden Hauptlauf Luft.
    public static let groessterSchritt: TimeInterval = 3

    public init() {}

    /// Eine neue Stelle. Zählt nur, wenn gerade gespielt wird.
    public mutating func messen(_ position: TimeInterval, laeuft: Bool) {
        defer { zuletzt = position }
        guard laeuft, let zuletzt else { return }
        let schritt = position - zuletzt
        if schritt > 0, schritt <= Self.groessterSchritt { gehoert += schritt }
    }

    /// Nach einem Sprung: ab hier neu messen.
    public mutating func gesprungen(auf position: TimeInterval) {
        zuletzt = position
    }
}
