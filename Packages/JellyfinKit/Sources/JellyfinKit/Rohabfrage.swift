import Foundation
// Auf Linux liegt URLSession nicht in Foundation, sondern in einem
// eigenen Modul. Auf Apple-Plattformen gibt es das Modul nicht — der
// Import ist deshalb bedingt und dort wirkungslos.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// **Eine Anfrage mit dem Ausweis dieses Clients — für Endpunkte, die das
/// Paket selbst nicht abfragt.**
///
/// Für Swiftly Music (Paket `MusikKit`). Musik fragt andere Felder und
/// Endpunkte ab als der Player — `/Artists/AlbumArtists`,
/// `/Items/{id}/InstantMix`, `/Audio/{id}/Lyrics` — und meldet die Wiedergabe
/// mit eigenem Rumpf (`PlayMethod` und `PlaySessionId` je Lied). Statt den
/// `Authorization`-Kopf dort ein zweites Mal zu bauen, geht die Anfrage hier
/// durch: derselbe Kopf, dieselbe Gerätekennung, dieselben eigenen Köpfe und
/// dieselbe Fehlerregel wie bei jedem anderen Aufruf.
///
/// Rein hinzugefügt; am übrigen Paket ändert sich nichts.
extension JellyfinClient {

    /// Schickt die Anfrage und gibt den Rumpf der Antwort zurück.
    ///
    /// - Parameters:
    ///   - pfad: ohne führenden Schrägstrich, etwa `Items/123/InstantMix`.
    ///   - rumpf: fertiges JSON; setzt `Content-Type: application/json`.
    /// - Throws: ``JellyfinError`` — `.http` bei einem Status außerhalb von
    ///   2xx, `.netz`/`.zertifikat`, wenn die Anfrage nicht durchkam.
    public func rohdaten(_ pfad: String, methode: String = "GET",
                         abfrage: [URLQueryItem] = [], rumpf: Data? = nil) async throws -> Data {
        var anfrage = try rohAnfrage(pfad, method: methode, query: abfrage)
        if let rumpf {
            anfrage.setValue("application/json", forHTTPHeaderField: "Content-Type")
            anfrage.httpBody = rumpf
        }
        let daten: Data
        let antwort: URLResponse
        do {
            (daten, antwort) = try await rohSitzung.data(for: anfrage)
        } catch {
            throw JellyfinError(anfrage: error)
        }
        guard let http = antwort as? HTTPURLResponse else {
            throw JellyfinError.transport("Keine HTTP-Antwort.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            // Wie in `send`: ein Vorposten, der gleich ablehnt, schickt seine
            // Seite mit — Jellyfin selbst lehnt nie mit HTML ab.
            if [401, 403].contains(http.statusCode), Eigenkoepfe.anmeldeseite(http) {
                throw JellyfinError.transport(Eigenkoepfe.anmeldeseiteText)
            }
            throw JellyfinError.http(status: http.statusCode,
                                     body: String(data: daten.prefix(400), encoding: .utf8))
        }
        return daten
    }
}
