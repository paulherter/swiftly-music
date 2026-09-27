import Foundation
import JellyfinKit
import MusikKit
import SubsonicKit
import SwiftUI

/// **Ein Fehler als Satz: was war, und was jetzt.**
///
/// Jellyfin- und Netzfehler übersetzt JellyfinKit (`lesbarerFehler`, eine
/// Regel für alle Plattformen); die Subsonic-Codes stehen hier.
enum Fehlertext {

    /// Jeder Fehler, der als Satz vor jemandem steht, geht auch ins
    /// Protokoll — dann steht in „Protokoll teilen", was er gesehen hat.
    static func lesbar(_ fehler: any Error) -> String {
        Protokoll.schreib("[Fehler] \(geschwaerzt(String(describing: fehler)))")
        guard let s = fehler as? SubsonicFehler else { return lesbarerFehler(fehler) }
        switch s {
        case .adresse:
            // Derselbe Satz wie für Jellyfin, aus dem Paket statt getippt.
            return lesbarerFehler(JellyfinError.invalidServerURL)
        case .keinSubsonic:
            return String(localized: "Unter dieser Adresse antwortet kein Musikserver.")
        case let .http(status):
            return lesbarerFehler(JellyfinError.http(status: status, body: nil))
        case .dekodieren:
            return String(localized: "Die Antwort des Servers war unverständlich.")
        case let .server(code, text):
            switch code {
            case 40, 44:
                return String(localized: "Benutzername oder Passwort stimmt nicht.")
            case 41, 42, 43:
                return String(localized: "Der Server lässt diese Art der Anmeldung nicht zu.")
            case 50:
                return String(localized: "Dieses Konto darf das nicht.")
            case 70:
                return String(localized: "Das gibt es auf dem Server nicht mehr.")
            case 20, 30:
                return String(localized: "Server und App sprechen verschiedene Fassungen der Schnittstelle.")
            default:
                if let text, !text.isEmpty {
                    return String(localized: "Der Server meldet: \(text)")
                }
                return String(localized: "Der Server hat einen Fehler gemeldet.")
            }
        }
    }

    /// **Anmeldung aus einer Fehlerbeschreibung tilgen**, bevor sie ins
    /// Protokoll geht — zweite Schranke, falls doch einmal eine rohe
    /// Anfrage-URL bei einem Fehler ankommt (Subsonic trägt die Anmeldung in
    /// `u=`/`t=`/`s=`, im Rückfall `p=enc:<hex>`). JellyfinKits
    /// `Protokollschwaerzung` kennt nur ganze Namen wie `token`, nicht diese
    /// einbuchstabigen Abfragewerte.
    private static func geschwaerzt(_ text: String) -> String {
        text.replacingOccurrences(
            of: "(?i)([?&](?:u|t|s|p|apikey|api_key|token)=)[^&\\s]*",
            with: "$1•••",
            options: .regularExpression
        )
    }
}

// MARK: - Störung

/// **Eine Seite, die nicht laden konnte** — und ob der Server gar nicht
/// geantwortet hat. Nur dann gilt der Satz des Players („Server ist
/// abgetaucht"); hat er geantwortet, aber abgelehnt, wäre das eine falsche
/// Fehlersuche, und es steht, was er gesagt hat.
struct Stoerung: Equatable {
    let text: String
    let abgetaucht: Bool

    init(_ fehler: any Error) {
        text = Fehlertext.lesbar(fehler)
        abgetaucht = Self.ohneAntwort(fehler)
    }

    /// Kein Netz zum Server — ohne einen Fehler in der Hand.
    static let keineVerbindung = Stoerung(text: "", abgetaucht: true)

    private init(text: String, abgetaucht: Bool) {
        self.text = text
        self.abgetaucht = abgetaucht
    }

    private static func ohneAntwort(_ fehler: any Error) -> Bool {
        if fehler is URLError { return true }
        if let j = fehler as? JellyfinError {
            switch j {
            case .netz, .transport: return true
            case let .http(status, _): return (502...504).contains(status)
            default: return false
            }
        }
        if case let .http(status) = fehler as? SubsonicFehler { return (502...504).contains(status) }
        return false
    }
}

/// **Der Störhinweis einer ganzen Seite** — Zeichen, Wortlaut und Knopf wie
/// im Player (`Leerzustand` mit „Server ist abgetaucht" in `HomeView`,
/// `Stoerhinweis` in `Stil.swift`): ein sachlicher erster Satz, ein zweiter
/// mit Haltung, „Erneut versuchen".
struct Stoerhinweis: View {
    let stoerung: Stoerung
    let erneut: () -> Void
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        if stoerung.abgetaucht {
            Leerzustand(symbol: "externaldrive.badge.xmark",
                        kopfzeile: Text("Server ist abgetaucht"),
                        text: Text("\(adresse) antwortet nicht. Läuft er noch, oder hängt das WLAN?"),
                        knopf: (Text("Erneut versuchen"), erneut))
        } else {
            Leerzustand(symbol: "externaldrive.badge.xmark",
                        kopfzeile: Text("Das hat nicht geklappt"),
                        text: Text(verbatim: stoerung.text),
                        knopf: (Text("Erneut versuchen"), erneut))
        }
    }

    /// Wie im Player: der Rechner, sonst „Der Server".
    private var adresse: String {
        modell.quelle?.konto.server.host() ?? String(localized: "Der Server")
    }
}
