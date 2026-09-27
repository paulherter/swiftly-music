import MusikKit
import SwiftUI

/// **Start** (Übergabe §4): Zuletzt gehört → Zuletzt hinzugefügt → Sofortmix.
///
/// Der Kopf trägt die Wortmarke in der Klein-Fassung (32 hoch) und das
/// Profilzeichen. Geladen wird beim ersten Erscheinen, beim Zurückkommen in
/// die App (Frist 30 s) und wenn das Blatt zugeht (`VERHALTEN.md` D8) — sonst
/// stünde „Zuletzt gehört" nach einem Album auf einem anderen Gerät falsch da.
struct Startseite: View {
    @Environment(Musikmodell.self) private var modell
    @Environment(\.scenePhase) private var phase

    // **Jede Reihe für sich**: `nil` heißt „noch unterwegs". Vorher wartete
    // die Seite auf alle drei Anfragen, bevor sie irgendetwas zeigte — bei
    // Jellyfin gehen „Zuletzt gehört" und „Oft gehört" je über bis zu 800
    // gespielte Lieder, und so lange standen auch die fertigen Neuzugänge
    // nur als Platzhalter da.
    @State private var zuletztVomServer: [Sammlungsverweis]?
    /// Die gehörten Alben vom Server nach Kennung — daran sieht „Zuletzt
    /// gehört", welche davon Singles sind.
    @State private var gehoerteAlben: [String: Album] = [:]
    @State private var neu: [Album]?
    @State private var mixe: [Mixvorschlag]?
    @State private var fehler: Stoerung?
    @State private var geholt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Musikstil.reihenAbstand) {
                if modell.offline, zuletztVomServer == nil, neu == nil {
                    Leerzustand(symbol: "wifi.slash",
                                kopfzeile: Text("Kein Netz"),
                                text: Text("Was du geladen hast, liegt in der Bibliothek und läuft auch so."),
                                knopf: (Text("Zur Bibliothek"), { modell.bereich = .bibliothek }))
                        .padding(.top, 80)
                } else if let fehler, zuletztVomServer == nil, neu == nil {
                    Stoerhinweis(stoerung: fehler) { Task { await laden() } }
                        .padding(.top, 80)
                } else {
                    inhalt
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .bereichsinhalt()
        .refreshable { await laden() }
        .safeAreaInset(edge: .top, spacing: 0) {
            Wurzelkopf {
                HStack(alignment: .center) {
                    Image("Wortmarke")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 32)
                        .accessibilityLabel(Text(verbatim: "Swiftly Music"))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Kontoziel()
                }
            }
        }
        .background(Stil.grund)
        .toolbar(.hidden, for: .navigationBar)
        .task { if geholt == nil { await laden() } }
        .onChange(of: phase) { _, neu in
            if neu == .active, let geholt, Date().timeIntervalSince(geholt) > 30 {
                Task { await laden() }
            }
        }
        .onChange(of: modell.blattOffen) { _, offen in
            if !offen { Task { await laden() } }
        }
        .onChange(of: modell.bibliothekswechsel) { _, _ in Task { await laden() } }
        // Wieder im Netz: frisch holen.
        .onChange(of: modell.offline) { _, offline in
            if !offline { Task { await laden() } }
        }
    }

    // MARK: Inhalt

    @ViewBuilder
    private var inhalt: some View {
        let zuletzt = zuletztVomServer.map { server in
            Zuletztgehoert.liste(eigene: modell.zuletzt, server: server) { v in
                v.art == .album ? gehoerteAlben[v.kennung].map { Veroeffentlichung.art($0) } : nil
            }
        }
        if let zuletzt, let neu, zuletzt.isEmpty && neu.isEmpty {
            Leerzustand(symbol: "music.note.list",
                        kopfzeile: Text("Hier ist noch nichts"),
                        text: Text("Sobald auf deinem Server Musik liegt, steht sie hier. Was du hörst, landet oben."))
                .padding(.top, 80)
        }

        if let zuletzt {
            if !zuletzt.isEmpty {
                VStack(alignment: .leading, spacing: Musikstil.reihentitelAbstand) {
                    Reihentitel(text: "Zuletzt gehört").padding(.horizontal, Musikstil.rand)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                              alignment: .leading, spacing: 16) {
                        ForEach(zuletztGebuendelt(zuletzt)) { buendel in
                            switch buendel {
                            case let .einzeln(verweis):
                                Button { if modell.frei { oeffnen(verweis) } } label: {
                                    Zuletztkachel(verweis: verweis,
                                                  bild: modell.bildadresse(verweis.bild, punkte: Musikstil.kachelbild),
                                                  laeuft: laeuft(verweis),
                                                  bezeichnung: gehoerteAlben[verweis.kennung]
                                                    .flatMap { verweis.art == .album ? $0.artname : nil })
                                }
                                .buttonStyle(Druckknopf())
                                .langerDruck { handlungen(verweis) }
                            case let .singles(name, id, liste):
                                Button { singlesOeffnen(name: name, id: id, bild: liste.first?.bild) } label: {
                                    Zuletztkachel(verweis: Sammlungsverweis(art: .album, kennung: buendel.id,
                                                                            titel: name, bild: liste.first?.bild),
                                                  bild: modell.bildadresse(liste.first?.bild, punkte: Musikstil.kachelbild),
                                                  bezeichnung: String(localized: "\(liste.count) Singles"))
                                }
                                .buttonStyle(Druckknopf())
                                .langerDruck {
                                    singleshandlungen(name: name, id: id, liste: liste.map {
                                        Album(id: $0.kennung, titel: $0.titel, bild: $0.bild)
                                    })
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Musikstil.rand)
                }
                .transition(.opacity)
            }
        } else {
            Reihenplatzhalter()
        }

        if let neu {
            if !neu.isEmpty {
                VStack(alignment: .leading, spacing: Musikstil.reihentitelAbstand) {
                    Reihentitel(text: "Zuletzt hinzugefügt").padding(.horizontal, Musikstil.rand)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: Musikstil.kachelAbstand) {
                            ForEach(Self.gebuendelt(neu)) { buendel in
                                switch buendel {
                                case let .einzeln(album):
                                    Button { if modell.frei { modell.albumTippen(album) } } label: {
                                        Kachel(bild: modell.bildadresse(album.bild, punkte: Musikstil.kachelbild),
                                               titel: album.titel,
                                               angabe: album.istSingle
                                                ? [String(localized: "Single"), album.kuenstlerzeile].compactMap { $0 }
                                                    .joined(separator: " · ")
                                                : album.kuenstlerzeile,
                                               neu: Neuheit.istNeu(hinzugefuegt: album.hinzugefuegt,
                                                                   gespielt: album.gespielt))
                                    }
                                    .buttonStyle(Druckknopf())
                                    .langerDruck { Handlungen.album(album, modell) }
                                case let .singles(name, id, liste):
                                    Button { singlesOeffnen(name: name, id: id, bild: liste.first?.bild) } label: {
                                        Kachel(bild: modell.bildadresse(liste.first?.bild, punkte: Musikstil.kachelbild),
                                               titel: name, angabe: String(localized: "\(liste.count) Singles"),
                                               neu: liste.contains {
                                                   Neuheit.istNeu(hinzugefuegt: $0.hinzugefuegt, gespielt: $0.gespielt)
                                               })
                                    }
                                    .buttonStyle(Druckknopf())
                                    .langerDruck { singleshandlungen(name: name, id: id, liste: liste) }
                                }
                            }
                        }
                    }
                    .contentMargins(.horizontal, Musikstil.rand, for: .scrollContent)
                    .scrollIndicators(.hidden)
                }
                .transition(.opacity)
            }
        } else {
            Reihenplatzhalter()
        }

        if let mixe, !mixe.isEmpty {
            VStack(alignment: .leading, spacing: Musikstil.reihentitelAbstand) {
                Reihentitel(text: "Sofortmix").padding(.horizontal, Musikstil.rand)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Musikstil.kachelAbstand) {
                        ForEach(mixe) { mix in
                            Button {
                                Task { await modell.sofortmix(mix.mixziel, herkunft: herkunft(mix)) }
                            } label: {
                                Mixkachel(huellen: mix.huellen.map {
                                              modell.bildadresse($0, punkte: Musikstil.kachelbild)
                                          },
                                          etikett: mix.name,
                                          titel: String(localized: "Mix: \(mix.name)"),
                                          angabe: String(localized: "50 Lieder"))
                            }
                            .buttonStyle(Druckknopf())
                            .langerDruck { mixhandlungen(mix) }
                        }
                    }
                }
                .contentMargins(.horizontal, Musikstil.rand, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
            .transition(.opacity)
        }
    }

    /// **Langer Druck auf „3 Singles"** — wie auf jeder Kachel daneben
    /// (`HomeView` im Player: jede Kachel einer Reihe hat ihr Menü).
    private func singleshandlungen(name: String, id: String?, liste: [Album]) -> Handlungsliste? {
        var handlungen = [
            Handlung(text: String(localized: "Abspielen"), zeichen: .abspielen) {
                Task {
                    var lieder: [Lied] = []
                    for album in liste { lieder += await modell.lieder(.album(album)) ?? [] }
                    modell.spielen(lieder, herkunft: nil)
                }
            },
        ]
        if let id {
            handlungen.append(Handlung(text: String(localized: "Zum Künstler"), symbol: "person") {
                modell.oeffnen(.kuenstler(Kuenstler(id: id, name: name)))
            })
        }
        return Handlungsliste(titel: name, handlungen: handlungen)
    }

    /// **Langer Druck auf einen Sofortmix**: bei einem Künstler-Mix der Weg
    /// zum Künstler. Ein Genre-Mix hat keinen Ort, an den es ginge, und
    /// „Abspielen" wäre nur der Tipp noch einmal — dort bewusst nichts.
    private func mixhandlungen(_ mix: Mixvorschlag) -> Handlungsliste? {
        guard case let .kuenstler(id, name) = mix.ziel else { return nil }
        return Handlungsliste(titel: String(localized: "Mix: \(mix.name)"), handlungen: [
            Handlung(text: String(localized: "Abspielen"), zeichen: .abspielen) {
                Task { await modell.sofortmix(mix.mixziel, herkunft: herkunft(mix)) }
            },
            Handlung(text: String(localized: "Zum Künstler"), symbol: "person") {
                modell.oeffnen(.kuenstler(Kuenstler(id: id, name: name)))
            },
        ])
    }

    /// Langer Druck auf eine Kachel von „Zuletzt gehört".
    private func handlungen(_ verweis: Sammlungsverweis) -> Handlungsliste? {
        switch verweis.art {
        case .album:
            return Handlungen.album(gehoerteAlben[verweis.kennung]
                                    ?? Album(id: verweis.kennung, titel: verweis.titel, bild: verweis.bild), modell)
        case .kuenstler:
            return Handlungen.sammlung(.kuenstler(Kuenstler(id: verweis.kennung, name: verweis.titel,
                                                            bild: verweis.bild)), titel: verweis.titel, modell)
        case .playlist where verweis.kennung == Musikmodell.lieblingskennung:
            return Handlungen.sammlung(.lieblingssongs, titel: verweis.titel, modell)
        case .playlist:
            return Handlungen.sammlung(.playlist(Playlist(id: verweis.kennung, name: verweis.titel,
                                                          bild: verweis.bild)), titel: verweis.titel, modell)
        case .hoerbuch:
            return Handlungen.sammlung(.hoerbuch(Hoerbuch(id: verweis.kennung, titel: verweis.titel,
                                                          bild: verweis.bild)), titel: verweis.titel, modell)
        }
    }

    // MARK: Singles

    /// **Singles desselben Künstlers vom selben Tag als eine Kachel**
    /// (``Singlebuendel``).
    static func gebuendelt(_ alben: [Album]) -> [Buendel<Album>] {
        Singlebuendel.buendeln(alben, single: \.istSingle,
                               kuenstler: { a in a.kuenstlernamen.first.map { ($0, a.kuenstlerID) } },
                               tag: \.hinzugefuegt)
    }

    private func zuletztGebuendelt(_ liste: [Sammlungsverweis]) -> [Buendel<Sammlungsverweis>] {
        Singlebuendel.buendeln(liste,
                               single: { $0.art == .album && gehoerteAlben[$0.kennung]?.istSingle == true },
                               kuenstler: { v in
                                   gehoerteAlben[v.kennung].flatMap { a in
                                       a.kuenstlernamen.first.map { ($0, a.kuenstlerID) }
                                   }
                               },
                               tag: \.zeit)
    }

    /// Die Singles eines Künstlers: seine Seite, dort stehen sie unter
    /// „Singles & EPs".
    private func singlesOeffnen(name: String, id: String?, bild: Bildbezug?) {
        guard modell.frei, let id else { return }
        modell.oeffnen(.kuenstler(Kuenstler(id: id, name: name)))
    }

    private func laeuft(_ verweis: Sammlungsverweis) -> Bool? {
        guard modell.spieler.aktuell != nil, modell.spieler.herkunft?.id == verweis.id else { return nil }
        return modell.spieler.spielt
    }

    private func herkunft(_ mix: Mixvorschlag) -> Sammlungsverweis? {
        if case let .kuenstler(id, name) = mix.ziel {
            return Sammlungsverweis(art: .kuenstler, kennung: id, titel: name, bild: nil)
        }
        return nil
    }

    private func oeffnen(_ verweis: Sammlungsverweis) {
        switch verweis.art {
        case .album:
            modell.albumTippen(gehoerteAlben[verweis.kennung]
                               ?? Album(id: verweis.kennung, titel: verweis.titel, bild: verweis.bild, art: .album))
        case .kuenstler:
            modell.oeffnen(.kuenstler(Kuenstler(id: verweis.kennung, name: verweis.titel, bild: verweis.bild)))
        case .playlist where verweis.kennung == Musikmodell.lieblingskennung:
            modell.oeffnen(.lieblingssongs)
        case .playlist:
            modell.oeffnen(.playlist(Playlist(id: verweis.kennung, name: verweis.titel, bild: verweis.bild)))
        case .hoerbuch:
            modell.oeffnen(.hoerbuch(Hoerbuch(id: verweis.kennung, titel: verweis.titel, bild: verweis.bild)))
        }
    }

    // MARK: Laden

    /// **Jede Reihe, sobald ihre Antwort da ist** — die schnelle wartet
    /// nicht auf die langsamen. Ersetzt wird, wenn das Neue da ist, nie vorher
    /// geleert (`Fallen/swiftui.md`, „Vorher leeren statt ersetzen").
    ///
    /// **Das erste Mal ohne Animation** (24.09.: beim Kaltstart
    /// „animiert sich einmal alles ein"): was beim ersten Laden kommt, steht
    /// einfach da. Eingeblendet wird erst beim Nachladen, wenn schon ein
    /// vollständiges Bild stand.
    private func laden() async {
        guard let quelle = modell.quelle else { return }
        let einblenden = geholt != nil
        func zeigen(_ aenderung: () -> Void) {
            var t = Transaction(animation: einblenden ? Musikstil.einblenden : nil)
            t.disablesAnimations = !einblenden
            withTransaction(t, aenderung)
        }
        var gehoert: [Album]?
        var oft: [Album]?
        var zuletztKam = false, neuKam = false
        await withTaskGroup(of: Antwort.self) { gruppe in
            gruppe.addTask { .zuletzt(try? await quelle.zuletztGehoert(anzahl: 16)) }
            gruppe.addTask { .neu(try? await quelle.zuletztHinzugefuegt(anzahl: 20)) }
            gruppe.addTask { .oft(try? await quelle.oftGehoerteAlben(anzahl: 30)) }
            for await antwort in gruppe {
                switch antwort {
                case let .zuletzt(liste):
                    gehoert = liste
                    guard let liste else { continue }
                    zuletztKam = true
                    gehoerteAlben = Dictionary(liste.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    zeigen {
                        zuletztVomServer = liste.map { Sammlungsverweis($0, zeit: $0.zuletztGespielt) }
                    }
                case let .neu(liste):
                    guard let liste else { continue }
                    neuKam = true
                    zeigen { neu = liste }
                case let .oft(liste):
                    oft = liste
                }
            }
        }
        // Die Mixe erst, wenn beide Quellen da sind — sonst ordneten sie sich
        // nach der zweiten Antwort noch einmal um.
        zeigen {
            mixe = Mixvorschlaege.bilden(aus: (gehoert ?? []) + (oft ?? []))
            // Eine gescheiterte Reihe steht nicht ewig als Platzhalter da.
            if zuletztVomServer == nil, neuKam { zuletztVomServer = [] }
            if neu == nil, zuletztKam { neu = [] }
            if zuletztKam || neuKam {
                fehler = nil
            } else if zuletztVomServer == nil {
                fehler = .keineVerbindung
            }
        }
        geholt = Date()
    }

    private enum Antwort: Sendable {
        case zuletzt([Album]?)
        case neu([Album]?)
        case oft([Album]?)
    }
}
