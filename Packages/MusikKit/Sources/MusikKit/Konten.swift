import Foundation
import JellyfinKit
import SubsonicKit

// MARK: - Mehrere Konten

/// Ein gespeichertes Konto, gleich welcher Server — die App legt ihre
/// Anmeldung (Merkmal oder Zugang) darin ab; hier zählt nur, wem sie gehört.
public protocol Kontoeintrag: Codable, Sendable, Equatable {
    var kontokennung: Kontokennung { get }
}

extension Kontokennung {
    /// **Wann zwei Anmeldungen dasselbe Konto sind**: derselbe Server (Groß-
    /// und Kleinschreibung und ein Schrägstrich am Ende zählen nicht) und
    /// derselbe Benutzer — wie `Session.kontoschluessel` in JellyfinKit.
    public var schluessel: String {
        var server = self.server.absoluteString.lowercased()
        while server.hasSuffix("/") { server.removeLast() }
        return server + "|" + benutzerID
    }
}

/// **Mehrere Konten, auch auf verschiedenen Servern, und welches gilt** —
/// dieselben Regeln wie `Kontenbund` im Player (JellyfinKit), nur für
/// Jellyfin und Subsonic zugleich.
///
/// Warum ein eigener Typ: meldet sich dasselbe Konto ein zweites Mal an, darf
/// es nicht doppelt dastehen; wird das aktive entfernt, muss ein anderes
/// gelten; und die alte Einzelanmeldung von vor dieser Fassung muss als
/// erstes Konto weiterleben. Jede dieser Regeln ist hier ohne Simulator
/// geprüft (`KontenTests`).
public struct Kontenreihe<Eintrag: Kontoeintrag>: Codable, Sendable, Equatable {

    /// In der Reihenfolge, in der sie dazukamen.
    public private(set) var konten: [Eintrag]
    private var aktiverSchluessel: String

    /// Das Konto, mit dem die App gerade angemeldet ist. Zeigt der Zeiger ins
    /// Leere, gilt das erste — eine Reihe ohne aktives Konto gibt es nicht.
    public var aktives: Eintrag {
        konten.first { $0.kontokennung.schluessel == aktiverSchluessel } ?? konten[0]
    }

    /// Die übrigen, in ihrer Reihenfolge.
    public var andere: [Eintrag] {
        let aktiv = aktives.kontokennung.schluessel
        return konten.filter { $0.kontokennung.schluessel != aktiv }
    }

    public init(_ erstes: Eintrag) {
        konten = [erstes]
        aktiverSchluessel = erstes.kontokennung.schluessel
    }

    /// Aus gespeicherten Werten; `nil`, wenn nichts da ist.
    public init?(konten: [Eintrag], aktiv: Kontokennung?) {
        guard !konten.isEmpty else { return nil }
        self.konten = konten
        aktiverSchluessel = aktiv?.schluessel ?? konten[0].kontokennung.schluessel
    }

    /// **Ein Konto aufnehmen und zum aktiven machen.** Ist es schon da,
    /// ersetzt die neue Anmeldung die alte an ihrer Stelle — ein neues
    /// Merkmal, ein geänderter Servername.
    public mutating func aufnehmen(_ neu: Eintrag) {
        let schluessel = neu.kontokennung.schluessel
        if let i = konten.firstIndex(where: { $0.kontokennung.schluessel == schluessel }) {
            konten[i] = neu
        } else {
            konten.append(neu)
        }
        aktiverSchluessel = schluessel
    }

    /// Eine Reihe aus dem, was da war, und dem neuen Konto.
    public static func aufgenommen(_ neu: Eintrag, in vorhanden: Kontenreihe?) -> Kontenreihe {
        guard var reihe = vorhanden else { return Kontenreihe(neu) }
        reihe.aufnehmen(neu)
        return reihe
    }

    /// Zu einem Konto wechseln, das es gibt. Ein unbekanntes ändert nichts.
    public mutating func wechseln(zu kennung: Kontokennung) {
        guard konten.contains(where: { $0.kontokennung.schluessel == kennung.schluessel }) else { return }
        aktiverSchluessel = kennung.schluessel
    }

