import Foundation

/// **Die Stelle je Bild, nicht je Meldung.**
///
/// Der Player meldet seine Stelle nur alle halbe Sekunde, ein anderes Gerät
/// noch seltener. Hing die Anzeige daran, sprangen Spur und Griffpunkt ruckweise
/// weiter (24.09.). Die Uhr rechnet dazwischen hoch — letzte Meldung plus
/// Rate mal vergangene Zeit — und die Meldungen korrigieren nur noch:
///
/// - **Kleine Abweichungen gleiten** (unter ``sprungschwelle``): die Differenz
///   klingt über ``angleich`` Sekunden ab, nie so schnell, dass die Anzeige
///   rückwärts liefe, solange es spielt.
/// - **Große Abweichungen springen** — das ist ein Sprung im Lied, ein
///   Liedwechsel oder ein anderes Gerät, das weit weg ist.
/// - **Pause steht sofort**: die Anzeige bleibt, wo sie gerade ist.
///
/// Die Zeit kommt von außen (`jetzt`, monoton, in Sekunden), damit die Uhr
/// ohne echten Takt geprüft werden kann. Ein Werttyp, gerechnet wird nur,
/// wenn jemand fragt.
public struct Stellenuhr: Sendable, Equatable {
    /// Darüber wird gesprungen statt geglitten.
    public static let sprungschwelle: TimeInterval = 1.0
    /// So lange gleitet eine kleine Abweichung wenigstens aus.
    public static let angleich: TimeInterval = 0.4

    /// Die gemeldete Stelle und wann sie galt.
    public private(set) var anker: TimeInterval = 0
    public private(set) var ankerzeit: TimeInterval = 0
    /// 0 in der Pause und beim Puffern, sonst die Abspielrate (meist 1).
    public private(set) var rate: Double = 0
    /// Was die Anzeige bei der letzten Meldung von ihr abwich — klingt ab.
    private var abweichung: TimeInterval = 0
    private var abklingen: TimeInterval = Self.angleich

    public init() {}

    /// Die Stelle, die jetzt gezeigt wird.
    public func stelle(jetzt: TimeInterval) -> TimeInterval {
        let dt = max(0, jetzt - ankerzeit)
        let rest = abweichung * max(0, 1 - dt / abklingen)
        return max(0, anker + rate * dt + rest)
    }

    /// **Eine Meldung vom Player**: die Stelle und die Rate, mit der es
    /// gerade läuft (0 = steht). Kleine Abweichungen gleiten, große springen.
    public mutating func melden(_ gemeldet: TimeInterval, rate neueRate: Double, jetzt: TimeInterval) {
        let gezeigt = stelle(jetzt: jetzt)
        let differenz = gezeigt - gemeldet
        anker = max(0, gemeldet)
        ankerzeit = jetzt
        rate = max(0, neueRate)
        if abs(differenz) < Self.sprungschwelle, differenz != 0 {
            abweichung = differenz
            // Nie rückwärts: holt die Anzeige auf, darf sie höchstens halb so
            // schnell zurückbleiben, wie es läuft. Steht es, gleitet sie in
            // der kürzesten Zeit.
            abklingen = rate > 0 ? max(Self.angleich, abs(differenz) * 2 / rate) : Self.angleich
        } else {
            abweichung = 0
        }
        if rate == 0, abs(differenz) < Self.sprungschwelle {
            // **In der Pause steht die Anzeige, wo sie war** — die kleine
            // Abweichung holt das nächste Abspielen weich nach. Ein Sprung im
            // Lied gilt auch in der Pause.
            anker = gezeigt
            abweichung = 0
        }
    }

    /// **Anhalten**: sofort stehen, an der Stelle, die gerade zu sehen ist.
    public mutating func anhalten(jetzt: TimeInterval) {
        anker = stelle(jetzt: jetzt)
        ankerzeit = jetzt
        rate = 0
        abweichung = 0
    }

    /// **Setzen** — ein Sprung, ein neues Lied: ohne Gleiten dorthin.
    public mutating func setzen(_ neu: TimeInterval, rate neueRate: Double, jetzt: TimeInterval) {
        anker = max(0, neu)
        ankerzeit = jetzt
        rate = max(0, neueRate)
        abweichung = 0
    }
}
