import Foundation

/// **Wie laut ein Lied im Verhältnis sein soll** — ReplayGain bzw. Jellyfins
/// `NormalizationGain`, in Dezibel.
///
/// Jellyfin misst je Lied und je Album auf −18 LUFS; OpenSubsonic liefert
/// `replayGain` mit Lied- und Albumwert samt Spitzenpegel. Ohne Angabe bleibt
/// das Lied, wie es ist.
public struct Lautheit: Hashable, Sendable, Codable {
    /// dB, um die das Lied angehoben (+) oder abgesenkt (−) werden soll.
    public var lied: Double?
    public var album: Double?
    /// Spitzenpegel 0…1 (linear), falls bekannt — damit Anheben nicht
    /// übersteuert.
    public var liedspitze: Double?
    public var albumspitze: Double?

    public init(lied: Double? = nil, album: Double? = nil, liedspitze: Double? = nil, albumspitze: Double? = nil) {
        self.lied = lied
        self.album = album
        self.liedspitze = liedspitze
        self.albumspitze = albumspitze
    }

    public var istLeer: Bool { lied == nil && album == nil }
}

/// **Aus dem Pegel wird eine Lautstärke.**
///
/// Das Vorgehen wie in Finamp: iOS hat keine Lautheits-Einheit im Player,
/// also bekommt der Player selbst die Lautstärke `10^(dB/20)`. Mehr als 1
/// geht dort nicht — ein leises Lied wird nicht lauter, ein lautes leiser.
/// Das ist der Teil, der beim Hören zählt: kein Sprung, wenn nach einem
/// ruhigen Album ein gemastertes Stück kommt.
public enum Lautheitsregel {

    /// Albumweise, wenn ein Album in seiner Reihenfolge läuft — dann bleibt
    /// der Abstand zwischen leisen und lauten Stücken, wie er gemeint ist.
    /// Sonst liedweise. Fehlt der gewünschte Wert, gilt der andere.
    public static func pegel(_ l: Lautheit?, albumweise: Bool) -> (dB: Double, spitze: Double?)? {
        guard let l else { return nil }
        if albumweise, let a = l.album { return (a, l.albumspitze ?? l.liedspitze) }
        if let t = l.lied { return (t, l.liedspitze) }
        if let a = l.album { return (a, l.albumspitze) }
        return nil
    }

    /// Die Lautstärke für den Player, 0…1.
    public static func lautstaerke(_ l: Lautheit?, albumweise: Bool) -> Float {
        guard let (dB, spitze) = pegel(l, albumweise: albumweise), dB.isFinite else { return 1 }
        var faktor = pow(10, dB / 20)
        // Mit bekanntem Spitzenpegel nie über die Vollaussteuerung.
        if let spitze, spitze > 0 { faktor = min(faktor, 1 / spitze) }
        return Float(min(max(faktor, 0.05), 1))
    }
}
