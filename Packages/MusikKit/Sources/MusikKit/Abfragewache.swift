import Foundation

/// **Wann eine wiederholte Abfrage als gestört gilt** — damit ein Platzhalter
/// nicht endlos steht, wenn der Server weg ist.
///
/// Das Geräteblatt fragt im Takt nach anderen Geräten und zeigte bis zur
/// ersten Antwort Platzhalter. Antwortete der Server nie, blieben sie für
/// immer (24.09.). Vorbild ist der Wachhund in `AirPlayFlaeche` im
/// Player: nach ``frist`` ohne Antwort ist Schluss mit Warten. Dazu zählen
/// Fehlschläge in Folge: nach ``fehlschlaege`` gilt es auch dann als gestört,
/// wenn vorher schon eine Liste da war — sie wäre sonst veraltet.
public struct Abfragewache: Sendable, Equatable {

    public enum Lage: Sendable, Equatable {
        /// Noch keine Antwort, die Frist läuft.
        case laedt
        /// Die letzte Abfrage kam an.
        case da
        /// Frist verstrichen oder zu oft gescheitert.
        case gestoert
    }

    /// Zwölf Sekunden wie beim Wachhund des Players: länger sieht auch bei
    /// Erfolg nach kaputt aus.
    public static let frist: Duration = .seconds(12)
    public static let fehlschlaege = 3

    public private(set) var lage: Lage = .laedt
    private var inFolge = 0

    public init() {}

    public mutating func geantwortet() {
        inFolge = 0
        lage = .da
    }

    public mutating func fehlgeschlagen() {
        inFolge += 1
        if inFolge >= Self.fehlschlaege { lage = .gestoert }
    }

    /// Die Frist ist um. Gilt nur, solange noch gar nichts kam.
    public mutating func fristVorbei() {
        if lage == .laedt { lage = .gestoert }
    }

    /// Von vorn warten — „Erneut versuchen", oder ein neuer Blick aufs Blatt.
    public mutating func vonVorn() {
        inFolge = 0
        lage = .laedt
    }
}
