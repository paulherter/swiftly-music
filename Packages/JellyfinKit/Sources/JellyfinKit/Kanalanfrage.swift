import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// **Die Anfrage für Jellyfins Steuerkanal (`/socket`) — für Swiftly Music.**
///
/// ``Fernsteuerung`` hört nur auf `Playstate` und meldet Video-Fähigkeiten;
/// Swiftly Music braucht dazu `Play` und `GeneralCommand` (Lautstärke,
/// Wiederholen, Mischen) und meldet nur `Audio`. Der Kanal selbst läuft
/// deshalb in `MusikKit` — der Ausweis aber muss **derselbe** sein wie bei
/// jedem anderen Aufruf, sonst landet der Kanal auf einer zweiten Sitzung
/// (die Falle steht bei ``Fernsteuerung/starten(bei:)``). Hier wird er
/// gebaut, nicht nachgebaut.
///
/// Rein hinzugefügt; an ``Fernsteuerung`` ändert sich nichts.
extension JellyfinClient {

    /// `ws(s)://…/socket?ApiKey=…&deviceId=…` mit eigenen Köpfen und dem
    /// `Authorization`-Kopf dieses Clients.
    ///
    /// **`ApiKey`, nicht `api_key`** — Jellyfin 12 kennt die alte
    /// Schreibweise nicht mehr (siehe ``Fernsteuerung/starten(bei:)``).
    public func steuerkanalAnfrage() throws -> URLRequest {
        let s = try requireSessionForReporting()
        guard var teile = URLComponents(url: s.serverURL.appendingPathComponent("socket"),
                                        resolvingAgainstBaseURL: false) else {
            throw JellyfinError.invalidServerURL
        }
        teile.scheme = s.serverURL.scheme == "http" ? "ws" : "wss"
        teile.queryItems = [
            URLQueryItem(name: "ApiKey", value: s.accessToken),
            URLQueryItem(name: "deviceId", value: geraeteKennung),
        ]
        guard let url = teile.url else { throw JellyfinError.invalidServerURL }
        var anfrage = URLRequest(url: url)
        anfrage.eigeneKoepfeSetzen()
        anfrage.setValue(ausweisFuerKanal, forHTTPHeaderField: "Authorization")
        return anfrage
    }
}
