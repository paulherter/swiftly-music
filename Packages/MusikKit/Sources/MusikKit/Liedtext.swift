import Foundation

/// **Ein Liedtext, getaktet oder nicht.**
///
/// Getaktet heißt: jede Zeile trägt die Stelle, an der sie gesungen wird.
/// Dann folgt die Ansicht der Wiedergabe, und ein Tipp auf eine Zeile springt
/// dorthin. Ungetaktet steht der Text einfach da.
public struct Liedtext: Sendable, Hashable {

    public struct Zeile: Sendable, Hashable {
        /// Sekunden ab Liedbeginn, schon um jeden Versatz bereinigt.
        public let zeit: TimeInterval?
        public let text: String

        public init(zeit: TimeInterval?, text: String) {
            self.zeit = zeit
            self.text = text
        }

        /// Eine Zeile ohne Text — eine Pause zwischen zwei Strophen.
        public var istPause: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public let zeilen: [Zeile]

    /// Getaktete Zeilen stehen nach Zeit geordnet; eine Zeile ohne Zeit in
    /// einem getakteten Text wird verworfen, sie hätte keinen Platz.
    ///
    /// **Tragen alle Zeilen dieselbe Zeit, ist der Text nicht getaktet** —
    /// manche Server schreiben bei ungetaktetem Text 0 an jede Zeile. Als
    /// getaktet stand dann ab der ersten Sekunde die letzte Zeile hell da und
    /// alle anderen grau wie schon gesungen: ein toter Text.
    public init(zeilen: [Zeile]) {
        let zeiten = Set(zeilen.compactMap(\.zeit))
        let getaktet = !zeiten.isEmpty && (zeiten.count > 1 || zeilen.filter { $0.zeit != nil }.count == 1)
        if !getaktet, !zeiten.isEmpty {
            self.zeilen = zeilen.map { Zeile(zeit: nil, text: $0.text) }
        } else if getaktet {
            // Stabil sortieren: gleiche Zeiten behalten ihre Reihenfolge.
            self.zeilen = zeilen.enumerated()
                .filter { $0.element.zeit != nil }
                .sorted { ($0.element.zeit!, $0.offset) < ($1.element.zeit!, $1.offset) }
                .map(\.element)
        } else {
            self.zeilen = zeilen
        }
    }

    public var getaktet: Bool { zeilen.first?.zeit != nil }
    public var istLeer: Bool { zeilen.allSatisfy(\.istPause) }

    /// **Die Zeile, die gerade gesungen wird.** Die letzte, deren Zeit
    /// erreicht ist; vor der ersten keine.
    ///
    /// - Parameter vorlauf: So viel früher springt die Hervorhebung weiter.
    ///   Zeitmarken zeigen, wann die Zeile **beginnt** — kommt die
    ///   Hervorhebung einen Wimpernschlag vorher, liest man mit statt hinterher.
    public func aktuelleZeile(zu zeit: TimeInterval, vorlauf: TimeInterval = 0.2) -> Int? {
        guard getaktet else { return nil }
        let t = zeit + vorlauf
        // Binäre Suche nach der letzten Zeile mit zeit <= t.
        var unten = 0
        var oben = zeilen.count - 1
        var treffer: Int?
        while unten <= oben {
            let mitte = (unten + oben) / 2
            if let z = zeilen[mitte].zeit, z <= t {
                treffer = mitte
                unten = mitte + 1
            } else {
                oben = mitte - 1
            }
        }
        return treffer
    }

    /// Wohin ein Tipp auf die Zeile springt.
    public func sprungziel(_ index: Int) -> TimeInterval? {
        guard zeilen.indices.contains(index) else { return nil }
        return zeilen[index].zeit.map { max(0, $0) }
    }

    // MARK: - LRC

