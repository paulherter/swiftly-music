import Foundation
import JellyfinKit

/// **Connect über Jellyfin** — andere Geräte sehen, steuern, und selbst
/// steuerbar sein.
///
/// Jellyfin hat alles, was es dafür braucht: `GET /Sessions` nennt jedes
/// Gerät samt Schlange und Stelle, `POST /Sessions/{id}/Playing…` schickt
/// ihm Befehle, und der Steuerkanal bringt fremde Befehle zu uns. Nichts
/// davon muss Swiftly Music selbst verteilen.
extension JellyfinQuelle {

    /// **Sagt dem Server, dass diese Sitzung Musik annimmt**
    /// (``Musikfaehigkeiten``). Ohne das bleibt sie in Jellyfin-Web grau,
    /// und `controllableByUserId` liefert sie keinem anderen Gerät.
    public func faehigkeitenMelden() async throws {
        _ = try await client.rohdaten("Sessions/Capabilities/Full", methode: "POST",
                                      rumpf: Musikfaehigkeiten.rumpf())
    }

    /// Der Steuerkanal für diese Anmeldung.
    public func steuerkanal() async throws -> Steuerkanal {
        Steuerkanal(anfrage: try await client.steuerkanalAnfrage())
    }

    /// **Alle Sitzungen, die dieses Konto steuern darf** — ungefiltert; was
    /// davon angeboten wird, entscheidet ``Geraeteliste``.
    ///
    /// `activeWithinSeconds` wie bei Jellyfin-Web: ein Browserfenster, das
    /// eine Viertelstunde nichts getan hat, steht trotzdem noch bereit.
    public func sitzungen() async throws -> [Musiksitzung] {
        let daten = try await client.rohdaten("Sessions", abfrage: [
            .init(name: "controllableByUserId", value: konto.benutzerID),
            .init(name: "activeWithinSeconds", value: "960"),
        ])
        let roh: [Vielleicht<JSitzung>]
        do {
            roh = try JSONDecoder().decode([Vielleicht<JSitzung>].self, from: daten)
        } catch {
            throw JellyfinError.decoding(String(describing: error))
        }
        let abgefragt = Date()
        return roh.compactMap(\.wert).map {
            var sitzung = $0.musiksitzung(liedAus)
            sitzung.abgefragt = abgefragt
            return sitzung
        }
    }

    /// Nur die Geräte, die in der Liste stehen dürfen.
    public func geraete() async throws -> [Musiksitzung] {
        Geraeteliste.auswahl(try await sitzungen(), eigeneGeraeteID: geraeteID,
                             eigeneBenutzerID: konto.benutzerID, programme: Geraeteliste.swiftlyProgramme)
    }

    /// Einen Befehl an ein anderes Gerät.
    public func fern(_ aktion: Fernaktion, an sitzung: String) async throws {
        let a = Fernbedienung.anfrage(aktion, an: sitzung)
        _ = try await client.rohdaten(a.pfad, methode: "POST", abfrage: a.abfrage, rumpf: a.rumpf)
    }

    /// **Lieder nach Kennung, in derselben Folge** — für eine Schlange, die
    /// ein anderes Gerät schickt oder die hier weiterlaufen soll. Mit
    /// Dateiangaben, damit der Spieler weiß, ob er direkt spielen kann.
    /// In Bündeln zu 100: die Kennungen stehen in der Adresse.
    public func lieder(ids: [String]) async throws -> [Lied] {
        guard !ids.isEmpty else { return [] }
        var nachID: [String: Lied] = [:]
        var reste = Array(Set(ids))
        while !reste.isEmpty {
            let teil = Array(reste.prefix(100))
            reste.removeFirst(teil.count)
            let daten = try await client.rohdaten("Items", abfrage: [
                .init(name: "userId", value: konto.benutzerID),
                .init(name: "Ids", value: teil.joined(separator: ",")),
                .init(name: "Fields", value: Self.liedFelder),
                .init(name: "EnableUserData", value: "true"),
                .init(name: "EnableImageTypes", value: "Primary"),
                .init(name: "ImageTypeLimit", value: "1"),
            ])
            let liste = try JSONDecoder().decode(JListe.self, from: daten)
            for e in liste.eintraege { nachID[e.id] = liedAus(e) }
        }
        return ids.compactMap { nachID[$0] }
    }
}
