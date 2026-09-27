import Foundation

/// **Der Abspielknopf zeigt, was gewollt ist — eine Ladeanzeige nur, wenn
/// es wirklich dauert.**
///
/// Nach einem Druck auf Abspielen meldet `AVPlayer` fast immer kurz
/// `waitingToPlayAtSpecifiedRate`, bevor er spielt — auch wenn alles schon
/// im Puffer liegt. Reichte man das ans Zeichen durch, sprang es zwischen
/// Pause, Ladeanzeige und Pause hin und her (24.09.). Das Zeichen hängt
/// deshalb nur am Wunsch (spielen oder nicht), und die Ladeanzeige erscheint
/// erst, wenn das Warten länger als ``schwelle`` dauert.
///
/// Die Zeit kommt von außen (`jetzt`, monoton, in Sekunden), damit sich die
/// Regel ohne echten Takt prüfen lässt — wie ``Stellenuhr``.
public struct Ladeanzeige: Sendable, Equatable {
    /// So lange darf der Player warten, ohne dass man es sieht.
    public static let schwelle: TimeInterval = 0.4

    /// Seit wann der Player wartet, während gespielt werden soll.
    public private(set) var wartetSeit: TimeInterval?

    public init() {}

    /// **Eine Meldung vom Player**: wartet er gerade auf Daten, obwohl
    /// gespielt werden soll? Eine Folge von Wartemeldungen zählt ab der
    /// ersten; jede andere Meldung beendet das Warten.
    public mutating func melden(wartet: Bool, jetzt: TimeInterval) {
        if wartet {
            if wartetSeit == nil { wartetSeit = jetzt }
        } else {
            wartetSeit = nil
        }
    }

    /// Ob die Ladeanzeige jetzt zu sehen ist.
    public func sichtbar(jetzt: TimeInterval) -> Bool {
        guard let seit = wartetSeit else { return false }
        return jetzt - seit >= Self.schwelle
    }

    /// Wann die Ladeanzeige erscheint, wenn bis dahin nichts anderes kommt —
    /// dann muss jemand noch einmal nachsehen.
    public var faellig: TimeInterval? { wartetSeit.map { $0 + Self.schwelle } }
}
