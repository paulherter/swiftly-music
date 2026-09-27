import Foundation

/// **Nachsichtig lesen.** Subsonic ist eine Schnittstelle mit vielen
/// Umsetzungen, und nicht jede schreibt dieselben Typen: Kennungen kommen bei
/// Navidrome als Text, bei älteren Servern als Zahl; Zahlen stehen mal in
/// Anführungszeichen; leere Listen fehlen ganz. Ein erzeugter Decoder würde an
/// jeder dieser Stellen die **ganze Antwort** verwerfen — ein falsch
/// geschriebenes Jahr nähme das Album mit.
///
/// Deshalb liest jedes Modell seine Felder einzeln über diese Helfer. Was
/// nicht passt, fehlt; nur eine fehlende Kennung lässt einen Eintrag fallen.
struct Feld: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ name: String) { stringValue = name }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer where Key == Feld {

    /// Text — auch aus einer Zahl.
    func text(_ name: String) -> String? {
        let k = Feld(name)
        if let s = try? decodeIfPresent(String.self, forKey: k) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: k) {
            return d.rounded() == d ? String(Int(d)) : String(d)
        }
        return nil
    }

    /// Ganze Zahl — auch aus Text oder einer Kommazahl.
    func zahl(_ name: String) -> Int? {
        let k = Feld(name)
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: k), d.isFinite,
           abs(d) < Double(Int.max) {
            return Int(d.rounded())
        }
        if let s = try? decodeIfPresent(String.self, forKey: k) {
            return Int(s.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    func kommazahl(_ name: String) -> Double? {
        let k = Feld(name)
        if let d = try? decodeIfPresent(Double.self, forKey: k) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return Double(s) }
        return nil
    }

    func wahr(_ name: String) -> Bool? {
        let k = Feld(name)
        if let b = try? decodeIfPresent(Bool.self, forKey: k) { return b }
        if let s = try? decodeIfPresent(String.self, forKey: k) {
            switch s.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return i != 0 }
        return nil
    }

    func zeit(_ name: String) -> Date? {
        text(name).flatMap(Zeitangabe.lesen)
    }

    /// Eine Liste, deren kaputte Einträge einzeln herausfallen. Fehlt der
    /// Schlüssel ganz, ist sie leer — so schreiben Server eine leere Liste oft.
    ///
    /// Manche Server schreiben einen einzelnen Eintrag als Objekt statt als
    /// Liste mit einem Element (ein Rest aus der XML-Übersetzung); auch das
    /// wird hier zur Liste.
    func liste<T: Decodable>(_ name: String, _ typ: T.Type = T.self) -> [T] {
        let k = Feld(name)
        if let viele = try? decodeIfPresent([Nachsichtig<T>].self, forKey: k) {
            return viele.compactMap(\.wert)
        }
        if let einer = try? decodeIfPresent(T.self, forKey: k) { return [einer] }
        return []
    }

    /// Namen aus einer Liste von `{ "name": … }` — so schreibt OpenSubsonic
    /// Genres und Stimmungen.
    func namen(_ name: String) -> [String] {
        liste(name, Benannt.self).map(\.name).filter { !$0.isEmpty }
    }
}

/// Ein Listeneintrag, der beim Lesen nicht wirft.
struct Nachsichtig<T: Decodable>: Decodable {
    let wert: T?
    init(from decoder: any Decoder) throws {
        wert = try? T(from: decoder)
    }
}

struct Benannt: Decodable {
    let name: String
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Feld.self)
        name = c.text("name") ?? ""
    }
}

/// Wird geworfen, wenn einem Eintrag die Kennung fehlt — dann taugt er nicht.
struct OhneKennung: Error {}

/// **Zeitangaben nach ISO 8601, so wie Server sie wirklich schreiben.**
///
/// Navidrome schreibt Nanosekunden (`2026-09-23T09:53:46.606867295Z`), ältere
/// Server Millisekunden oder gar keine Nachkommastellen, manche lassen die
/// Zone weg. `ISO8601DateFormatter` scheitert an den neun Stellen, deshalb
/// hier von Hand: Datum und Uhrzeit fest, Bruchteil beliebig lang, Zone
/// wahlweise `Z`, `±hh:mm` oder `±hhmm` — ohne Zone gilt UTC.
public enum Zeitangabe {

    public static func lesen(_ text: String) -> Date? {
        let z = Array(text.trimmingCharacters(in: .whitespaces).utf8)
        guard z.count >= 19 else { return nil }

        func ziffern(_ von: Int, _ bis: Int) -> Int? {
            var wert = 0
            for i in von ..< bis {
                guard i < z.count, z[i] >= 48, z[i] <= 57 else { return nil }
                wert = wert * 10 + Int(z[i] - 48)
            }
            return wert
        }

        guard let jahr = ziffern(0, 4), z[4] == 45,          // -
              let monat = ziffern(5, 7), z[7] == 45,
              let tag = ziffern(8, 10), z[10] == 84 || z[10] == 32,   // T oder Leerzeichen
              let stunde = ziffern(11, 13), z[13] == 58,     // :
              let minute = ziffern(14, 16), z[16] == 58,
              let sekunde = ziffern(17, 19)
        else { return nil }

        var i = 19
        var bruch = 0.0
        if i < z.count, z[i] == 46 {                         // .
            i += 1
            var stelle = 0.1
            while i < z.count, z[i] >= 48, z[i] <= 57 {
                bruch += Double(z[i] - 48) * stelle
                stelle /= 10
                i += 1
            }
        }

        var versatz = 0
        if i < z.count {
            switch z[i] {
            case 90, 122:                                    // Z, z
                break
            case 43, 45:                                     // +, -
                let vorzeichen = z[i] == 45 ? -1 : 1
                guard let h = ziffern(i + 1, i + 3) else { return nil }
                var m = 0
                if i + 3 < z.count {
                    if z[i + 3] == 58 {
                        guard let mm = ziffern(i + 4, i + 6) else { return nil }
                        m = mm
                    } else if let mm = ziffern(i + 3, i + 5) {
                        m = mm
                    }
                }
                versatz = vorzeichen * (h * 3600 + m * 60)
            default:
                return nil
            }
        }

        var kalender = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else { return nil }
        kalender.timeZone = utc
        var teile = DateComponents()
        teile.year = jahr
        teile.month = monat
        teile.day = tag
        teile.hour = stunde
        teile.minute = minute
        teile.second = sekunde
        guard let basis = kalender.date(from: teile) else { return nil }
        return basis.addingTimeInterval(bruch - Double(versatz))
    }
}
