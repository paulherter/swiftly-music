import Foundation

/// **Ein Sonos-Lautsprecher**, wie er in der Gruppenliste steht: seine
/// Kennung (`RINCON_…`), der Raumname und wo er antwortet.
public struct SonosLautsprecher: Sendable, Hashable, Identifiable {
    /// `RINCON_000E58…01400` — dieselbe Kennung, die `x-rincon:` braucht.
    public let id: String
    public let name: String
    /// `http://192.168.1.20:1400`
    public let basis: URL

    public init(id: String, name: String, basis: URL) {
        self.id = id
        self.name = name
        self.basis = basis
    }
}

/// **Eine Gruppe von Lautsprechern** — auch ein einzelner ist eine. Der
/// Koordinator spielt, die anderen hören auf ihn; alle Befehle zur
/// Wiedergabe gehen an ihn.
public struct SonosGruppe: Sendable, Hashable, Identifiable {
    /// `RINCON_…:1234` — ändert sich, sobald die Gruppe neu gebildet wird.
    public let id: String
    public let koordinator: SonosLautsprecher
    /// Der Koordinator zuerst, dann die anderen nach Namen.
    public let mitglieder: [SonosLautsprecher]

    public init(id: String, koordinator: SonosLautsprecher, mitglieder: [SonosLautsprecher]) {
        self.id = id
        self.koordinator = koordinator
        self.mitglieder = mitglieder
    }

    /// „Wohnzimmer", „Wohnzimmer + 2" — wie in der Sonos-App.
    public var name: String {
        mitglieder.count <= 1 ? koordinator.name : "\(koordinator.name) + \(mitglieder.count - 1)"
    }

    public func enthaelt(_ id: String) -> Bool { mitglieder.contains { $0.id == id } }
}

public enum SonosTopologie {

