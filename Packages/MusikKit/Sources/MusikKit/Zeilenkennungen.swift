import Foundation

/// **Welche Zeilen beim Wechsel einer Kapsel an ihren neuen Platz ziehen und
/// welche überblenden.**
///
/// Bibliothek und Suche tauschen beim Wechsel einer Kapsel die Liste. Eine
/// Zeile mit derselben Kennung zieht an ihren neuen Platz — das ist das
/// „Fliegen", das beim Wählen und Abwählen zeigt, woher ein Eintrag kommt.
/// Nur quer über den Schirm soll keine fliegen: liegt der alte oder der neue
/// Platz außerhalb des Sichtbaren, oder ist der Weg länger als ein halber
/// Schirm, bekommt die Zeile für diesen Wechsel eine neue Kennung. Dann geht
/// die alte aus, und die neue blendet an ihrem Platz ein.
///
/// Die Kennung bleibt, bis der nächste Wechsel sie ändert — sonst blendete
/// eine Zeile beim nächsten Zeichnen ein zweites Mal.
public struct Zeilenkennungen: Sendable, Equatable {
    private var kennungen: [String: String] = [:]
    private var runde = 0

    public init() {}

    /// Die Kennung, unter der die Zeile gerade steht.
    public func kennung(_ id: String) -> String { kennungen[id] ?? id }

    /// Rechnet die Kennungen für den Wechsel von `alt` nach `neu`.
    ///
    /// - `vorAlt`, `vorNeu`: Zeilen über der Liste (angeheftete), in Zeilen.
    /// - `sichtbar`: wie viele Zeilen auf den Schirm passen. `0` heißt: die
    ///   Liste war gescrollt und springt nach oben — dann zieht nichts, es
    ///   wird nur überblendet.
    public mutating func wechsel(von alt: [String], nach neu: [String],
                                 vorAlt: Int = 0, vorNeu: Int = 0, sichtbar: Int) {
        runde += 1
        var altePlaetze: [String: Int] = [:]
        altePlaetze.reserveCapacity(alt.count)
        for (i, id) in alt.enumerated() { altePlaetze[id] = i + vorAlt }
        let weiteste = max(1, sichtbar / 2)
        var naechste: [String: String] = [:]
        naechste.reserveCapacity(neu.count)
        for (j, id) in neu.enumerated() {
            let bisher = kennung(id)
            guard let i = altePlaetze[id] else {
                // Neu in der Liste: blendet ohnehin ein.
                if bisher != id { naechste[id] = bisher }
                continue
            }
            let n = j + vorNeu
            let beideDraussen = i >= sichtbar && n >= sichtbar
            let ziehen = sichtbar > 0
                && (beideDraussen || (i < sichtbar && n < sichtbar && abs(i - n) <= weiteste))
            let k = ziehen ? bisher : "\(id)#\(runde)"
            if k != id { naechste[id] = k }
        }
        kennungen = naechste
    }
}
