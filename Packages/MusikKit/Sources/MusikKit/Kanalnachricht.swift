import Foundation

/// **Was ein anderes Gerät von Swiftly Music will** — aus Jellyfins
/// Steuerkanal gelesen, schon in unsere Begriffe übersetzt.
///
/// Drei Nachrichtenarten tragen Befehle: `Play` (eine Schlange spielen oder
/// ergänzen), `Playstate` (Pause, Weiter, Springen …) und `GeneralCommand`
/// (Lautstärke, Wiederholen, Mischen). Alles andere, was der Server schickt
/// (`UserDataChanged`, `LibraryChanged` …), ist für die Wiedergabe egal.
public enum Fernauftrag: Sendable, Equatable {

    /// Wie eine geschickte Liste in die Schlange kommt — Jellyfins
    /// `PlayCommand`.
    public enum Einreihung: String, Sendable, Equatable {
        /// `PlayNow`: die Schlange ersetzen und bei `ab` anfangen.
        case jetzt = "PlayNow"
        /// `PlayNext`: direkt nach dem laufenden Lied.
        case alsNaechstes = "PlayNext"
        /// `PlayLast`: hinten an.
        case hintenAn = "PlayLast"
        /// `PlayShuffle`: ersetzen und mischen.
        case gemischt = "PlayShuffle"
        /// `PlayInstantMix`: einen Sofortmix aus dem ersten Titel.
        case mix = "PlayInstantMix"
    }

    case spielen(ids: [String], ab: Int, stelle: TimeInterval?, wie: Einreihung)
    case pause
    case weiter
    case umschalten
    case stopp
    case naechstes
    case voriges
    /// Absolute Stelle in Sekunden.
    case springen(TimeInterval)
    /// `FastForward`/`Rewind` — ein Stück vor oder zurück.
    case vor
    case zurueck
    /// 0 bis 100.
    case lautstaerke(Int)
    /// `true` stumm, `false` laut, `nil` umschalten.
    case stumm(Bool?)
    case wiederholung(Warteschlange.Wiederholung)
    case mischen(Bool)
}

/// Eine Nachricht aus dem Steuerkanal.
public enum Kanalnachricht: Sendable, Equatable {
    /// `ForceKeepAlive`: der Server will sofort ein Lebenszeichen.
    case lebenszeichenVerlangt
    case auftrag(Fernauftrag)
    /// Etwas anderes — nur der Name, für das Protokoll.
    case sonstiges(String)

