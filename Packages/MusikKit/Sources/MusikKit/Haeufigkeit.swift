import Foundation

/// Werte nach Häufigkeit, bei Gleichstand in der Reihenfolge ihres ersten
/// Auftretens — für das Genre eines Künstlers aus seinen Alben und den
/// Künstler, der eine Playlist trägt.
public enum Haeufigkeit {
    public static func ordnen(_ werte: [String]) -> [String] {
        var zahl: [String: Int] = [:]
        var erste: [String: Int] = [:]
        for (i, w) in werte.enumerated() where !w.isEmpty {
            zahl[w, default: 0] += 1
            if erste[w] == nil { erste[w] = i }
        }
        return zahl.keys.sorted { a, b in
            zahl[a]! != zahl[b]! ? zahl[a]! > zahl[b]! : erste[a]! < erste[b]!
        }
    }
}
