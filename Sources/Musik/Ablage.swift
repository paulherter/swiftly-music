import Foundation
import MusikKit
import UIKit

/// **Geladene Musik auf dem Gerät.**
///
/// Das Verzeichnis (was liegt da, wer braucht es) steht in MusikKit
/// (``Ablageverzeichnis``); hier wird geladen, abgelegt und gelöscht. Je Konto
/// ein eigener Ordner unter `Application Support/Musik/<Konto>` — ein
/// geladenes Lied gehört seinem Konto (`VERHALTEN.md` H11).
///
/// **Eins nach dem anderen** (H4): ein Album mit zwölf Liedern lädt Lied für
/// Lied, der Rest wartet sichtbar. Geladen wird, was der Player auch streamen
/// würde — die Originaldatei, wenn das iPhone sie spielen kann, sonst dieselbe
/// Umwandlung wie beim Streamen; eine Ogg-Datei auf dem Gerät hätte ohne
/// Server keinen Weg in den Lautsprecher.
@MainActor
@Observable
final class Ablage {

    private(set) var verzeichnis = Ablageverzeichnis()
    /// Das Lied, das gerade lädt.
    private(set) var laedt: String?
    /// 0…1 für das laufende Lied.
    private(set) var fortschritt: Double = 0
    /// Ein Hinweis, wenn etwas nicht ging.
    var hinweis: String?

    /// Das Netz gerade und ob nur über WLAN geladen werden darf
    /// (``Ladeerlaubnis``) — das Modell hält beides aktuell.
    @ObservationIgnored var verbindung: Verbindung = .wlan
    @ObservationIgnored var nurWLAN = false
    /// Ob gerade gewartet wird, bis geladen werden darf.
    private(set) var wartetAufNetz = false

    @ObservationIgnored private var konto: Kontokennung?
    @ObservationIgnored private var quelle: (any Musikquelle)?
    @ObservationIgnored private var lauf: Task<Void, Never>?
    @ObservationIgnored private var bilder: [String: String] = [:]

    // MARK: - Ordner

    @ObservationIgnored private var ordnerGemerkt: URL?

    private var ordner: URL? {
        if let ordnerGemerkt { return ordnerGemerkt }
        guard let konto,
              let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        var ordner = basis.appendingPathComponent("Musik", isDirectory: true)
            .appendingPathComponent(konto.ablagename, isDirectory: true)
        if !FileManager.default.fileExists(atPath: ordner.path) {
            try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            // Geladene Musik lässt sich jederzeit neu holen — sie gehört
            // nicht in die Sicherung.
            var werte = URLResourceValues()
            werte.isExcludedFromBackup = true
            try? ordner.setResourceValues(werte)
        }
        ordnerGemerkt = ordner
        return ordner
    }

    private var verzeichnisdatei: URL? { ordner?.appendingPathComponent("verzeichnis.json") }
    private var bilderdatei: URL? { ordner?.appendingPathComponent("bilder.json") }

    // MARK: - Einrichten

