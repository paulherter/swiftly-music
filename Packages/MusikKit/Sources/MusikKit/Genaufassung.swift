import Foundation

/// **Die genaue Fassung einer gestreamten FLAC-Datei.**
///
/// Ohne `AVURLAssetPreferPreciseDurationAndTimingKey` springt AVFoundation in
/// FLAC über eine geschätzte Bitrate (``Abspielregel/genauerZugriff(_:startMitten:)``:
/// `seek(58)` klang nach 67,5 s). Mit dem Schlüssel lädt es über das Netz erst
/// die ganze Datei, bevor das Item bereit ist — beim Start eines Liedes
/// zu teuer. Darum lädt die App die Datei **im WLAN nebenher** und wechselt,
/// sobald sie da ist, unbemerkt auf ein Item aus der Datei auf dem Gerät mit
/// dem Schlüssel (dort +0,07 s) — in der Pause oder mit dem nächsten Sprung
/// (``einwechseln(stelle:dauer:springt:bereit:laeuft:verrutscht:)``). Ab
/// dann sitzt jedes Spulen.
///
/// Im Mobilfunk, in einem teuren Netz (Hotspot) und im Datensparmodus bleibt
/// es beim Stream wie bisher. Die Dateien liegen im Zwischenspeicher, höchstens
/// die des laufenden und des nächsten Liedes, und zählen nicht als geladen.
public enum Genaufassung {

    /// **Betrifft den Abspielweg**: eine FLAC-Datei, direkt vom Server —
    /// Jellyfin `static=true` wie Subsonic `format=raw`. Nicht, was schon auf
    /// dem Gerät liegt, und nicht, was umgewandelt kommt.
    public static func betrifft(_ weg: Abspielweg) -> Bool {
        weg.art == .direkt && !weg.adresse.isFileURL && Abspielregel.istFlacDatei(weg)
    }

    /// **Laden nur im WLAN** — kein Mobilfunk, kein teures Netz (beides
    /// ``Verbindung/mobil``), kein Datensparmodus (`sparsam`).
    public static func darfLaden(_ verbindung: Verbindung, sparsam: Bool) -> Bool {
        verbindung == .wlan && !sparsam
    }

    /// **Für dieses Item nebenher laden?** `schonGenau`: das Item hat den
    /// Schlüssel schon (es fing mitten drin an und lädt dafür selbst ganz).
    public static func nachladen(_ weg: Abspielweg, schonGenau: Bool, verbindung: Verbindung,
                                 sparsam: Bool) -> Bool {
        !schonGenau && betrifft(weg) && darfLaden(verbindung, sparsam: sparsam)
    }

    /// Wann das laufende Item gegen die genaue Fassung getauscht wird.
    public enum Einwechseln: Equatable, Sendable {
        /// Jetzt, an derselben Stelle.
        case jetzt
        /// Noch nicht — ein Sprung läuft, das Item ist nicht bereit, oder es
        /// spielt gerade und liegt richtig: dann beim nächsten Sprung oder
        /// in der nächsten Pause.
        case spaeter
        /// Für dieses Item nicht mehr: das Ende ist zu nah. Spulen lohnt dort
        /// nicht mehr, und das nächste Lied soll ungestört übergehen.
        case nicht
    }

    /// So viel muss vom Lied noch übrig sein, damit sich der Tausch lohnt.
    public static let mindestrest: TimeInterval = 4

    /// **Getauscht wird, wo man es nicht hört.**
    ///
    /// Gemessen am 25.09. (Simulator, Ton im Tap mitgeschnitten): ein Tausch
    /// mitten im Spielen lässt den Ton 0,44–0,6 s stehen. Lückenlos ginge es
    /// nur, wenn das neue Item hinter dem laufenden im `AVQueuePlayer`
    /// vorbereitet wäre — das tut AVFoundation hinter einem Stream nicht,
    /// auch nicht, wenn er ganz geladen ist (nach 40 s noch `unknown`). Ein
    /// Tausch zusammen mit einem Sprung braucht dagegen nur 30–60 ms länger
    /// als der Sprung allein. Darum:
    /// - in der Pause (und während der Player wartet) sofort;
    /// - beim nächsten Sprung von Hand — der landet dann gleich genau;
    /// - mitten im Spielen nur, wenn ein ungenauer Sprung das Item
    ///   `verrutscht` hat: Ton und Anzeige (Liedtext) liegen dann
    ///   auseinander, und der Tausch holt den Ton an die angezeigte Stelle.
    public static func einwechseln(stelle: TimeInterval, dauer: TimeInterval?, springt: Bool,
                                   bereit: Bool, laeuft: Bool, verrutscht: Bool) -> Einwechseln {
        if let dauer, dauer - stelle < mindestrest { return .nicht }
        if springt || !bereit { return .spaeter }
        if laeuft, !verrutscht { return .spaeter }
        return .jetzt
    }

    /// **Wie weit voraus getauscht wird**, wenn es läuft: das neue Item
    /// lädt vorab, getauscht wird, wenn das alte an dieser Stelle ankommt.
    /// Steht es, sofort an derselben Stelle.
    public static func vorlauf(laeuft: Bool) -> TimeInterval { laeuft ? 0.35 : 0 }

    /// **Ein Sprung wartet auf die Datei, wenn sie gleich da ist** — dann
    /// landet er einmal richtig statt erst falsch und kurz danach richtig.
    /// Sonst springt er wie bisher (ungenau), und der Tausch holt die
    /// Stelle nach, sobald die Datei da ist.
    public static let sprungwartezeit: TimeInterval = 1

    public static func sprungAbwarten(restzeit: TimeInterval?) -> Bool {
        guard let restzeit else { return false }
        return restzeit < sprungwartezeit
    }

    /// **Wie lange das Laden noch dauert**, aus dem Anteil und der Zeit seit
    /// dem Beginn — gleichmäßig weitergerechnet. `nil`, solange die Zahl
    /// nichts taugt (zu früh, noch nichts angekommen).
    public static func restzeit(anteil: Double, seit: TimeInterval) -> TimeInterval? {
        guard seit >= 0.25, anteil > 0.01 else { return nil }
        if anteil >= 1 { return 0 }
        return seit * (1 - anteil) / anteil
    }
}
