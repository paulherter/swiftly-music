import Foundation

/// **Mehrere Künstler als Liste, nicht als roher Tag.**
///
/// Ein Lied mit Gästen trägt oft einen einzigen Tag wie
/// „Ikkimel;nocashfromparents;Florida Juicy". Jellyfin zerlegt ihn nur, wenn
/// die Bibliothek so eingestellt ist, und liefert sonst genau diesen Text als
/// einzigen Namen in `Artists`. OpenSubsonic kennt `artists`, ältere Server
/// nur `artist`. Deshalb: die Liste des Servers nehmen, jeden Eintrag noch
/// einmal an `;` und ` / ` zerlegen, Doppelte streichen.
///
/// ` / ` nur mit Leerzeichen — „AC/DC" bleibt ein Name.
public enum Kuenstlernamen {

    /// Zerlegt einen Tag in Namen.
    public static func zerlegen(_ roh: String) -> [String] {
        roh.components(separatedBy: ";")
            .flatMap { $0.components(separatedBy: " / ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Die Namen einer Liste, jeder zerlegt, ohne Doppelte, in ihrer Folge.
    public static func liste(_ namen: [String]) -> [String] {
        var gesehen = Set<String>()
        var ergebnis: [String] = []
        for name in namen.flatMap(zerlegen) where gesehen.insert(name.lowercased()).inserted {
            ergebnis.append(name)
        }
        return ergebnis
    }

    /// **„A, B und C"** — im Englischen „A, B, and C", wie die Sprache es
    /// schreibt (`ListFormatter`). `nil` ohne Namen.
    public static func zeile(_ namen: [String], sprache: Locale = .current) -> String? {
        guard !namen.isEmpty else { return nil }
        guard namen.count > 1 else { return namen[0] }
        let formatierer = ListFormatter()
        formatierer.locale = sprache
        return formatierer.string(from: namen) ?? namen.joined(separator: ", ")
    }

    /// Ob zwei Listen dieselben Künstler nennen, gleich in welcher Folge.
    public static func gleich(_ a: [String], _ b: [String]) -> Bool {
        Set(a.map { $0.lowercased() }) == Set(b.map { $0.lowercased() })
    }
}

extension Lied {
    /// Die Künstler dieses Liedes — aus der Liste des Servers, sonst aus der
    /// Zeile zerlegt (auch für Lieder, die vor der Liste abgelegt wurden).
    public var kuenstlernamen: [String] {
        let aus = kuenstlerliste.isEmpty ? [kuenstler].compactMap { $0 } : kuenstlerliste
        return Kuenstlernamen.liste(aus)
    }
}

extension Album {
    public var kuenstlernamen: [String] {
        let aus = kuenstlerliste.isEmpty ? [kuenstler].compactMap { $0 } : kuenstlerliste
        return Kuenstlernamen.liste(aus)
    }
}
