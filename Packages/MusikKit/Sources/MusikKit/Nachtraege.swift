import Foundation

/// **Was gehört wurde, während der Server nicht erreichbar war.**
///
/// Eine Wiedergabemeldung ohne Netz ging vorher verloren. Jetzt wird sie
/// gemerkt und nachgeschickt, sobald das Netz wieder da ist — mit dem
/// Zeitpunkt, an dem das Lied lief (Amperfys `ScrobbleSyncer`).
public struct Nachtrag: Codable, Sendable, Hashable {
    public let liedID: String
    public let titel: String
    /// Wann das Lied anfing.
    public let zeit: Date

    public init(liedID: String, titel: String, zeit: Date) {
        self.liedID = liedID
        self.titel = titel
        self.zeit = zeit
    }
}

public struct Nachtragsliste: Codable, Sendable, Equatable {
    public private(set) var eintraege: [Nachtrag] = []
    /// Mehr hebt niemand auf — wer ein Jahr offline hört, verliert die
    /// ältesten, nicht die App ihren Speicher.
    public static let hoechstens = 500

    public init() {}

    public var istLeer: Bool { eintraege.isEmpty }

    /// Merkt einen Nachtrag; derselbe Lauf desselben Liedes nur einmal.
    public mutating func merken(_ n: Nachtrag) {
        guard !eintraege.contains(n) else { return }
        eintraege.append(n)
        eintraege.sort { $0.zeit < $1.zeit }
        if eintraege.count > Self.hoechstens { eintraege.removeFirst(eintraege.count - Self.hoechstens) }
    }

    public mutating func erledigt(_ n: Nachtrag) {
        eintraege.removeAll { $0 == n }
    }
}
