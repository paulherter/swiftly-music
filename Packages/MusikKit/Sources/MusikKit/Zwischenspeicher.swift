import Foundation

/// **Ein kleiner Speicher mit fester Obergrenze**: was zuletzt gebraucht
/// wurde, bleibt; ist er voll, geht der älteste Eintrag.
///
/// Gebaut für den Liedtext (24.09.): die Ansicht fragte bei jedem
/// Öffnen den Server, auch für das Lied, das seit drei Minuten läuft.
/// Gemerkt wird auch „kein Liedtext" (`Wert` ist dann ein Optional mit
/// `nil`) — ein Fehler dagegen nie, sonst bliebe ein Aussetzer des Servers
/// bis zum Neustart als „nichts da" stehen.
public struct Zwischenspeicher<Schluessel: Hashable & Sendable, Wert: Sendable>: Sendable {
    public let grenze: Int
    private var werte: [Schluessel: Wert] = [:]
    /// Älteste zuerst.
    private var folge: [Schluessel] = []

    public init(grenze: Int) {
        precondition(grenze > 0)
        self.grenze = grenze
    }

    public var anzahl: Int { werte.count }

    /// Der gemerkte Wert — und er zählt ab jetzt als zuletzt gebraucht.
    public mutating func wert(_ schluessel: Schluessel) -> Wert? {
        guard let wert = werte[schluessel] else { return nil }
        auffrischen(schluessel)
        return wert
    }

    public mutating func merken(_ wert: Wert, fuer schluessel: Schluessel) {
        if werte.updateValue(wert, forKey: schluessel) != nil {
            auffrischen(schluessel)
            return
        }
        folge.append(schluessel)
        while folge.count > grenze {
            werte[folge.removeFirst()] = nil
        }
    }

    public mutating func leeren() {
        werte = [:]
        folge = []
    }

    private mutating func auffrischen(_ schluessel: Schluessel) {
        guard let i = folge.firstIndex(of: schluessel), i != folge.count - 1 else { return }
        folge.remove(at: i)
        folge.append(schluessel)
    }
}
