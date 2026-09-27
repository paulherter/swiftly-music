import Foundation

/// **„Zuletzt gehört": acht Sammlungen, neueste zuerst.**
///
/// Die eigene Liste kennt, woraus auf diesem Gerät gespielt wurde — auch
/// Künstler und Playlists, die der Server so nicht meldet. Der Server kennt
/// die Alben, die auf anderen Geräten liefen. Beides zusammen, nach Zeit.
public enum Zuletztgehoert {

    public static let anzahl = 8
    /// So viele merkt sich das Gerät — mehr als gezeigt, damit nach einem
    /// Wechsel auf ein anderes Konto nicht gleich alles aufgefüllt werden muss.
    public static let gemerkt = 40

    /// **Was hineingehört: Alben, Playlists, Künstler** (24.09.). Keine
    /// Singles, keine EPs, keine Hörbücher — und einzelne Lieder ohnehin
    /// nicht. Eingetragen wird nur, wenn die Sammlung selbst gestartet wurde
    /// (Abspielen oder Zufall auf ihrer Seite oder Kachel); das entscheidet
    /// die Aufrufstelle, nicht diese Regel.
    ///
    /// `art` ist, was man sonst über das Album weiß — für Einträge, die ihre
    /// Art noch nicht mitbringen.
    public static func zaehlt(_ verweis: Sammlungsverweis, art: Albumart? = nil) -> Bool {
        switch verweis.art {
        case .kuenstler, .playlist: return true
        case .hoerbuch: return false
        case .album:
            let a = verweis.albumart ?? art
            return a != .single && a != .ep
        }
    }

    /// Nimmt heraus, was nach ``zaehlt(_:art:)`` nicht hineingehört — beim
    /// Laden, für Einträge von vorher.
    public static func bereinigt(_ liste: [Sammlungsverweis],
                                 art: (Sammlungsverweis) -> Albumart? = { _ in nil }) -> [Sammlungsverweis] {
        liste.filter { zaehlt($0, art: art($0)) }
    }

    /// Nimmt eine Sammlung vorn auf; steht sie schon da, rückt sie nach vorn.
    /// Was nicht hineingehört, bleibt draußen.
    public static func merken(_ neu: Sammlungsverweis, in liste: [Sammlungsverweis]) -> [Sammlungsverweis] {
        guard zaehlt(neu) else { return liste }
        var ergebnis = liste.filter { $0.id != neu.id }
        ergebnis.insert(neu, at: 0)
        return Array(ergebnis.prefix(gemerkt))
    }

    /// **Ein Album gilt vom Server nur als gehört, wenn mindestens die
    /// Hälfte seiner Lieder gespielt wurde** — sonst hat jemand ein Lied
    /// daraus gehört, nicht das Album. Ohne bekannte Liedzahl zählt es nicht.
    public static func albumGehoert(gespielt: Int, liedzahl: Int?) -> Bool {
        guard let liedzahl, liedzahl > 0, gespielt > 0 else { return false }
        return gespielt * 2 >= liedzahl
    }

    /// **Die eigene Liste — der Server nur, solange sie leer ist.**
    ///
    /// Was der Server als gehört meldet, sind die Alben gespielter Lieder:
    /// ein einzelnes Lied aus der Suche brachte so sein Album hierher. Das
    /// ist ausdrücklich nicht gewollt (24.09.). Die Serverliste füllt deshalb
    /// nur die leere Reihe direkt nach einer Neuanmeldung; sobald es einen
    /// eigenen Eintrag gibt, zählt nur noch die eigene Liste.
    ///
    /// Innerhalb der Serverliste gilt je Sammlung die neueste Zeit; ohne Zeit
    /// steht sie hinter allen mit Zeit, in der Reihenfolge des Servers.
    /// Singles, EPs und Hörbücher fallen heraus (``zaehlt(_:art:)``); `art`
    /// weiß über Alben, was ein Eintrag selbst nicht sagt.
    public static func liste(eigene: [Sammlungsverweis], server: [Sammlungsverweis],
                             anzahl: Int = anzahl,
                             art: (Sammlungsverweis) -> Albumart? = { _ in nil }) -> [Sammlungsverweis] {
        let eigene = bereinigt(eigene, art: art)
        let quelle = eigene.isEmpty ? bereinigt(server, art: art) : eigene
        var nachKennung: [String: (verweis: Sammlungsverweis, rang: Int)] = [:]
        for (rang, v) in quelle.enumerated() {
            if let da = nachKennung[v.id] {
                let neuer = (v.zeit ?? .distantPast) > (da.verweis.zeit ?? .distantPast)
                if neuer {
                    // Titel und Bild vom Server sind frischer als die abgelegten.
                    nachKennung[v.id] = (v, da.rang)
                } else if da.verweis.bild == nil, v.bild != nil {
                    var besser = da.verweis
                    besser.bild = v.bild
                    nachKennung[v.id] = (besser, da.rang)
                }
            } else {
                nachKennung[v.id] = (v, rang)
            }
        }
        return nachKennung.values
            .sorted { a, b in
                switch (a.verweis.zeit, b.verweis.zeit) {
                case let (x?, y?): return x != y ? x > y : a.rang < b.rang
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return a.rang < b.rang
                }
            }
            .prefix(anzahl)
            .map(\.verweis)
    }
}

