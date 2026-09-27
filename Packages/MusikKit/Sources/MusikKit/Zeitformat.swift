import Foundation

/// **Zeiten, wie sie in Listen und unter der Spur stehen.**
///
/// `4:07` in der Liedliste, `1:38` und `−2:29` unter der Spur, `1:02:15`
/// ab einer Stunde. Die Zahlen stehen tabellarisch untereinander; die App
/// setzt dafür `monospacedDigit()`, hier geht es nur um den Text.
public enum Zeitformat {

    /// `m:ss`, ab einer Stunde `h:mm:ss`. Negative und kaputte Werte als 0.
    public static func dauer(_ sekunden: TimeInterval) -> String {
        let s = sekunden.isFinite ? max(0, Int(sekunden.rounded(.down))) : 0
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        if h > 0 { return "\(h):\(zwei(m)):\(zwei(r))" }
        return "\(m):\(zwei(r))"
    }

    /// Die Restzeit mit echtem Minuszeichen (U+2212), wie im Entwurf: `−2:29`.
    public static func rest(_ sekunden: TimeInterval) -> String {
        "\u{2212}" + dauer(sekunden.rounded(.up))
    }

    /// Ganze Minuten für „41 Min." — gerundet, aber nie 0 bei einem Lied.
    public static func minuten(_ sekunden: TimeInterval) -> Int {
        guard sekunden.isFinite, sekunden > 0 else { return 0 }
        return max(1, Int((sekunden / 60).rounded()))
    }

    /// **Zum Vorlesen**: „3 Minuten, 45 Sekunden" statt „3:45" — VoiceOver
    /// liest Doppelpunkte als Doppelpunkte (`Zeitregler.gesprochen` im
    /// Player). Anders als dort mit Sekunden, denn ein Lied ist kurz, und in
    /// der Sprache des Geräts.
    public static func gesprochen(_ sekunden: TimeInterval, locale: Locale = .current) -> String {
        let s = sekunden.isFinite ? max(0, Int(sekunden.rounded(.down))) : 0
        var kalender = Calendar(identifier: .gregorian)
        kalender.locale = locale
        let format = DateComponentsFormatter()
        format.calendar = kalender
        format.unitsStyle = .full
        format.allowedUnits = s >= 3600 ? [.hour, .minute] : [.minute, .second]
        format.zeroFormattingBehavior = .dropLeading
        return format.string(from: TimeInterval(s)) ?? dauer(sekunden)
    }

    private static func zwei(_ zahl: Int) -> String {
        zahl < 10 ? "0\(zahl)" : "\(zahl)"
    }
}
