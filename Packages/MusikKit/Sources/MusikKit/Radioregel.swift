import Foundation

/// **Weiter mit Ähnlichem, wenn die Schlange zu Ende geht** — wie Finamps
/// Radio und Feishins „Auto DJ": steht nur noch ein Lied aus, holt der
/// Spieler einen Sofortmix zum laufenden und hängt an, was noch nicht in der
/// Schlange steht.
public enum Radioregel {

    /// Nachschub braucht es, wenn höchstens noch ein Lied kommt — nicht bei
    /// Wiederholung (dann geht es ohnehin weiter) und nicht bei Hörbüchern.
    public static func brauchtNachschub(_ schlange: Warteschlange, an: Bool) -> Bool {
        guard an, schlange.wiederholung == .aus, let aktuell = schlange.aktuell,
              !aktuell.lied.istHoerbuch else { return false }
        return schlange.kommende.count <= 1
    }

    /// Aus den Vorschlägen, was noch nicht in der Schlange steht, jedes nur
    /// einmal, höchstens `anzahl`.
    public static func auswahl(_ vorschlaege: [Lied], schlange: Warteschlange, anzahl: Int = 25) -> [Lied] {
        var schon = Set(schlange.eintraege.map(\.lied.id))
        var neu: [Lied] = []
        for lied in vorschlaege where !lied.istHoerbuch && schon.insert(lied.id).inserted {
            neu.append(lied)
            if neu.count == anzahl { break }
        }
        return neu
    }
}