    /// **Ohne dieses Konto** — `nil`, wenn keins übrig bleibt. War es das
    /// aktive, gilt das nächste in der Reihe, sonst das letzte davor.
    public func entfernt(_ kennung: Kontokennung) -> Kontenreihe? {
        guard let i = konten.firstIndex(where: { $0.kontokennung.schluessel == kennung.schluessel }) else {
            return self
        }
        var rest = konten
        rest.remove(at: i)
        guard !rest.isEmpty else { return nil }
        let warAktiv = kennung.schluessel == aktives.kontokennung.schluessel
        let neu = warAktiv ? rest[min(i, rest.count - 1)].kontokennung : aktives.kontokennung
        return Kontenreihe(konten: rest, aktiv: neu)
    }

    /// **Die Ablage lesen**, die neue Reihe oder die einzelne Anmeldung von
    /// vorher. Fällt die Reihe beim Lesen durch, zählt die einzelne — lieber
    /// ein Konto als der Anmeldeschirm (die Lehre aus
    /// `Kontenbund.ausAlterGtkAblage`).
    public static func ausAblage(reihe: Data?, einzelne: Data?) -> Kontenreihe? {
        let leser = JSONDecoder()
        if let reihe, let r = try? leser.decode(Kontenreihe.self, from: reihe), !r.konten.isEmpty {
            return r
        }
        guard let einzelne, let alt = try? leser.decode(Eintrag.self, from: einzelne) else { return nil }
        return Kontenreihe(alt)
    }

    private enum K: String, CodingKey { case konten, aktiv }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        // Ein Eintrag, der sich nicht lesen lässt, kostet nur sich selbst.
        let roh = try c.decode([Ueberspringbar<Eintrag>].self, forKey: .konten)
        konten = roh.compactMap(\.wert)
        aktiverSchluessel = (try? c.decode(String.self, forKey: .aktiv)) ?? ""
        if konten.isEmpty {
            throw DecodingError.dataCorruptedError(forKey: .konten, in: c, debugDescription: "keine Konten")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(konten, forKey: .konten)
        try c.encode(aktives.kontokennung.schluessel, forKey: .aktiv)
    }
}

private struct Ueberspringbar<Wert: Decodable>: Decodable {
    let wert: Wert?
    init(from decoder: any Decoder) throws {
        wert = try? Wert(from: decoder)
    }
}

// MARK: - Gilt die Anmeldung noch?

/// **Was der Server zur gespeicherten Anmeldung sagt.** Wie
/// `JellyfinClient.sitzungGiltNoch()` im Player: nur eine ausdrückliche
/// Ablehnung heißt „gilt nicht", ein Netzfehler heißt „weiß nicht" — deswegen
/// jemanden abzumelden, der im Flugzeug seine geladene Musik hört, wäre falsch.
public enum Anmeldestand: Sendable, Equatable {
    case gilt
    case giltNicht
    case unbekannt

    /// Ein HTTP-Status: nur 401 und 403 lehnen ab.
    public static func aus(status: Int) -> Anmeldestand {
        switch status {
        case 401, 403: .giltNicht
        case 200..<300: .gilt
        default: .unbekannt
        }
    }

    /// Ein Fehler beim Prüfen. Subsonic antwortet mit Code 40 (Name oder
    /// Passwort) oder 44 (Token ungültig); Jellyfin mit dem HTTP-Status.
    public static func aus(fehler: any Error) -> Anmeldestand {
        if let s = fehler as? SubsonicFehler {
            switch s {
            case .server(code: 40, _), .server(code: 44, _): return .giltNicht
            case let .http(status): return aus(status: status)
            default: return .unbekannt
            }
        }
        if let j = fehler as? JellyfinError {
            switch j {
            case let .http(status, _): return aus(status: status)
            default: return .unbekannt
            }
        }
        return .unbekannt
    }
}
