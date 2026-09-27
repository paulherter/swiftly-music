import Foundation
import JellyfinKit
import OSLog

/// **Das Protokoll von Swiftly Music** — unter demselben Namen wie im Player
/// (`Protokoll.schreib` in `Sources/Shared/VLCPlayer.swift`), damit
/// `Sources/Shared/Protokollteilen.swift` unverändert in dieses Ziel geht.
///
/// Anders als dort ohne eigene Datei: jede Zeile geht in den Ring im
/// Speicher (``Protokollring``, geschwärzt beim Eintragen), ins Systemprotokoll
/// (Konsole, Filter „Swiftly Music") und zusätzlich fortlaufend in
/// `Documents/swiftly-music.log` — für die Messung des Zurückholens von Sonos
/// (Auftrag 25.09.), bei der „Protokoll teilen" zu spät kommt, weil die
/// Sitzung dafür extra beendet werden müsste.
enum Protokoll {
    private static let system = Logger(subsystem: "de.paulherter.swiftly.music", category: "App")

    static func schreib(_ text: String) {
        let sauber = Protokollschwaerzung.text(text)
        system.notice("\(sauber, privacy: .public)")
        Protokollring.geteilt.anhaengen(sauber)
        Dateiprotokoll.geteilt.anhaengen(sauber)
    }
}

/// **Die Datei `Documents/swiftly-music.log`.**
///
/// Vorbild ist `Protokoll.schreib` in `Sources/Shared/VLCPlayer.swift`
/// (Swiftly Player nach `Documents/swiftly.log`) — hier zusätzlich gepuffert
/// und der Länge nach begrenzt, weil dieses Protokoll nicht nur im
/// Entwicklerbau, sondern für die laufende Messung mitschreibt.
///
/// - Geschrieben wird **gepuffert**, höchstens alle zwei Sekunden: eine
///   Sperre je Zeile wäre bei den dichten Meldungen beim Zurückholen von
///   Sonos unnötige Plattenzugriffe.
/// - Die Datei bleibt auf rund ``grenze`` Zeilen — läuft sie über, fliegt die
///   ältere Hälfte hinaus, nicht nur die überzähligen Zeilen: sonst schriebe
///   fast jeder Aufruf erneut auf die Platte.
private final class Dateiprotokoll: @unchecked Sendable {
    static let geteilt = Dateiprotokoll()

    private let grenze = 2000
    private let mindestabstand: TimeInterval = 2

    private let sperre = NSLock()
    private var puffer: [String] = []
    private var letzteSchreibzeit: Date = .distantPast
    private var zeilenInDatei: Int?

    private let pfad: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("swiftly-music.log")
    }()

    /// `text` ist bereits geschwärzt (``Protokoll/schreib(_:)``).
    ///
    /// **Die Sperre umschließt auch das Schreiben** — bei höchstens einem
    /// Schreibzugriff alle zwei Sekunden fällt das nicht ins Gewicht, macht
    /// aber zwei sich überschneidende Dateizugriffe unmöglich.
    func anhaengen(_ text: String, jetzt: Date = Date()) {
        let stempel = String(format: "%.3f", jetzt.timeIntervalSince1970)
        sperre.lock(); defer { sperre.unlock() }
        puffer.append("\(stempel) \(text)")
        guard jetzt.timeIntervalSince(letzteSchreibzeit) >= mindestabstand else { return }
        letzteSchreibzeit = jetzt
        let zeilen = puffer
        puffer.removeAll(keepingCapacity: true)
        aufDiePlatteSchreiben(zeilen)
    }

    /// Nur unter ``sperre`` gerufen.
    private func aufDiePlatteSchreiben(_ zeilen: [String]) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: pfad.path) {
            fm.createFile(atPath: pfad.path, contents: nil)
        }
        guard let griff = try? FileHandle(forWritingTo: pfad) else { return }
        defer { try? griff.close() }
        _ = try? griff.seekToEnd()
        let block = zeilen.map { "\($0)\n" }.joined()
        try? griff.write(contentsOf: Data(block.utf8))

        if zeilenInDatei == nil {
            zeilenInDatei = (try? String(contentsOf: pfad, encoding: .utf8))?
                .split(separator: "\n", omittingEmptySubsequences: true).count ?? zeilen.count
        } else {
            zeilenInDatei! += zeilen.count
        }
        guard let anzahl = zeilenInDatei, anzahl > grenze else { return }
        // Beim Überlauf die ältere Hälfte verwerfen, nicht nur den Rest über
        // der Grenze — sonst schriebe fast jeder weitere Aufruf die ganze
        // Datei neu.
        guard let inhalt = try? String(contentsOf: pfad, encoding: .utf8) else { return }
        let alle = inhalt.split(separator: "\n", omittingEmptySubsequences: true)
        let behalten = alle.suffix(grenze / 2)
        let neu = behalten.joined(separator: "\n") + "\n"
        try? Data(neu.utf8).write(to: pfad)
        zeilenInDatei = behalten.count
    }
}
