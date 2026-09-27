import Foundation

/// **Ein Eintrag der Bibliothek** — Playlist, Album, Künstler oder Lied in
/// einer gemeinsamen Liste, wie bei Spotify.
public enum Bibliothekseintrag: Identifiable, Hashable, Sendable {
    case playlist(Playlist)
    case album(Album)
    case kuenstler(Kuenstler)
    case lied(Lied)

    public var id: String {
        switch self {
        case let .playlist(p): "playlist:\(p.id)"
        case let .album(a): "album:\(a.id)"
        case let .kuenstler(k): "kuenstler:\(k.id)"
        case let .lied(l): "lied:\(l.id)"
        }
    }

    public var name: String {
        switch self {
        case let .playlist(p): p.name
        case let .album(a): a.titel
        case let .kuenstler(k): k.name
        case let .lied(l): l.titel
        }
    }

    /// Wann es dazukam, soweit der Server es sagt.
    public var hinzugefuegt: Date? {
        switch self {
        case let .playlist(p): p.geaendert
        case let .album(a): a.hinzugefuegt
        case .kuenstler, .lied: nil
        }
    }

    /// Wann zuletzt gespielt, soweit der Server es sagt.
    public var gespielt: Date? {
        if case let .album(a) = self { return a.zuletztGespielt }
        return nil
    }
}

public enum Bibliothekssortierung: String, CaseIterable, Sendable, Codable {
    case zuletztGespielt, zuletztHinzugefuegt, name
}

/// **Die Reihenfolge der Bibliothek.**
///
/// „Zuletzt gespielt": was je gespielt wurde, neueste zuerst — nach der
/// Zeit vom Server oder vom Gerät, die spätere gilt —, danach der Rest nach
/// Namen. „Zuletzt hinzugefügt": neueste zuerst, ohne Datum nach Namen.
/// „A–Z": nach Namen, wie Menschen sortieren („10" nach „9").
public enum Bibliotheksordnung {
    public static func ordnen(_ eintraege: [Bibliothekseintrag], nach sortierung: Bibliothekssortierung,
                              gespielt aufDemGeraet: [String: Date] = [:]) -> [Bibliothekseintrag] {
        func nachName(_ a: Bibliothekseintrag, _ b: Bibliothekseintrag) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        switch sortierung {
        case .name:
            return eintraege.sorted(by: nachName)
        case .zuletztHinzugefuegt:
            return eintraege.sorted { a, b in
                switch (a.hinzugefuegt, b.hinzugefuegt) {
                case let (x?, y?) where x != y: x > y
                case (.some, nil): true
                case (nil, .some): false
                default: nachName(a, b)
                }
            }
        case .zuletztGespielt:
            func zeit(_ e: Bibliothekseintrag) -> Date? {
                [e.gespielt, aufDemGeraet[e.id]].compactMap { $0 }.max()
            }
            return eintraege.sorted { a, b in
                switch (zeit(a), zeit(b)) {
                case let (x?, y?) where x != y: x > y
                case (.some, nil): true
                case (nil, .some): false
                default: nachName(a, b)
                }
            }
        }
    }
}

/// **Die geordnete Bibliothek nach Art aufgeteilt** — in einem Durchgang,
/// ohne neu zu sortieren: jede Art behält die Reihenfolge der ganzen Liste.
/// Einmal nach dem Laden gerechnet, danach ist der Wechsel einer Kapsel nur
/// noch ein Nachschlagen.
public struct Bibliotheksfaecher: Sendable {
    public private(set) var playlists: [Bibliothekseintrag] = []
    public private(set) var alben: [Bibliothekseintrag] = []
    public private(set) var kuenstler: [Bibliothekseintrag] = []
    public private(set) var lieder: [Bibliothekseintrag] = []

    public init() {}

    public init(_ eintraege: [Bibliothekseintrag]) {
        for e in eintraege {
            switch e {
            case .playlist: playlists.append(e)
            case .album: alben.append(e)
            case .kuenstler: kuenstler.append(e)
            case .lied: lieder.append(e)
            }
        }
    }
}