    /// **Liest eine Textnachricht des Kanals.** `nil`, wenn es gar kein
    /// Jellyfin-Umschlag ist.
    ///
    /// Gelesen wird mit `JSONSerialization` und von Hand, nicht über
    /// `Decodable`: Jellyfin schreibt Zahlen je nach Befehl als Zahl oder
    /// als Text (`"Volume": "40"` in `Arguments`, `SeekPositionTicks` als
    /// Zahl), und ein unbekannter Befehl darf die übrigen nicht mitnehmen.
    public static func lesen(_ text: String) -> Kanalnachricht? {
        guard let daten = text.data(using: .utf8),
              let roh = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any],
              let art = roh["MessageType"] as? String else { return nil }
        let inhalt = roh["Data"] as? [String: Any] ?? [:]
        switch art {
        case "ForceKeepAlive":
            return .lebenszeichenVerlangt
        case "Play":
            return spielen(inhalt).map { .auftrag($0) } ?? .sonstiges(art)
        case "Playstate":
            guard let befehl = inhalt["Command"] as? String,
                  let auftrag = spielstand(befehl, ziel: zahl(inhalt["SeekPositionTicks"])) else {
                return .sonstiges(art)
            }
            return .auftrag(auftrag)
        case "GeneralCommand":
            guard let name = inhalt["Name"] as? String,
                  let auftrag = allgemein(name, werte: inhalt["Arguments"] as? [String: Any] ?? [:]) else {
                return .sonstiges(art)
            }
            return .auftrag(auftrag)
        default:
            return .sonstiges(art)
        }
    }

    static func spielen(_ inhalt: [String: Any]) -> Fernauftrag? {
        let ids = (inhalt["ItemIds"] as? [Any] ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return nil }
        // Ältere Server schicken den Befehl als Zahl (Stelle im Aufzählungstyp).
        let wie: Fernauftrag.Einreihung
        if let text = inhalt["PlayCommand"] as? String {
            guard let w = Fernauftrag.Einreihung(rawValue: text) else { return nil }
            wie = w
        } else if let n = zahl(inhalt["PlayCommand"]) {
            let folge: [Fernauftrag.Einreihung] = [.jetzt, .alsNaechstes, .hintenAn, .mix, .gemischt]
            guard n >= 0, Int(n) < folge.count else { return nil }
            wie = folge[Int(n)]
        } else {
            wie = .jetzt
        }
        let ab = min(max(Int(zahl(inhalt["StartIndex"]) ?? 0), 0), ids.count - 1)
        let stelle = zahl(inhalt["StartPositionTicks"]).flatMap { $0 > 0 ? $0 / 10_000_000 : nil }
        return .spielen(ids: ids, ab: ab, stelle: stelle, wie: wie)
    }

    static func spielstand(_ befehl: String, ziel: Double?) -> Fernauftrag? {
        switch befehl {
        case "Pause":         .pause
        case "Unpause":       .weiter
        case "PlayPause":     .umschalten
        case "Stop":          .stopp
        case "NextTrack":     .naechstes
        case "PreviousTrack": .voriges
        case "Seek":          ziel.map { .springen(max(0, $0 / 10_000_000)) }
        case "FastForward":   .vor
        case "Rewind":        .zurueck
        default:              nil
        }
    }

    static func allgemein(_ name: String, werte: [String: Any]) -> Fernauftrag? {
        switch name {
        case "SetVolume":
            guard let v = zahl(werte["Volume"]) else { return nil }
            return .lautstaerke(min(max(Int(v), 0), 100))
        case "Mute":       return .stumm(true)
        case "Unmute":     return .stumm(false)
        case "ToggleMute": return .stumm(nil)
        case "SetRepeatMode":
            switch werte["RepeatMode"] as? String {
            case "RepeatNone": return .wiederholung(.aus)
            case "RepeatAll":  return .wiederholung(.alles)
            case "RepeatOne":  return .wiederholung(.eines)
            default:           return nil
            }
        case "SetShuffleQueue":
            switch werte["ShuffleMode"] as? String {
            case "Shuffle": return .mischen(true)
            case "Sorted":  return .mischen(false)
            default:        return nil
            }
        default:
            return nil
        }
    }

    /// Eine Zahl, gleich ob als Zahl oder als Text geschickt.
    static func zahl(_ wert: Any?) -> Double? {
        if let n = wert as? NSNumber { return n.doubleValue }
        if let t = wert as? String { return Double(t) }
        return nil
    }
}

// MARK: - Was wir melden

/// **Die Fähigkeiten, die Swiftly Music dem Server meldet**
/// (`POST /Sessions/Capabilities/Full`).
///
/// **Jeder Name muss `GeneralCommandType` des Servers treffen** — ein
/// einziger falscher Wert lässt den Server die ganze Meldung verwerfen, und
/// dann ist die Sitzung für niemanden steuerbar (die Geschichte dazu steht
/// bei `JellyfinClient.faehigkeitenMelden()` in JellyfinKit: dort war es
/// `Playstate` statt `PlayState`). Gegen Jellyfins `GeneralCommandType`
/// abgeglichen, Wert für Wert.
///
/// Nur `Audio`: ein Film, den jemand an Swiftly Music schickt, hätte hier
/// keinen Platz.
public enum Musikfaehigkeiten {
    public static let befehle = ["Play", "PlayState", "PlayNext", "SetVolume", "Mute", "Unmute",
                                 "ToggleMute", "SetRepeatMode", "SetShuffleQueue"]

    public static func rumpf() -> Data {
        let werte: [String: Any] = [
            "PlayableMediaTypes": ["Audio"],
            "SupportedCommands": befehle,
            "SupportsMediaControl": true,
            "SupportsPersistentIdentifier": true,
        ]
        return (try? JSONSerialization.data(withJSONObject: werte, options: [.sortedKeys])) ?? Data()
    }
}
