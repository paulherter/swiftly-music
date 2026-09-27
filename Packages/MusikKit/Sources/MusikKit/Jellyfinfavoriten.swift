import Foundation
import JellyfinKit

/// **Favoriten auf Jellyfin: versionsfest, und gegen das eigene Melden.**
///
/// **Die Falle (gemessen am 24.09.2026 gegen den öffentlichen Demo-Server
/// `demo.jellyfin.org/stable`, Jellyfin 12.1.0):** Wer ein Lied
/// favorisiert, *während es läuft*, verliert das Herz mit der nächsten
/// Meldung. `Sessions/Playing/Progress` und `Sessions/Playing/Stopped`
/// schreiben die Nutzerdaten des Lieds zurück, und zwar aus dem Stand, den
/// die Sitzung beim Start gelesen hat (`SessionManager.OnPlaybackProgress`
/// über `session.FullNowPlayingItem`). Protokoll des Versuchs:
///
/// ```
/// Start → Herz an (IsFavorite true) → Progress → IsFavorite false
/// Start → Herz aus (false) → Progress → true → Herz aus → Stopped → true
/// Herz aus nach Stopped → false, bleibt es auch beim nächsten Start
/// ```
///
/// Swiftly Music meldet alle zehn Sekunden — das Herz im Minispieler und im
/// Wiedergabeblatt hielt auf dem Server also höchstens zehn Sekunden. In der
/// App stand es trotzdem (`Musikmodell.neueLieblinge`), bis die
/// Lieblingssongs das nächste Mal vom Server kamen.
///
/// **Deshalb merkt sich die Quelle jedes umgeschaltete Lied** und setzt den
/// Stand nach jeder Meldung zu diesem Lied noch einmal. Nach `Stopped` ist
/// es erledigt: der nächste Start liest den Stand frisch.
///
/// **Zwei Wege zum Setzen.** `UserFavoriteItems/{id}` gibt es seit 10.9;
/// 10.8 kennt nur `Users/{userId}/FavoriteItems/{id}`. Der alte Weg besteht
/// in 12.1 weiter (ebenfalls gemessen), er ist dort nur als veraltet
/// markiert. Also zuerst der neue, und nach einem 404 für diese Sitzung der
/// alte.
final class Favoritenstand: @unchecked Sendable {
    private let schloss = NSLock()
    private var umgeschaltet: [String: Bool] = [:]
    private var _alterWeg = false

    /// Der Server kennt nur `Users/{userId}/FavoriteItems` (10.8).
    var alterWeg: Bool {
        get { schloss.withLock { _alterWeg } }
        set { schloss.withLock { _alterWeg = newValue } }
    }

    func merken(_ id: String, an: Bool) {
        schloss.withLock { umgeschaltet[id] = an }
    }

    func stand(_ id: String) -> Bool? {
        schloss.withLock { umgeschaltet[id] }
    }

    func vergessen(_ id: String) {
        schloss.withLock { _ = umgeschaltet.removeValue(forKey: id) }
    }
}

extension JellyfinQuelle {

    /// Der neue Weg (seit 10.9).
    static func favoritpfad(_ id: String) -> String { "UserFavoriteItems/\(id)" }

    /// Der alte Weg (10.8, in 12.1 noch vorhanden).
    static func alterFavoritpfad(_ id: String, benutzer: String) -> String {
        "Users/\(benutzer)/FavoriteItems/\(id)"
    }

    /// Setzt oder löscht den Favoriten — über den Weg, den der Server kennt.
    func favoritSenden(_ id: String, an: Bool) async throws {
        let methode = an ? "POST" : "DELETE"
        if !favoritenstand.alterWeg {
            do {
                _ = try await client.rohdaten(Self.favoritpfad(id), methode: methode,
                                              abfrage: [.init(name: "userId", value: benutzerID)])
                return
            } catch let JellyfinError.http(status, _) where status == 404 || status == 405 {
                // Vor 10.9 gibt es den Pfad nicht. Fehlt nur das Lied, sagt
                // der alte Weg dasselbe — und er gilt auf jedem Server.
                favoritenstand.alterWeg = true
            }
        }
        _ = try await client.rohdaten(Self.alterFavoritpfad(id, benutzer: benutzerID), methode: methode)
    }

    /// Nach einer Meldung zu einem umgeschalteten Lied: den Stand noch einmal
    /// setzen (siehe ``Favoritenstand``).
    func favoritNachMeldung(_ meldung: Wiedergabemeldung) async {
        let stand: Wiedergabestand
        let ende: Bool
        switch meldung {
        case let .beginn(s), let .fortschritt(s): stand = s; ende = false
        case let .ende(s): stand = s; ende = true
        case .gehoert: return
        }
        let id = stand.lied.id
        guard let an = favoritenstand.stand(id) else { return }
        try? await favoritSenden(id, an: an)
        if ende { favoritenstand.vergessen(id) }
    }

    /// **Die Lieblingssongs, ohne Eingrenzung auf die gewählte Bibliothek.**
    ///
    /// Das Herz gibt es auch an Liedern von außerhalb — im Sofortmix, über
    /// Connect, in einer Warteschlange von einem anderen Gerät. Mit `ParentId`
    /// stand so ein Lied nach dem Setzen kurz in den Lieblingssongs und war
    /// nach dem nächsten Laden weg. Subsonic (`getStarred2`) liefert
    /// ebenfalls alle, ohne Ordner.
    static func lieblingsabfrage(benutzer: String) -> [URLQueryItem] {
        [.init(name: "userId", value: benutzer)]
            + liste("Audio", felder: liedFelder)
            + [.init(name: "Filters", value: "IsFavorite")]
            + sortierung("SortName", absteigend: false)
    }
}