    /// **Liest eine `.lrc`-Datei.**
    ///
    /// - `[mm:ss.xx]Text`, auch mehrere Zeitmarken vor einer Zeile
    ///   (`[00:12.00][01:30.00]Refrain`) — die Zeile steht dann mehrmals da.
    /// - `[offset:+500]` verschiebt alles; **plus heißt früher**, so steht es
    ///   in der Beschreibung des Formats.
    /// - Kopfzeilen wie `[ar:…]`, `[ti:…]` fallen weg, Wortmarken des
    ///   erweiterten Formats (`<00:12.30>`) ebenso.
    /// - Ohne eine einzige Zeitmarke ist es ein ungetakteter Text.
    public static func lrc(_ text: String) -> Liedtext {
        var getaktet: [(TimeInterval, String)] = []
        var frei: [String] = []
        var versatz: TimeInterval = 0

        for rohzeile in text.split(omittingEmptySubsequences: false,
                                   whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            var rest = Substring(rohzeile.trimmingCharacters(in: .whitespaces))
            var zeiten: [TimeInterval] = []
            var istKopf = false

            while rest.hasPrefix("["), let zu = rest.firstIndex(of: "]") {
                let innen = rest[rest.index(after: rest.startIndex) ..< zu]
                if let zeit = zeitmarke(innen) {
                    zeiten.append(zeit)
                } else if let doppelpunkt = innen.firstIndex(of: ":") {
                    let name = innen[..<doppelpunkt].lowercased()
                    if name == "offset",
                       let wert = Double(innen[innen.index(after: doppelpunkt)...]
                        .trimmingCharacters(in: .whitespaces)) {
                        versatz = wert / 1000
                    }
                    istKopf = true
                } else {
                    break
                }
                rest = rest[rest.index(after: zu)...]
            }

            let inhalt = ohneWortmarken(String(rest)).trimmingCharacters(in: .whitespaces)
            if !zeiten.isEmpty {
                for zeit in zeiten { getaktet.append((zeit, inhalt)) }
            } else if !istKopf {
                frei.append(inhalt)
            }
        }

        if getaktet.isEmpty {
            // Leere Zeilen am Rand tragen nichts; in der Mitte trennen sie Strophen.
            while frei.first?.isEmpty == true { frei.removeFirst() }
            while frei.last?.isEmpty == true { frei.removeLast() }
            return Liedtext(zeilen: frei.map { Zeile(zeit: nil, text: $0) })
        }
        return Liedtext(zeilen: getaktet.map { Zeile(zeit: max(0, $0.0 - versatz), text: $0.1) })
    }

    /// `mm:ss`, `mm:ss.x`, `mm:ss.xx`, `mm:ss.xxx`, auch `mm:ss:xx` und
    /// Stunden (`h:mm:ss.xx`).
    static func zeitmarke(_ text: Substring) -> TimeInterval? {
        let teile = text.split(separator: ":", omittingEmptySubsequences: false)
        guard teile.count >= 2, teile.allSatisfy({ !$0.isEmpty }) else { return nil }
        // Ein Doppelpunkt als Trenner vor den Hundertsteln (`01:02:34`) ist
        // eine alte Schreibweise — erkennbar daran, dass der letzte Teil zwei
        // Stellen hat und der mittlere die Sekunden trägt.
        var zahlen = teile.map(String.init)
        if zahlen.count == 3, zahlen[2].count == 2, (Int(zahlen[1]) ?? 99) < 60,
           (Int(zahlen[0]) ?? 99) < 60, !zahlen[1].contains(".") {
            zahlen = [zahlen[0], zahlen[1] + "." + zahlen[2]]
        }
        var sekunden: TimeInterval = 0
        for (i, teil) in zahlen.enumerated() {
            let istLetzter = i == zahlen.count - 1
            if istLetzter {
                guard let s = Double(teil), s >= 0, s < 60 || zahlen.count == 1 else { return nil }
                sekunden = sekunden * 60 + s
            } else {
                guard teil.allSatisfy(\.isNumber), let ganz = Int(teil) else { return nil }
                sekunden = sekunden * 60 + TimeInterval(ganz)
            }
        }
        return sekunden
    }

    private static func ohneWortmarken(_ text: String) -> String {
        guard text.contains("<") else { return text }
        var ergebnis = ""
        var rest = Substring(text)
        while let auf = rest.firstIndex(of: "<") {
            ergebnis += rest[..<auf]
            guard let zu = rest[auf...].firstIndex(of: ">") else {
                ergebnis += rest[auf...]
                return ergebnis
            }
            let innen = rest[rest.index(after: auf) ..< zu]
            if zeitmarke(innen) == nil {
                // Keine Zeitmarke — der Text meint das Zeichen wirklich.
                ergebnis += rest[auf ... zu]
            }
            rest = rest[rest.index(after: zu)...]
        }
        ergebnis += rest
        return ergebnis
    }
}
