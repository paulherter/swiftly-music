import CoreGraphics
import ImageIO
import SwiftUI

/// **Hüllen aus dem Netz: holen, abseits des Hauptlaufs entschlüsseln,
/// merken, einblenden.**
///
/// Nachgebaut nach `Bildspeicher`/`Netzbild` in `Sources/Shared/Netzbild.swift`
/// — dort stehen die Messungen hinter den Zahlen (vier Abrufe gleichzeitig,
/// zwei Entschlüsselungen, Merken nach Byte). Nicht geteilt, weil jene Datei
/// ohne `Stil.swift` und den Player nicht übersetzt.
///
/// Zwei Unterschiede für Musik:
/// - **Der Schlüssel ohne Zugangsmerkmal.** Jellyfin hängt `ApiKey` an,
///   Subsonic `u`, `t`, `s`; ohne das heißt dieselbe Hülle nach einem neuen
///   Salz oder Konto gleich, und die Ablage auf der Platte trifft.
/// - **Das `CGImage` bleibt greifbar**, für die Glut im Wiedergabeblatt und
///   das Bild auf dem Sperrbildschirm.
@MainActor
final class Bildlager {
    static let geteilt = Bildlager()

    private struct Eintrag: Sendable {
        let bild: Image
        let roh: Bildkiste
        let byte: Int
    }

    private var bekannt: [String: Eintrag] = [:]
    private var reihenfolge: [String] = []
    private var belegt = 0
    private var laufend: [String: Task<Eintrag?, Never>] = [:]

    /// iPhone: 96 MB wie im Player.
    private static let grenze = 96 * 1024 * 1024
    private static let gleichzeitig = 4
    private static let gleichzeitigWandeln = 2
    private var imLauf = 0
    private var wartend: [CheckedContinuation<Void, Never>] = []
    private var imWandeln = 0
    private var wartendAufWandeln: [CheckedContinuation<Void, Never>] = []

    /// **Nur diese Kantenlängen werden verlangt.** Dieselbe Hülle steht als
    /// 40er, 48er, 112er und 338er da; ohne Stufen wäre jede Größe eine eigene
    /// Adresse und ein eigener Abruf.
    static func stufe(punkte: CGFloat, skala: CGFloat = 3) -> Int {
        let noetig = Int((punkte * skala).rounded(.up))
        for s in [120, 300, 600, 1000] where noetig <= s { return s }
        return 1200
    }

    /// Das Bild, wenn es schon da ist — ohne zu warten.
    func bild(_ url: URL) -> Image? { bekannt[Self.schluessel(url)]?.bild }

    func rohbild(_ url: URL) -> CGImage? { bekannt[Self.schluessel(url)]?.roh.bild }

    @discardableResult
    func laden(_ url: URL) async -> Image? {
        await eintrag(url)?.bild
    }

    func rohbildLaden(_ url: URL) async -> CGImage? {
        await eintrag(url)?.roh.bild
    }

    private func eintrag(_ url: URL) async -> Eintrag? {
        let schluessel = Self.schluessel(url)
        if let da = bekannt[schluessel] { return da }
        if let lauf = laufend[schluessel] { return await lauf.value }

        let lauf = Task<Eintrag?, Never> { [self] in
            let daten: Data
            if url.isFileURL {
                guard let gelesen = await Task.detached(priority: .userInitiated, operation: {
                    try? Data(contentsOf: url)
                }).value else { return nil }
                daten = gelesen
            } else if let abgelegt = await Task.detached(priority: .userInitiated, operation: {
                Huellenablage.lesen(schluessel)
            }).value {
                daten = abgelegt
            } else {
                await einlass()
                let geholt = try? await URLSession.shared.data(from: url)
                einlassZurueck()
                guard let (d, antwort) = geholt,
                      (antwort as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { return nil }
                daten = d
                Task.detached(priority: .utility) { Huellenablage.schreiben(d, schluessel) }
            }
            await wandelEinlass()
            defer { wandelEinlassZurueck() }
            let kiste = await Task.detached(priority: .userInitiated) { () -> Bildkiste? in
                guard let quelle = CGImageSourceCreateWithData(daten as CFData, nil) else { return nil }
                let regeln: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1200,
                ]
                guard let roh = CGImageSourceCreateThumbnailAtIndex(quelle, 0, regeln as CFDictionary)
                else { return nil }
                return Bildkiste(bild: roh)
            }.value
            guard let kiste else { return nil }
            return Eintrag(bild: Image(decorative: kiste.bild, scale: 1), roh: kiste,
                           byte: kiste.bild.width * kiste.bild.height * 4)
        }
        laufend[schluessel] = lauf
        let ergebnis = await lauf.value
        laufend[schluessel] = nil
        if let ergebnis { merken(ergebnis, fuer: schluessel) }
        return ergebnis
    }

    private func merken(_ eintrag: Eintrag, fuer schluessel: String) {
        if let alt = bekannt[schluessel] {
            belegt -= alt.byte
        } else {
            reihenfolge.append(schluessel)
        }
        bekannt[schluessel] = eintrag
        belegt += eintrag.byte
        while belegt > Self.grenze, !reihenfolge.isEmpty {
            let raus = reihenfolge.removeFirst()
            belegt -= bekannt.removeValue(forKey: raus)?.byte ?? 0
        }
    }

    // MARK: Schleusen — wie in `Bildspeicher`