/// **Die Marke „NEU" auf einer Kachel.** Ein Wort, keine Zahl
/// (`BRAND.md` 7, „Die Kachel"): neu heißt, in den letzten zwei Wochen
/// hinzugekommen und noch nie gehört.
public enum Neuheit {
    public static let tage = 14

    public static func istNeu(hinzugefuegt: Date?, gespielt: Int?, jetzt: Date = Date()) -> Bool {
        guard let hinzugefuegt else { return false }
        guard (gespielt ?? 0) == 0 else { return false }
        let alter = jetzt.timeIntervalSince(hinzugefuegt)
        return alter >= 0 && alter < TimeInterval(tage) * 86_400
    }
}

/// Ein Vorschlag für die Reihe „Sofortmix" auf der Startseite.
public struct Mixvorschlag: Identifiable, Hashable, Sendable {
    public enum Ziel: Hashable, Sendable {
        case kuenstler(id: String, name: String)
        case genre(String)
    }

    public let ziel: Ziel
    /// Bis zu vier Hüllen für das Mosaik.
    public let huellen: [Bildbezug]

    public var id: String {
        switch ziel {
        case let .kuenstler(id, _): "k:\(id)"
        case let .genre(name): "g:\(name.lowercased())"
        }
    }

    /// Der Name auf dem Etikett und hinter „Mix:".
    public var name: String {
        switch ziel {
        case let .kuenstler(_, name): name
        case let .genre(name): name
        }
    }

    public var mixziel: Mixziel {
        switch ziel {
        case let .kuenstler(id, name): .kuenstler(id: id, name: name)
        case let .genre(name): .genre(name)
        }
    }
}

/// **Welche Mixe die Startseite anbietet.**
///
/// Aus den Alben, die zuletzt und oft gehört wurden: die zwei Künstler, die
/// dort am häufigsten stehen, und das häufigste Genre — in der Folge
/// Künstler, Genre, Künstler, damit sich die Arten abwechseln. Sammelalben
/// („Various Artists") zählen für kein Künstlerkonto.
public enum Mixvorschlaege {

    public static func bilden(aus alben: [Album], kuenstler hoechstens: Int = 2,
                              genres genreHoechstens: Int = 1) -> [Mixvorschlag] {
        var kuenstlerZahl: [String: (name: String, zahl: Double, erste: Int)] = [:]
        var genreZahl: [String: (name: String, zahl: Double, erste: Int)] = [:]

        for (i, album) in alben.enumerated() {
            // Weiter vorn in der Liste wiegt mehr — das ist das Frischere.
            let gewicht = 1.0 + 1.0 / Double(i + 1)
            if let id = album.kuenstlerID, let name = album.kuenstler, !istSammlung(name, album) {
                let alt = kuenstlerZahl[id] ?? (name, 0, i)
                kuenstlerZahl[id] = (alt.name, alt.zahl + gewicht, alt.erste)
            }
            for genre in album.genres where !genre.isEmpty {
                let schluessel = genre.lowercased()
                let alt = genreZahl[schluessel] ?? (genre, 0, i)
                genreZahl[schluessel] = (alt.name, alt.zahl + gewicht, alt.erste)
            }
        }

        func rangfolge(_ d: [String: (name: String, zahl: Double, erste: Int)]) -> [(String, String)] {
            d.sorted { a, b in
                a.value.zahl != b.value.zahl ? a.value.zahl > b.value.zahl : a.value.erste < b.value.erste
            }.map { ($0.key, $0.value.name) }
        }

        let kuenstler = rangfolge(kuenstlerZahl).prefix(hoechstens).map { paar in
            Mixvorschlag(ziel: .kuenstler(id: paar.0, name: paar.1),
                         huellen: huellen(alben.filter { $0.kuenstlerID == paar.0 }))
        }
        let genres = rangfolge(genreZahl).prefix(genreHoechstens).map { paar in
            Mixvorschlag(ziel: .genre(paar.1),
                         huellen: huellen(alben.filter { $0.genres.contains { $0.lowercased() == paar.0 } }))
        }

        // Künstler, Genre, Künstler …
        var ergebnis: [Mixvorschlag] = []
        var k = kuenstler.makeIterator()
        var g = genres.makeIterator()
        var kam = true
        while kam {
            kam = false
            if let a = k.next() { ergebnis.append(a); kam = true }
            if let b = g.next() { ergebnis.append(b); kam = true }
        }
        return ergebnis
    }

    /// Bis zu vier verschiedene Hüllen. Sind es weniger, wiederholen sie sich —
    /// das Mosaik hat immer vier Felder.
    static func huellen(_ alben: [Album]) -> [Bildbezug] {
        var gesehen = Set<Bildbezug>()
        var liste: [Bildbezug] = []
        for album in alben {
            guard let bild = album.bild, !gesehen.contains(bild) else { continue }
            gesehen.insert(bild)
            liste.append(bild)
            if liste.count == 4 { break }
        }
        guard !liste.isEmpty else { return [] }
        var i = 0
        while liste.count < 4 {
            liste.append(liste[i % liste.count])
            i += 1
        }
        return liste
    }

    static func istSammlung(_ name: String, _ album: Album) -> Bool {
        if album.art == .zusammenstellung { return true }
        let klein = name.lowercased()
        return ["various artists", "various", "verschiedene interpreten", "va"].contains(klein)
    }
}