    /// **Die Gruppen aus `GetZoneGroupState`.** Der Wert kommt als
    /// maskiertes XML in der SOAP-Antwort; neuere Firmware legt
    /// `<ZoneGroupState>` um `<ZoneGroups>`, ältere nicht — beides geht.
    ///
    /// Weggelassen wird, was man nicht einzeln ansteuern kann: unsichtbare
    /// Mitglieder (die zweite Box eines Stereopaars, `Invisible="1"`) und
    /// Bridges und Boosts (`IsZoneBridge="1"`). Die Rücklautsprecher und der
    /// Sub einer Heimkinoanlage stehen als `Satellite` unter ihrem Hauptgerät
    /// und kommen gar nicht erst vor.
    public static func gruppen(_ zustand: String) -> [SonosGruppe] {
        guard let baum = SonosKnoten.lesen(zustand), let liste = baum.finde("ZoneGroups") else { return [] }
        var gruppen: [SonosGruppe] = []
        for g in liste.kinder("ZoneGroup") {
            guard let kid = g.attribute["Coordinator"], let gid = g.attribute["ID"] else { continue }
            let alle: [SonosLautsprecher] = g.kinder("ZoneGroupMember").compactMap { m in
                guard m.attribute["Invisible"] != "1", m.attribute["IsZoneBridge"] != "1",
                      let id = m.attribute["UUID"], let name = m.attribute["ZoneName"],
                      let ort = m.attribute["Location"], let basis = basis(ort) else { return nil }
                return SonosLautsprecher(id: id, name: name, basis: basis)
            }
            guard let koordinator = alle.first(where: { $0.id == kid }) else { continue }
            let andere = alle.filter { $0.id != kid }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            gruppen.append(SonosGruppe(id: gid, koordinator: koordinator, mitglieder: [koordinator] + andere))
        }
        return gruppen.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// `http://192.168.1.20:1400/xml/device_description.xml` → `http://192.168.1.20:1400`.
    public static func basis(_ ort: String) -> URL? {
        guard let url = URL(string: ort), let host = url.host(), let schema = url.scheme else { return nil }
        let teil = host.contains(":") ? "[\(host)]" : host
        return URL(string: "\(schema)://\(teil):\(url.port ?? 1400)")
    }

    /// **Das Bild eines Lautsprechers** aus seinem Modell (`modelName`):
    /// Soundbar, Verstärker, tragbar, sonst der Standlautsprecher.
    public static func zeichen(modell: String?) -> String {
        let m = (modell ?? "").lowercased()
        if ["arc", "beam", "ray", "playbar", "playbase"].contains(where: m.contains) { return "tv.and.hifispeaker.fill" }
        if ["port", "amp", "connect", "zp80", "zp90", "zp100", "zp120"].contains(where: m.contains) { return "hifireceiver.fill" }
        if ["roam", "move"].contains(where: m.contains) { return "speaker.fill" }
        return "hifispeaker.fill"
    }

    /// Alle Lautsprecher aus allen Gruppen, nach Namen.
    public static func lautsprecher(_ gruppen: [SonosGruppe]) -> [SonosLautsprecher] {
        gruppen.flatMap(\.mitglieder)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// **Was `device_description.xml` über einen Lautsprecher sagt.**
public struct SonosBeschreibung: Sendable, Equatable {
    /// Ohne das `uuid:` davor.
    public let id: String
    public let raum: String
    public let modell: String?

    public static func lesen(_ daten: Data) -> SonosBeschreibung? {
        guard let baum = SonosKnoten.lesen(daten), let geraet = baum.finde("device") else { return nil }
        // Das erste `device` ist der Lautsprecher, die darunter sind
        // seine Teildienste (MediaServer, MediaRenderer).
        guard let udn = geraet.kind("UDN")?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              !udn.isEmpty else { return nil }
        let id = udn.hasPrefix("uuid:") ? String(udn.dropFirst(5)) : udn
        let raum = geraet.kind("roomName")?.text ?? geraet.kind("friendlyName")?.text ?? id
        return SonosBeschreibung(id: id, raum: raum.trimmingCharacters(in: .whitespacesAndNewlines),
                                 modell: geraet.kind("modelName")?.text)
    }
}

// MARK: - Im Blatt

/// **Eine Zeile im Blatt „Abspielen auf"**: ein Lautsprecher, in der Gruppe,
/// in der er gerade steht. Die Zeilen einer Gruppe stehen zusammen, der
/// Koordinator vorn; die Gruppe mit unserer Musik steht ganz oben.
public struct Sonoszeile: Sendable, Equatable, Identifiable {
    public let lautsprecher: SonosLautsprecher
    public let gruppe: SonosGruppe
    /// Die letzte Zeile ihrer Gruppe — dort endet die Karte.
    public let ende: Bool
    /// In der Gruppe, die unsere Musik spielt.
    public let unser: Bool

    public var id: String { lautsprecher.id }
    /// Die erste Zeile ihrer Gruppe: der Koordinator.
    public var kopf: Bool { gruppe.koordinator.id == lautsprecher.id }

    /// **Die Zeilen, wie sie gerade stehen sollen** — mit dem, was eben
    /// angetippt und noch nicht bestätigt ist (`vorgemerkt`: Lautsprecher →
    /// soll in der Gruppe von `ziel` sein). Geht der Koordinator, führt der
    /// nächste der Gruppe, wie bei ``Sonossteuerung/koordinationUebergeben(an:)``.
    /// `ziel` darf schon der neue Koordinator sein, bevor die Gruppen es wissen.
    public static func zeilen(_ gruppen: [SonosGruppe], ziel: String?, vorgemerkt: [String: Bool]) -> [Sonoszeile] {
        var liste = gruppen.map { (id: $0.id, mitglieder: $0.mitglieder) }
        let zi = ziel.flatMap { z in liste.firstIndex { $0.mitglieder.contains { $0.id == z } } }
        let unsere = zi.map { liste[$0].id }
        if let zi {
            let alle = gruppen.flatMap(\.mitglieder)
            for (lid, rein) in vorgemerkt.sorted(by: { $0.key < $1.key }) {
                guard let l = alle.first(where: { $0.id == lid }) else { continue }
                let drin = liste[zi].mitglieder.contains { $0.id == lid }
                guard rein != drin else { continue }
                for i in liste.indices { liste[i].mitglieder.removeAll { $0.id == lid } }
                if rein {
                    liste[zi].mitglieder.append(l)
                } else {
                    liste.append((id: "allein:" + lid, mitglieder: [l]))
                }
            }
        }
        let sortiert = liste.compactMap { g -> SonosGruppe? in
            guard let k = g.mitglieder.first else { return nil }
            let andere = g.mitglieder.dropFirst()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return SonosGruppe(id: g.id, koordinator: k, mitglieder: [k] + andere)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // Wo unsere Musik läuft, steht oben — wie in der Sonos-App.
        .sorted { a, b in a.id == unsere && b.id != unsere }
        return sortiert.flatMap { g in
            g.mitglieder.enumerated().map { i, l in
                Sonoszeile(lautsprecher: l, gruppe: g, ende: i == g.mitglieder.count - 1, unser: g.id == unsere)
            }
        }
    }
}