    private func einlass() async {
        if imLauf < Self.gleichzeitig {
            imLauf += 1
            return
        }
        await withCheckedContinuation { wartend.append($0) }
    }

    private func einlassZurueck() {
        if wartend.isEmpty {
            imLauf -= 1
        } else {
            wartend.removeFirst().resume()
        }
    }

    private func wandelEinlass() async {
        if imWandeln < Self.gleichzeitigWandeln {
            imWandeln += 1
            return
        }
        await withCheckedContinuation { wartendAufWandeln.append($0) }
    }

    private func wandelEinlassZurueck() {
        if wartendAufWandeln.isEmpty {
            imWandeln -= 1
        } else {
            wartendAufWandeln.removeFirst().resume()
        }
    }

    // MARK: Schlüssel

    /// Die Adresse ohne Zugangsmerkmal. Die Reihenfolge der übrigen Werte
    /// bleibt, sie ist je Quelle fest.
    nonisolated static func schluessel(_ url: URL) -> String {
        guard !url.isFileURL,
              var teile = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let werte = teile.queryItems else { return url.absoluteString }
        let geheim: Set<String> = ["apikey", "api_key", "u", "t", "s", "p", "v", "c", "f"]
        teile.queryItems = werte.filter { !geheim.contains($0.name.lowercased()) }
        return teile.url?.absoluteString ?? url.absoluteString
    }
}

/// `CGImage` über eine Laufgrenze tragen — unveränderlich, nur nicht als
/// `Sendable` erklärt (wie `Bildkiste` in `Netzbild.swift`).
struct Bildkiste: @unchecked Sendable {
    let bild: CGImage
}

/// **Hüllen auf der Platte**, im Cache-Ordner — das System darf ihn leeren.
/// Aufgeräumt wird beim ersten Schreiben je Start: über 300 MB fällt, was am
/// längsten nicht gelesen wurde, bis drei Viertel frei sind.
enum Huellenablage {
    private static let grenze = 300 * 1024 * 1024

    private static let ordner: URL? = {
        guard let basis = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let ordner = basis.appendingPathComponent("Huellen", isDirectory: true)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return ordner
    }()

    static func name(_ schluessel: String) -> String {
        var wert: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in schluessel.utf8 {
            wert ^= UInt64(byte)
            wert &*= 0x0100_0000_01b3
        }
        return String(wert, radix: 16)
    }

    static func lesen(_ schluessel: String) -> Data? {
        guard let datei = ordner?.appendingPathComponent(name(schluessel)),
              let daten = try? Data(contentsOf: datei) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: datei.path)
        return daten
    }

    static func schreiben(_ daten: Data, _ schluessel: String) {
        guard let ziel = ordner?.appendingPathComponent(name(schluessel)) else { return }
        try? daten.write(to: ziel, options: .atomic)
        _ = aufgeraeumt
    }

    private static let aufgeraeumt: Void = aufraeumen()

    private static func aufraeumen() {
        guard let ordner else { return }
        let felder: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let dateien = try? FileManager.default.contentsOfDirectory(
            at: ordner, includingPropertiesForKeys: felder) else { return }
        var liste = dateien.compactMap { datei -> (URL, Int, Date)? in
            guard let w = try? datei.resourceValues(forKeys: Set(felder)) else { return nil }
            return (datei, w.fileSize ?? 0, w.contentModificationDate ?? .distantPast)
        }
        var summe = liste.reduce(0) { $0 + $1.1 }
        guard summe > grenze else { return }
        liste.sort { $0.2 < $1.2 }
        for (datei, groesse, _) in liste where summe > grenze * 3 / 4 {
            try? FileManager.default.removeItem(at: datei)
            summe -= groesse
        }
    }
}

/// **Ein Bild, das einblendet**, sobald es da ist. Während des Abrufs pulst
/// ein Ladefeld wie im Player (`Bild` in `Stil.swift`) — ein Ersatzzeichen
/// hieße „hier gibt es kein Bild", und das stimmt dann noch nicht
/// (`VERHALTEN.md` E18).
struct Netzhuelle: View {
    let adresse: URL?
    var zeichengroesse: CGFloat = 22

    @State private var bild: Image?
    @State private var sichtbar = false
    @State private var fehlt = false

    init(adresse: URL?, zeichengroesse: CGFloat = 22) {
        self.adresse = adresse
        self.zeichengroesse = zeichengroesse
        let sofort = adresse.flatMap { Bildlager.geteilt.bild($0) }
        _bild = State(initialValue: sofort)
        _sichtbar = State(initialValue: sofort != nil)
        _fehlt = State(initialValue: adresse == nil)
    }

    var body: some View {
        ZStack {
            Stil.flaeche
            if let bild {
                bild.resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(sichtbar ? 1 : 0)
            } else if fehlt {
                Image(systemName: "music.note")
                    .font(.system(size: zeichengroesse))
                    .foregroundStyle(Stil.schriftSehrLeise)
            }
            if !sichtbar && !fehlt {
                Ladefeld(ecke: 0)
            }
        }
        .task(id: adresse) {
            guard let adresse else {
                bild = nil
                fehlt = true
                return
            }
            if let da = Bildlager.geteilt.bild(adresse) {
                bild = da
                sichtbar = true
                fehlt = false
                return
            }
            fehlt = false
            guard let geladen = await Bildlager.geteilt.laden(adresse) else {
                if !Task.isCancelled { fehlt = true }
                return
            }
            bild = geladen
            withAnimation(Musikstil.einblenden) { sichtbar = true }
        }
    }
}
