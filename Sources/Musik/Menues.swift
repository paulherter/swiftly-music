import MusikKit
import SwiftUI

/// **Die Handlungen für „Mehr" und langen Druck** — je Art eine Liste, damit
/// dieselbe Handlung überall gleich heißt (`VERHALTEN.md` D7). Sie gehen in
/// Swiftlys eigenes Blatt (`Handlungsebene`), nicht in ein Systemmenü.
@MainActor
enum Handlungen {

    static func album(_ album: Album, _ modell: Musikmodell) -> Handlungsliste {
        var liste = [
            Handlung(text: String(localized: "Abspielen"), zeichen: .abspielen) {
                Task { await modell.abspielen(.album(album)) }
            },
            Handlung(text: String(localized: "Als Nächstes spielen"),
                     symbol: "text.line.first.and.arrowtriangle.forward") {
                Task { await modell.alsNaechstes(.album(album)) }
            },
            Handlung(text: String(localized: "Hinten anstellen"),
                     symbol: "text.line.last.and.arrowtriangle.forward") {
                Task { await modell.hintenAn(.album(album)) }
            },
            Handlung(text: String(localized: "Zu Playlist hinzufügen"), symbol: "text.badge.plus") {
                Task { if let lieder = await modell.lieder(.album(album)) { modell.zuPlaylist(lieder) } }
            },
            Handlung(text: String(localized: "Sofortmix"), zeichen: .sofortmix) {
                Task { await modell.sofortmix(.album(album)) }
            },
        ]
        if let id = album.kuenstlerID {
            liste.append(Handlung(text: String(localized: "Zum Künstler"), symbol: "person") {
                modell.oeffnen(.kuenstler(Kuenstler(id: id, name: album.kuenstlernamen.first ?? "")))
            })
        }
        return Handlungsliste(titel: album.titel, handlungen: liste)
    }

    /// `mitAlbum`: auf einer Albumseite führt „Zum Album" nirgendwohin.
    /// `ausBlatt`: aus dem Wiedergabeblatt — dann geht es erst zu, bevor die
    /// Seite aufgeht.
    static func lied(_ lied: Lied, mitAlbum: Bool = true, ausBlatt: Bool = false,
                     _ modell: Musikmodell) -> Handlungsliste {
        let favorit = modell.istFavorit(lied.id, sonst: lied.favorit)
        let oeffnen: (Ziel) -> Void = ausBlatt ? modell.oeffnenAusBlatt : modell.oeffnen
        var liste: [Handlung] = []
        if !ausBlatt {
            liste += [
                Handlung(text: String(localized: "Als Nächstes spielen"),
                         symbol: "text.line.first.and.arrowtriangle.forward") { modell.alsNaechstes([lied]) },
                Handlung(text: String(localized: "Hinten anstellen"),
                         symbol: "text.line.last.and.arrowtriangle.forward") { modell.hintenAn([lied]) },
                Handlung(text: favorit ? String(localized: "Aus den Favoriten") : String(localized: "Zu den Favoriten"),
                         zeichen: favorit ? .herz : .herzUmriss) {
                    modell.favoritSetzen(.lied(lied.id), id: lied.id, an: !favorit, lied: lied)
                },
            ]
        }
        liste.append(Handlung(text: String(localized: "Zu Playlist hinzufügen"), symbol: "text.badge.plus") {
            modell.zuPlaylist([lied])
        })
        liste.append(Handlung(text: String(localized: "Sofortmix aus diesem Lied"), zeichen: .sofortmix) {
            Task { await modell.sofortmix(.lied(lied)) }
        })
        if mitAlbum, let id = lied.albumID {
            liste.append(Handlung(text: String(localized: "Zum Album"), symbol: "square.stack") {
                oeffnen(.album(Album(id: id, titel: lied.album ?? "", bild: lied.bild)))
            })
        }
        if let id = lied.kuenstlerID {
            liste.append(Handlung(text: String(localized: "Zum Künstler"), symbol: "person") {
                oeffnen(.kuenstler(Kuenstler(id: id, name: lied.ersterKuenstler ?? "")))
            })
        }
        return Handlungsliste(titel: lied.titel, handlungen: liste)
    }

    static func sammlung(_ ziel: Ziel, titel: String, _ modell: Musikmodell) -> Handlungsliste {
        Handlungsliste(titel: titel, handlungen: [
            Handlung(text: String(localized: "Abspielen"), zeichen: .abspielen) {
                Task { await modell.abspielen(ziel) }
            },
            Handlung(text: String(localized: "Zufall"), zeichen: .zufall) {
                Task { await modell.abspielen(ziel, mischen: true) }
            },
            Handlung(text: String(localized: "Als Nächstes spielen"),
                     symbol: "text.line.first.and.arrowtriangle.forward") {
                Task { await modell.alsNaechstes(ziel) }
            },
            Handlung(text: String(localized: "Hinten anstellen"),
                     symbol: "text.line.last.and.arrowtriangle.forward") {
                Task { await modell.hintenAn(ziel) }
            },
            Handlung(text: String(localized: "Zu Playlist hinzufügen"), symbol: "text.badge.plus") {
                Task { if let lieder = await modell.lieder(ziel) { modell.zuPlaylist(lieder) } }
            },
        ])
    }

    /// **Eine Auswahl**: vorn der Haken beim Wert, der gilt (`Auswahlblatt`).
    static func auswahl<Wert: Hashable>(_ titel: String, werte: [Wert], gewaehlt: Wert,
                                        name: (Wert) -> String,
                                        waehlen: @escaping @MainActor (Wert) -> Void) -> Handlungsliste {
        Handlungsliste(titel: titel, handlungen: werte.map { w in
            Handlung(text: name(w), gewaehlt: w == gewaehlt) { waehlen(w) }
        })
    }

    /// **Eine Rückfrage**, wo etwas verloren geht: die Frage als Rubrik, ein
    /// Satz dazu, eine rote Zeile — Abbrechen steht ohnehin darunter.
    static func rueckfrage(_ frage: String, hinweis: String, handlung: String, symbol: String,
                           tun: @escaping @MainActor () -> Void) -> Handlungsliste {
        Handlungsliste(titel: frage, hinweis: hinweis, handlungen: [
            Handlung(text: handlung, symbol: symbol, warnend: true, tun: tun),
        ])
    }
}