    /// Nach dem Anmelden: das Verzeichnis dieses Kontos lesen und weiterladen,
    /// was noch fehlt.
    func einrichten(konto: Kontokennung, quelle: any Musikquelle) {
        lauf?.cancel()
        lauf = nil
        ordnerGemerkt = nil
        self.konto = konto
        self.quelle = quelle
        verzeichnis = verzeichnisdatei.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Ablageverzeichnis.self, from: $0) } ?? Ablageverzeichnis()
        bilder = bilderdatei.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        // Dateien, die fehlen (etwa nach einer Wiederherstellung ohne sie),
        // gelten nicht als geladen — sie kommen wieder in die Warteschlange.
        if let ordner {
            for (id, datei) in verzeichnis.dateien
            where !FileManager.default.fileExists(atPath: ordner.appendingPathComponent(datei.pfad).path) {
                verzeichnis.vergessen(liedID: id)
            }
        }
        weiterladen()
    }

    /// Beim Abmelden: nicht mehr laden. Die Dateien bleiben — meldet sich
    /// dasselbe Konto wieder an, sind sie noch da.
    func trennen() {
        lauf?.cancel()
        lauf = nil
        konto = nil
        ordnerGemerkt = nil
        quelle = nil
        verzeichnis = Ablageverzeichnis()
        bilder = [:]
        laedt = nil
        fortschritt = 0
    }

    private func sichern() {
        guard let verzeichnisdatei, let bilderdatei else { return }
        try? JSONEncoder().encode(verzeichnis).write(to: verzeichnisdatei, options: .atomic)
        try? JSONEncoder().encode(bilder).write(to: bilderdatei, options: .atomic)
    }

    // MARK: - Fragen

    func stand(_ verweis: Sammlungsverweis) -> Ablageverzeichnis.Stand {
        verzeichnis.stand(verweis.id)
    }

    func istGeladen(_ lied: Lied) -> Bool { verzeichnis.istGeladen(lied.id) }

    /// Der Weg zur geladenen Datei, wenn es sie gibt.
    func lokalerWeg(fuer lied: Lied) -> Abspielweg? {
        guard let datei = verzeichnis.datei(fuer: lied.id),
              let url = ordner?.appendingPathComponent(datei.pfad),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return Abspielweg(adresse: url, mime: datei.mime, art: datei.art, format: datei.lied.format,
                          umwandlung: datei.art == .umgewandelt
                            ? Abspielregel.umwandlung(fuer: quelle?.serverart ?? .jellyfin) : nil)
    }

    /// Die abgelegte Hülle, wenn es sie gibt — damit geladene Alben auch ohne
    /// Netz ihr Bild zeigen.
    ///
    /// Ohne Blick auf die Platte: das läuft beim Zeichnen jeder Kachel. Fehlt
    /// die Datei doch, bleibt die Kachel eben leer.
    func lokalesBild(_ bild: Bildbezug) -> URL? {
        guard let name = bilder[Self.bildschluessel(bild)] else { return nil }
        return ordner?.appendingPathComponent(name)
    }

    var belegt: Int64 { verzeichnis.belegt }

    // MARK: - Laden und Entfernen

    /// Eine Sammlung zum Laden vormerken und loslegen.
    func laden(_ verweis: Sammlungsverweis, lieder: [Lied]) {
        guard !lieder.isEmpty else { return }
        // Vorher nachsehen, ob es passt — bei Musik selten knapp, aber wenn,
        // dann lieber vorher sagen als nach der Hälfte.
        let noetig = lieder.filter { !verzeichnis.istGeladen($0.id) }.compactMap(\.groesse).reduce(0, +)
        if let frei = Self.freierPlatz(), noetig > 0, frei < noetig + 200_000_000 {
            hinweis = String(localized: "Auf dem iPhone ist nicht genug Platz für dieses Album.")
            return
        }
        verzeichnis.vormerken(verweis, lieder: lieder)
        sichern()
        weiterladen()
        if wartetAufNetz {
            hinweis = verbindung == .keine ? String(localized: "Lädt, sobald das Netz wieder da ist.")
                                           : String(localized: "Lädt, sobald WLAN da ist.")
        }
    }

    /// Eine Sammlung entfernen — Dateien, die keine andere mehr braucht, fallen.
    func entfernen(_ verweis: Sammlungsverweis) {
        let frei = verzeichnis.entfernen(verweis.id)
        loeschen(frei)
        if let laedt, !verzeichnis.warteschlange.contains(where: { $0.id == laedt }) {
            lauf?.cancel()
            lauf = nil
            self.laedt = nil
            weiterladen()
        }
        sichern()
    }

    /// Alles, was dieses Konto geladen hat.
    func alleEntfernen() {
        lauf?.cancel()
        lauf = nil
        laedt = nil
        loeschen(verzeichnis.leeren())
        if let ordner {
            for name in Set(bilder.values) { try? FileManager.default.removeItem(at: ordner.appendingPathComponent(name)) }
        }
        bilder = [:]
        sichern()
    }

    private func loeschen(_ dateien: [Ablageverzeichnis.Datei]) {
        guard let ordner else { return }
        for d in dateien { try? FileManager.default.removeItem(at: ordner.appendingPathComponent(d.pfad)) }
    }

    /// Der Lauf: das nächste fehlende Lied, bis keins mehr fehlt.
    ///
    /// Jeder Lauf trägt eine Nummer. Ein abgebrochener Lauf räumt beim
    /// Aufhören nur auf, wenn er noch der geltende ist — sonst löschte er den
    /// Verweis auf seinen Nachfolger, und der nächste Aufruf startete einen
    /// zweiten Lauf daneben.
    @ObservationIgnored private var laufnummer = 0

    /// Lieder, die sich dauerhaft nicht laden lassen (keine Adresse, der
    /// Server lehnt ab) — übersprungen, damit eins nicht die ganze Schlange
    /// aufhält. Nur für diesen Start; beim nächsten gibt es einen neuen Versuch.
    @ObservationIgnored private var uebersprungen = Set<String>()

    private enum Ausgang { case fertig, dauerhaftGescheitert, abbrechen }

    /// Weiter, was noch fehlt — auch nach einem Netzwechsel oder wenn „Nur
    /// über WLAN laden" ausgeschaltet wird.
    func weiterladen() {
        guard lauf == nil, quelle != nil else { return }
        wartetAufNetz = !verzeichnis.warteschlange.isEmpty && !Ladeerlaubnis.darf(verbindung, nurWLAN: nurWLAN)
        guard !wartetAufNetz else { return }
        laufnummer += 1
        let nummer = laufnummer
        lauf = Task { [weak self] in
            while let self, !Task.isCancelled, self.laufnummer == nummer,
                  let lied = self.verzeichnis.warteschlange.first(where: { !self.uebersprungen.contains($0.id) }) {
                switch await self.eins(lied, nummer: nummer) {
                case .fertig: continue
                case .dauerhaftGescheitert: self.uebersprungen.insert(lied.id)
                // Ohne Netz: nicht im Kreis laufen. Beim nächsten Start (oder
                // dem nächsten Laden) geht es weiter.
                case .abbrechen: break
                }
                if Task.isCancelled { break }
            }
            guard let self, self.laufnummer == nummer else { return }
            self.lauf = nil
            self.laedt = nil
            self.fortschritt = 0
        }
    }

    /// Ob dieser Lauf noch gilt — nach jedem `await` zu fragen.
    private func giltNoch(_ nummer: Int) -> Bool {
        !Task.isCancelled && laufnummer == nummer && lauf != nil
    }

    /// Lädt ein Lied und seine Hülle.
    private func eins(_ lied: Lied, nummer: Int) async -> Ausgang {
        guard let quelle, let ordner else { return .abbrechen }
        guard let weg = quelle.ladeweg(lied) else { return .dauerhaftGescheitert }
        laedt = lied.id
        fortschritt = 0
        let endung = weg.art == .umgewandelt
            ? (weg.umwandlung?.codec ?? "mp3")
            : (lied.format?.behaelter.flatMap { $0.isEmpty ? nil : $0 } ?? "mp3")
        let name = "\(Self.dateiname(lied.id)).\(endung)"
        let ziel = ordner.appendingPathComponent(name)

        // **Über die Hintergrunds-Sitzung**: das Lied lädt weiter, wenn die
        // App nicht mehr vorn ist. Mit „Nur über WLAN laden" wartet es auf
        // Mobilfunk, bis WLAN wieder da ist.
        var anfrage = URLRequest(url: weg.adresse)
        anfrage.allowsCellularAccess = !nurWLAN
        let kennung = "\(konto?.ablagename ?? "")|\(lied.id)"

        do {
            let (vorlaeufig, antwort) = try await Hintergrundlader.geteilt.laden(anfrage, kennung: kennung) {
                [weak self] anteil in
                Task { @MainActor in
                    // Nur für das Lied, das gerade lädt — eine späte
                    // Meldung des vorigen überschreibt sonst den neuen Balken.
                    guard let self, self.laedt == lied.id else { return }
                    self.fortschritt = max(self.fortschritt, anteil)
                }
            }
            guard giltNoch(nummer) else {
                try? FileManager.default.removeItem(at: vorlaeufig)
                return .abbrechen
            }
            let status = (antwort as? HTTPURLResponse)?.statusCode ?? 200
            guard status == 200 else {
                try? FileManager.default.removeItem(at: vorlaeufig)
                hinweis = String(localized: "Ein Lied ließ sich nicht laden.")
                // 4xx: dieses Lied geht nicht. 5xx: der Server hat gerade ein Problem.
                return (400 ..< 500).contains(status) ? .dauerhaftGescheitert : .abbrechen
            }
            try? FileManager.default.removeItem(at: ziel)
            try FileManager.default.moveItem(at: vorlaeufig, to: ziel)
            let groesse = (try? FileManager.default.attributesOfItem(atPath: ziel.path)[.size] as? NSNumber)?
                .int64Value ?? 0
            // Nur eintragen, wenn es noch gebraucht wird — die Sammlung kann
            // während des Ladens entfernt worden sein.
            guard verzeichnis.warteschlange.contains(where: { $0.id == lied.id }) else {
                try? FileManager.default.removeItem(at: ziel)
                return .fertig
            }
            let mime = weg.art == .umgewandelt ? "audio/mpeg" : (weg.mime ?? Abspielregel.mime(fuer: endung))
            verzeichnis.eintragen(.init(lied: lied, pfad: name, groesse: groesse, art: weg.art, mime: mime,
                                        geladen: Date()))
            sichern()
            if let bild = lied.bild { await huelleAblegen(bild, nummer: nummer) }
            if giltNoch(nummer) { sichern() }
            return .fertig
        } catch {
            if !Task.isCancelled {
                hinweis = String(localized: "Ein Lied ließ sich nicht laden.")
            }
            return .abbrechen
        }
    }

    private func huelleAblegen(_ bild: Bildbezug, nummer: Int) async {
        let schluessel = Self.bildschluessel(bild)
        guard bilder[schluessel] == nil, let quelle, let ordner,
              let url = quelle.bildadresse(bild, kante: 600),
              let (daten, antwort) = try? await URLSession.shared.data(from: url),
              (antwort as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { return }
        // Inzwischen alles entfernt oder abgemeldet: nichts mehr ablegen.
        guard giltNoch(nummer), self.ordner == ordner, !verzeichnis.dateien.isEmpty else { return }
        let name = "huelle-\(Self.dateiname(schluessel)).bild"
        try? daten.write(to: ordner.appendingPathComponent(name), options: .atomic)
        bilder[schluessel] = name
    }

    // MARK: - Hilfen

    static func bildschluessel(_ bild: Bildbezug) -> String {
        "\(bild.id)|\(bild.marke ?? "")|\(bild.hintergrund)"
    }

    /// Eine Kennung als Dateiname: nur Buchstaben und Ziffern.
    static func dateiname(_ text: String) -> String {
        var wert: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            wert ^= UInt64(byte)
            wert &*= 0x0100_0000_01b3
        }
        let lesbar = text.filter { $0.isLetter || $0.isNumber }.prefix(40)
        return "\(lesbar)-\(String(wert, radix: 16))"
    }

    /// Freier Platz, wie ihn das System für wichtige Daten rechnet.
    static func freierPlatz() -> Int64? {
        let basis = URL(fileURLWithPath: NSHomeDirectory())
        let werte = try? basis.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return werte?.volumeAvailableCapacityForImportantUsage
    }
}
