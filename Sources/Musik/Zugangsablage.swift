import Foundation
import JellyfinKit
import MusikKit
import SubsonicKit
import UIKit

/// **Die Anmeldung, wie sie im Schlüsselbund liegt.**
///
/// Bei Jellyfin das Zugangsmerkmal (kein Passwort), bei Subsonic der Zugang
/// samt Passwort — die Token-Anmeldung braucht es für jedes Salz, und der
/// Rückfall bei LDAP-Konten ohnehin. Deshalb Schlüsselbund, nie
/// Voreinstellungen (`Sources/Shared/Keychain.swift`, eigene Zugriffsgruppe
/// `de.paulherter.swiftly.music`).
struct GespeicherterZugang: Codable, Equatable {
    struct Jellyfin: Codable, Equatable {
        var server: URL
        var token: String
        var benutzerID: String
        var benutzername: String
    }

    var serverart: Serverart
    var jellyfin: Jellyfin?
    var subsonic: SubsonicZugang?
    /// Wie der Server heißt, für den Kopf der Kontoseite.
    var servername: String
    /// „Jellyfin 10.10.3", „Navidrome 0.64.0".
    var serverbeschreibung: String

    init(serverart: Serverart, jellyfin: Jellyfin? = nil, subsonic: SubsonicZugang? = nil,
         servername: String, serverbeschreibung: String) {
        self.serverart = serverart
        self.jellyfin = jellyfin
        self.subsonic = subsonic
        self.servername = servername
        self.serverbeschreibung = serverbeschreibung
    }

    private enum K: String, CodingKey { case serverart, jellyfin, subsonic, servername, serverbeschreibung }

    /// Von Hand, jeder Wert gegen seine Vorgabe — eine spätere Fassung mit
    /// einem Feld mehr darf die Anmeldung nicht wegwerfen (`Fallen/ablage.md`).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        serverart = try c.decode(Serverart.self, forKey: .serverart)
        jellyfin = try? c.decodeIfPresent(Jellyfin.self, forKey: .jellyfin)
        subsonic = try? c.decodeIfPresent(SubsonicZugang.self, forKey: .subsonic)
        servername = (try? c.decodeIfPresent(String.self, forKey: .servername)) ?? ""
        serverbeschreibung = (try? c.decodeIfPresent(String.self, forKey: .serverbeschreibung)) ?? ""
    }
}

extension GespeicherterZugang: Kontoeintrag {
    /// Wem die Anmeldung gehört — dieselbe Kennung, die die Quelle trägt
    /// (`JellyfinQuelle.konto`, `SubsonicQuelle.konto`).
    var kontokennung: Kontokennung {
        if let j = jellyfin { return Kontokennung(server: j.server, benutzerID: j.benutzerID) }
        if let s = subsonic { return Kontokennung(server: s.server, benutzerID: s.benutzer) }
        return Kontokennung(server: URL(string: "about:blank")!, benutzerID: servername)
    }

    var benutzername: String { jellyfin?.benutzername ?? subsonic?.benutzer ?? "" }

    /// Das Profilbild, ohne dass dafür eine Quelle stehen muss — für die
    /// Konten, die gerade nicht gelten. Jellyfin gibt Benutzerbilder ohne
    /// Anmeldung heraus; fehlt eins, bleibt der Anfangsbuchstabe.
    var profilbild: URL? {
        if let j = jellyfin {
            var teile = URLComponents(url: j.server.appendingPathComponent("Users/\(j.benutzerID)/Images/Primary"),
                                      resolvingAgainstBaseURL: false)
            teile?.queryItems = [.init(name: "fillWidth", value: "120"), .init(name: "quality", value: "90")]
            return teile?.url
        }
        // Subsonic rechnet jede Adresse mit neuem Salz — sie wäre bei jedem
        // Zeichnen eine andere und würde endlos neu geladen.
        return nil
    }
}

/// **Alle Konten im Schlüsselbund**, als eine ``Kontenreihe``. Bis 1.0.4 lag
/// hier genau ein Zugang unter `musik.zugang`; der wird beim ersten Lesen
/// zum ersten Konto der Reihe (``Kontenreihe/ausAblage(reihe:einzelne:)``).
enum Zugangsablage {
    private static let schluessel = "musik.konten"
    private static let alterSchluessel = "musik.zugang"

    static func lesen() -> Kontenreihe<GespeicherterZugang>? {
        Kontenreihe.ausAblage(reihe: Keychain.load(key: schluessel), einzelne: Keychain.load(key: alterSchluessel))
    }

    /// `nil` löscht alles — das letzte Konto ist abgemeldet.
    static func schreiben(_ reihe: Kontenreihe<GespeicherterZugang>?) {
        guard let reihe else {
            Keychain.delete(key: schluessel)
            Keychain.delete(key: alterSchluessel)
            return
        }
        do {
            try Keychain.save(JSONEncoder().encode(reihe), key: schluessel)
            // Die alte Einzelablage erst weg, wenn die Reihe sicher liegt.
            Keychain.delete(key: alterSchluessel)
        } catch {
            Protokoll.schreib("[Konto] Ablage ließ sich nicht schreiben: \(error.localizedDescription)")
        }
    }
}

/// **Die Gerätekennung, unter der Jellyfin diese App führt.**
///
/// Eine eigene, nicht die des Players: Jellyfin hält je Gerätekennung eine
/// Anmeldung. Mit derselben Kennung nähme die Anmeldung von Swiftly Music
/// dem Player auf demselben iPhone seine weg (wie `AppModel.deviceID`,
/// nur unter eigenem Schlüssel).
enum Geraetekennung {
    private static let schluessel = "musik.geraetekennung"

    static let wert: String = {
        if let da = UserDefaults.standard.string(forKey: schluessel), !da.isEmpty { return da }
        let neu = "swiftly-music-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(neu, forKey: schluessel)
        return neu
    }()
}

/// Baut aus einer gespeicherten Anmeldung die Quelle.
enum Quellenbau {
    static let programm = "Swiftly Music"

    @MainActor
    static func quelle(aus zugang: GespeicherterZugang) async -> (any Musikquelle)? {
        switch zugang.serverart {
        case .jellyfin:
            guard let j = zugang.jellyfin else { return nil }
            let sitzung = Session(accessToken: j.token, userID: j.benutzerID, userName: j.benutzername,
                                  serverURL: j.server)
            let client = JellyfinClient(baseURL: j.server, deviceID: Geraetekennung.wert,
                                        deviceName: UIDevice.current.name, programm: programm,
                                        session: sitzung)
            return JellyfinQuelle(client: client, sitzung: sitzung, geraeteID: Geraetekennung.wert)
        case .subsonic:
            guard let s = zugang.subsonic else { return nil }
            return SubsonicQuelle(client: SubsonicClient(zugang: s, sitzung: .ortsnetzfaehig))
        }
    }
}
