import Foundation

/// **Album, EP oder Single — auch ohne Angabe vom Server.**
///
/// Bei Jellyfin wird jedes einzelne Lied, das in keinem Album liegt, als
/// eigenes „Album" geführt; „Zuletzt gehört" und „Zuletzt hinzugefügt" sind
/// dann voller Ein-Lied-Alben. Sagt der Server selbst, was es ist (Subsonic
/// `releaseTypes`), gilt das — ein sauber getaggter Server bleibt, wie er
/// ist. Sonst entscheidet diese Regel:
///
/// - „… - Single", „(Single)", „[Single]" im Titel → Single; ebenso „EP".
/// - Ein Lied, oder das einzige Lied heißt wie das Album → Single.
/// - Zwei bis sechs Lieder unter 30 Minuten → EP.
/// - Sonst ein Album.
public enum Veroeffentlichung {

    public static func art(_ album: Album, liedtitel: [String] = []) -> Albumart {
        if let art = album.art { return art }
        let titel = album.titel.lowercased().trimmingCharacters(in: .whitespaces)
        if hatZusatz(titel, "single") { return .single }
        if hatZusatz(titel, "ep") { return .ep }
        let zahl = album.liedzahl ?? (liedtitel.isEmpty ? nil : liedtitel.count)
        if zahl == 1 { return .single }
        if let erstes = liedtitel.first, zahl ?? 0 <= 3,
           erstes.lowercased().trimmingCharacters(in: .whitespaces) == titel {
            return .single
        }
        if let zahl, (2 ... 6).contains(zahl), let dauer = album.dauer, dauer < 30 * 60 { return .ep }
        return .album
    }

    /// Ob ein Album eigentlich eine Single ist.
    public static func istSingle(_ album: Album) -> Bool { art(album) == .single }

    /// „… - single", „… (single)", „… [single]".
    static func hatZusatz(_ titel: String, _ wort: String) -> Bool {
        titel.hasSuffix(" - \(wort)") || titel.hasSuffix("(\(wort))") || titel.hasSuffix("[\(wort)]")
            || titel.hasSuffix(" – \(wort)")
    }

    /// Namen, die ein Server für „kein Künstler" einsetzt — sie zählen nicht.
    public static func istPlatzhalter(_ name: String) -> Bool {
        ["unknown artist", "unbekannter künstler", "unknown", "unbekannt", "[unknown]", "various"]
            .contains(name.lowercased().trimmingCharacters(in: .whitespaces))
    }
}

/// **Singles desselben Künstlers vom selben Tag, zusammengefasst** — für
/// „Zuletzt gehört" und „Zuletzt hinzugefügt". Aus drei Singles wird eine
/// Kachel „3 Singles" an der Stelle der ersten.
public enum Buendel<T: Sendable>: Sendable {
    case einzeln(T)
    case singles(kuenstler: String, kuenstlerID: String?, [T])
}

extension Buendel: Identifiable where T: Identifiable, T.ID == String {
    public var id: String {
        switch self {
        case let .einzeln(t): t.id
        case let .singles(k, _, liste): "singles:\(k):\(liste.first?.id ?? "")"
        }
    }
}

public enum Singlebuendel {
    public static func buendeln<T: Sendable>(_ posten: [T], single: (T) -> Bool,
                                             kuenstler: (T) -> (name: String, id: String?)?,
                                             tag: (T) -> Date?,
                                             kalender: Calendar = .current) -> [Buendel<T>] {
        // Erst die Gruppen: Künstler und Tag.
        var gruppen: [String: [Int]] = [:]
        for (i, p) in posten.enumerated() where single(p) {
            guard let k = kuenstler(p), let t = tag(p) else { continue }
            let tagkennung = kalender.startOfDay(for: t).timeIntervalSince1970
            gruppen["\(k.name.lowercased())|\(tagkennung)", default: []].append(i)
        }
        var verbraucht = Set<Int>()
        var ergebnis: [Buendel<T>] = []
        for (i, p) in posten.enumerated() where !verbraucht.contains(i) {
            if single(p), let k = kuenstler(p), let t = tag(p),
               let gruppe = gruppen["\(k.name.lowercased())|\(kalender.startOfDay(for: t).timeIntervalSince1970)"],
               gruppe.count > 1 {
                verbraucht.formUnion(gruppe)
                ergebnis.append(.singles(kuenstler: k.name, kuenstlerID: k.id, gruppe.map { posten[$0] }))
            } else {
                ergebnis.append(.einzeln(p))
            }
        }
        return ergebnis
    }
}
