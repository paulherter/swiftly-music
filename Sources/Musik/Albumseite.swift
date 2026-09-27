import MusikKit
import SwiftUI

/// **Die Seite einer Sammlung** — Album, Playlist oder Hörbuch — nach dem
/// Entwurf der Albumseite (Übergabe §4): ein Kopf von 320 mit Hülle 132 und
/// Titel unten links, darunter Plaketten, der weiße Hauptknopf, die
/// Aktionsreihe und die Liedliste. Hinter der ganzen Seite liegt die Hülle
/// verschwommen (``Seitenhintergrund``) — vorher nur hinter dem Kopf, als
/// Heldbild, das unten in `grund` auslief.
struct Albumseite: View {
    let ziel: Ziel
    @Environment(Musikmodell.self) private var modell

    /// Wie vom Server geholt; `sichtbareLieder()` rechnet für die Lieblingssongs noch
    /// die Herzen dieser Sitzung ein.
    @State private var geholt: [Lied]?
    /// Bei Playlists: mit den Kennungen der Einträge, zum Entfernen.
    @State private var detail: Playlistdetail?
    @State private var kopf: Kopfdaten
    @State private var fehler: Stoerung?
    @State private var deckung: Double = 0
    /// Die Farbe der Seite, sobald sie aus der Hülle gerechnet ist — für die
    /// Detailleiste (``Titelleistenglas``).
    @State private var seitenton: Seitenfarbe.Seitenton?
    /// Bei Alben: Album, EP oder Single — mit den Liedern gerechnet, nicht
    /// nur mit dem, was die Kachel wusste. Singles kommen nicht in „Zuletzt
    /// gehört".
    @State private var albumart: Albumart?
    /// Ein Lied, das gerade entfernt wird — der Server erfährt es erst, wenn
    /// „Rückgängig" nicht gedrückt wurde.
    @State private var entfernen: Task<Void, Never>?
    /// Einträge, die schon weg sind, aber noch nicht beim Server.
    @State private var ausstehend: [String] = []
    @Environment(\.dismiss) private var schliessen

    /// **Was die Seite zeigt.** Bei den Lieblingssongs: ohne die Lieder, die
    /// ihr Herz verloren haben, und mit denen, die eins bekamen — sofort,
    /// ohne auf den Server zu warten.
    ///
    /// **Einmal je Durchlauf gerechnet**, im `body`, und von dort an Kopf,
    /// Knöpfe und Liste gereicht. Vorher war es eine berechnete Eigenschaft,
    /// und jeder der rund zehn Zugriffe filterte die ganze Liste neu.
    private func sichtbareLieder() -> [Lied]? {
        if let detail, playlist != nil {
            return zip(detail.lieder, detail.eintraege).filter { !ausstehend.contains($0.1) }.map(\.0)
        }
        guard case .lieblingssongs = ziel, let geholt else { return geholt }
        let behalten = geholt.filter { modell.istFavorit($0.id, sonst: true) }
        let da = Set(behalten.map(\.id))
        return modell.neueLieblinge.filter { !da.contains($0.id) && modell.istFavorit($0.id, sonst: true) } + behalten
    }

    private var playlist: Playlist? {
        if case let .playlist(p) = ziel { return p }
        return nil
    }

    /// Was im Kopf steht — vorab aus dem, was die Kachel schon wusste.
    struct Kopfdaten: Equatable {
        var titel: String
        var zeile: String?
        var meta: String?
        var bild: Bildbezug?
        var favorit: Bool
        var favoritziel: Favoritziel?
        var kuenstler: Kuenstler?
        /// Die Albumkünstler — wer davon abweicht, steht unter dem Liedtitel.
        var kuenstlernamen: [String] = []
    }

    init(ziel: Ziel) {
        self.ziel = ziel
        _kopf = State(initialValue: Self.kopf(ziel))
    }

    private static let heldhoehe: CGFloat = 320
    /// Wo die erste Schrift stehen kann: drei Zeilen Titel, Zeile und Angabe
    /// über dem unteren Rand des Kopfs (16) — rund 150 hoch.
    private static let textAb: CGFloat = heldhoehe - 16 - 154

    var body: some View {
        let lieder = sichtbareLieder()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Seitenzugmesser()
                held(lieder)
                VStack(alignment: .leading, spacing: 0) {
                    plaketten(lieder)
                    Button { abspielen(lieder, mischen: false) } label: {
                        HStack(spacing: 9) {
                            Symbolbild(zeichen: .abspielen, groesse: 17)
                            Text(hoerbuch && fortsetzen(lieder) != nil ? "Weiterhören" : "Abspielen")
                        }
                    }
                    .buttonStyle(SeitenHauptknopfStil())
                    .disabled(lieder?.isEmpty ?? true)
                    aktionen(lieder).padding(.top, 20)
                }
                .padding(.horizontal, Musikstil.rand)
                liste(lieder).padding(.top, 22)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .modifier(Scrolldeckung(heldhoehe: Self.heldhoehe, deckung: $deckung))
        .seitenfarbe(hintergrund(lieder), textAb: Self.textAb, heldhoehe: Self.heldhoehe, farbton: $seitenton)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            Detailleiste(titel: kopf.titel, deckung: deckung, seitenfarbe: true,
                         farbe: seitenton.map { Color($0.farbe) } ?? Stil.grund) {
                Heldmehr { mehrliste(sichtbareLieder()) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(WischZurueck())
        .task { await laden() }
        // Keine veraltete Liste, wenn man zurückkommt: nach jeder Änderung an
        // Playlists (auch auf einer anderen Seite) frisch holen.
        .onChange(of: modell.playlistwechsel) { _, _ in
            if playlist != nil || ziel == .lieblingssongs { Task { await laden() } }
        }
    }

    private var hoerbuch: Bool { if case .hoerbuch = ziel { true } else { false } }
    private var verweis: Sammlungsverweis {
        var v = Musikmodell.verweis(ziel)
        v.titel = kopf.titel
        v.bild = kopf.bild ?? v.bild
        if let albumart { v.albumart = albumart }
        return v
    }

    // MARK: Kopf

    /// **Was hinter der Seite liegt**: die Hülle, in derselben Größe wie im
    /// Kopf — dann liegt sie schon im Speicher. Die Lieblingssongs haben ihre
    /// eigene Glut statt der Hülle des obersten Liedes.
    private func hintergrund(_ lieder: [Lied]?) -> Seitenhintergrund.Quelle {
        if ziel == .lieblingssongs { return .lieblinge }
        return .huelle(modell.bildadresse(kopf.bild ?? lieder?.first?.bild, punkte: 132))
    }

    private func held(_ lieder: [Lied]?) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            huelle(lieder)
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: Musikstil.eckeKachel, style: .continuous))
                .shadow(color: .black.opacity(0.7), radius: 16, x: 0, y: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: kopf.titel)
                    .font(Musikstil.seitentitel)
                    .tracking(Musikstil.sperrungSeitentitel)
                    .foregroundStyle(Stil.schrift)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                if let zeile = zeile(lieder) {
                    Text(verbatim: zeile)
                        .font(Musikstil.zeile)
                        .foregroundStyle(Stil.schriftLeise)
                        .lineLimit(1)
                        .padding(.top, 4)
                }
                if let meta = kopf.meta {
                    Text(verbatim: meta)
                        .font(Musikstil.angabe)
                        .foregroundStyle(Stil.schriftSehrLeise)
                        .lineLimit(1)
                        .padding(.top, 3)
                }
            }
            // Titel, Zeile und Angabe als eine Station, wie der
            // `Heldkopf` im Player.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, Musikstil.rand)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: Self.heldhoehe, alignment: .bottomLeading)
    }

    /// Unter dem Titel: bei den Lieblingssongs, wie viele es sind, sobald
    /// sie da sind — sonst, was die Sammlung ist.
    private func zeile(_ lieder: [Lied]?) -> String? {
        if ziel == .lieblingssongs, let lieder {
            return lieder.count == 1 ? String(localized: "1 Lied") : String(localized: "\(lieder.count) Lieder")
        }
        return kopf.zeile
    }

    /// **Die Hülle im Kopf.** Lieblingssongs: ihre eigene Kachel
    /// (``Lieblingskachel``). Eine Playlist mit mindestens vier verschiedenen
    /// Hüllen: ein 2×2-Mosaik aus den ersten vier, sonst ihre eigene.
    @ViewBuilder private func huelle(_ lieder: [Lied]?) -> some View {
        if ziel == .lieblingssongs {
            Lieblingskachel()
        } else if playlist != nil, let vier = Self.mosaik(lieder ?? []) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    Netzhuelle(adresse: modell.bildadresse(vier[0], punkte: Musikstil.kachelbild), zeichengroesse: 14)
                    Netzhuelle(adresse: modell.bildadresse(vier[1], punkte: Musikstil.kachelbild), zeichengroesse: 14)
                }
                GridRow {
                    Netzhuelle(adresse: modell.bildadresse(vier[2], punkte: Musikstil.kachelbild), zeichengroesse: 14)
                    Netzhuelle(adresse: modell.bildadresse(vier[3], punkte: Musikstil.kachelbild), zeichengroesse: 14)
                }
            }
        } else {
            Netzhuelle(adresse: modell.bildadresse(kopf.bild ?? lieder?.first?.bild, punkte: 132), zeichengroesse: 34)
        }
    }

    /// Die ersten vier verschiedenen Hüllen, wenn es so viele gibt.
    static func mosaik(_ lieder: [Lied]) -> [Bildbezug]? {
        var gesehen = Set<String>()
        var vier: [Bildbezug] = []
        for bild in lieder.compactMap(\.bild) where gesehen.insert(bild.id).inserted {
            vier.append(bild)
            if vier.count == 4 { return vier }
        }
        return nil
    }

    // MARK: Plaketten und Knöpfe

    @ViewBuilder private func plaketten(_ lieder: [Lied]?) -> some View {
        HStack(spacing: 8) {
            if let lieder, let quelle = modell.quelle,
               let angabe = Abspielregel.albumangabe(lieder, serverart: quelle.serverart) {
                switch angabe {
                case let .direkt(format):
                    Plakette(text: format.map { String(localized: "Direct Play · \($0)") } ?? String(localized: "Direct Play"),
                             akzent: true, haken: true)
                case let .umgewandelt(ziel):
                    Plakette(text: String(localized: "Transkodiert · \(ziel)"))
                case .gemischt:
                    Plakette(text: String(localized: "Teils umgewandelt"))
                }
            }
            if let lieder, !lieder.isEmpty {
                Plakette(text: umfang(lieder))
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 14)
        .frame(minHeight: 42, alignment: .top)
    }

    /// „24 Lieder · 1 Std. 12 Min."
    private func umfang(_ lieder: [Lied]) -> String {
        let minuten = Zeitformat.minuten(lieder.compactMap(\.dauer).reduce(0, +))
        let teile = hoerbuch ? String(localized: "\(lieder.count) Teile") : String(localized: "\(lieder.count) Lieder")
        guard minuten > 0 else { return teile }
        let dauer = minuten >= 60 ? String(localized: "\(minuten / 60) Std. \(minuten % 60) Min.")
                                  : String(localized: "\(minuten) Min.")
        return "\(teile) · \(dauer)"
    }

    @ViewBuilder private func aktionen(_ lieder: [Lied]?) -> some View {
        let favorit = kopf.favoritziel.map { _ in modell.istFavorit(zielID, sonst: kopf.favorit) }
        HStack(spacing: 0) {
            if hoerbuch {
                Aktion(zeichen: .zurueck, titel: Text("Von vorn")) { vonVorn(lieder) }
            } else {
                Aktion(zeichen: .zufall, titel: Text("Zufall")) { abspielen(lieder, mischen: true) }
            }
            if let ziel = kopf.favoritziel, let favorit, favoritErlaubt(ziel) {
                Aktion(zeichen: favorit ? .herz : .herzUmriss, titel: Text("Favorit"), aktiv: favorit) {
                    modell.favoritSetzen(ziel, id: zielID, an: !favorit)
                }
            }
            ladeaktion(lieder)
            Aktion(zeichen: .mehr, titel: Text("Mehr")) { modell.handlungen = mehrliste(lieder) }
        }
    }

    /// **Laden**: „Laden", während es lädt „3 von 10" in Akzent, danach
    /// „Geladen" in Akzent. Entfernen fragt vorher — da geht etwas verloren.
    @ViewBuilder private func ladeaktion(_ lieder: [Lied]?) -> some View {
        switch modell.ablage.stand(verweis) {
        case .nicht:
            Aktion(zeichen: .laden, titel: Text("Laden")) {
                if let lieder { modell.ablage.laden(verweis, lieder: lieder) }
            }
            .disabled(lieder?.isEmpty ?? true)
        case let .teilweise(fertig, von):
            Aktion(zeichen: .laden, titel: Text("\(fertig) von \(von)"), aktiv: true) { entfernenFragen() }
        case .ganz:
            Aktion(zeichen: .geladen, titel: Text("Geladen"), aktiv: true) { entfernenFragen() }
        }
    }

    /// „Mehr" auf der Seite und oben über dem Heldbild.
    private func mehrliste(_ lieder: [Lied]?) -> Handlungsliste {
        var liste: [Handlung] = []
        if let lieder, !lieder.isEmpty {
            liste.append(Handlung(text: String(localized: "Als Nächstes spielen"),
                                  symbol: "text.line.first.and.arrowtriangle.forward") { modell.alsNaechstes(lieder) })
            liste.append(Handlung(text: String(localized: "Hinten anstellen"),
                                  symbol: "text.line.last.and.arrowtriangle.forward") { modell.hintenAn(lieder) })
        }
        switch ziel {
        case let .album(album):
            liste.append(Handlung(text: String(localized: "Sofortmix"), zeichen: .sofortmix) {
                Task { await modell.sofortmix(.album(album)) }
            })
        case let .playlist(p):
            liste.append(Handlung(text: String(localized: "Sofortmix"), zeichen: .sofortmix) {
                Task { await modell.sofortmix(.playlist(p)) }
            })
        default:
            break
        }
        if let k = kopf.kuenstler {
            liste.append(Handlung(text: String(localized: "Zum Künstler"), symbol: "person") {
                modell.oeffnen(.kuenstler(k))
            })
        }
        if let lieder, !lieder.isEmpty {
            liste.append(Handlung(text: String(localized: "Zu Playlist hinzufügen"), symbol: "text.badge.plus") {
                modell.zuPlaylist(lieder)
            })
        }
        if let p = playlist {
            let aktuell = Playlist(id: p.id, name: kopf.titel, liedzahl: p.liedzahl, bild: p.bild)
            liste.append(Handlung(text: String(localized: "Bearbeiten"), symbol: "list.bullet") {
                modell.pfade[modell.bereich, default: []].append(.playlistBearbeiten(aktuell))
            })
            liste.append(Handlung(text: String(localized: "Umbenennen"), symbol: "pencil") {
                modell.umbenennen(aktuell) { kopf.titel = $0 }
            })
            liste.append(Handlung(text: String(localized: "Löschen"), symbol: "trash", warnend: true) {
                modell.loeschenFragen(aktuell) { schliessen() }
            })
        }
        if modell.ablage.stand(verweis) != .nicht {
            liste.append(Handlung(text: String(localized: "Geladenes entfernen"), symbol: "trash", warnend: true) {
                entfernenFragen()
            })
        }
        return Handlungsliste(titel: kopf.titel, handlungen: liste)
    }

    /// Entfernen fragt vorher — da geht etwas verloren.
    private func entfernenFragen() {
        let verweis = verweis
        let ablage = modell.ablage
        modell.handlungen = Handlungen.rueckfrage(
            String(localized: "Geladene Lieder entfernen?"),
            hinweis: String(localized: "Sie lassen sich jederzeit neu laden."),
            handlung: String(localized: "Entfernen"), symbol: "trash") { ablage.entfernen(verweis) }
    }

    // MARK: Liste

    @ViewBuilder private func liste(_ lieder: [Lied]?) -> some View {
        // Laden, leer und gestört getrennt, wie `SeriesView` im Player —
        // vorher stand bei null Liedern einfach nichts unter den Knöpfen.
        if let lieder, lieder.isEmpty {
            leer.padding(.top, 30)
        } else if let lieder {
            let spieler = modell.spieler
            let laufend = lieder.firstIndex { $0.id == spieler.aktuell?.id }
            // **CDs gibt es nur auf einem Album.** In den Lieblingssongs und
            // in Playlists kommen die Lieder aus vielen Alben; lag eins davon
            // auf CD 2, zerfiel die Liste in „CD 1" und „CD 2", und jedes Lied
            // ohne CD-Nummer fehlte ganz.
            let cds = istAlbum ? Set(lieder.compactMap(\.cd)) : []
            if cds.count > 1 {
                ForEach(cds.sorted(), id: \.self) { cd in
                    let teil = lieder.enumerated().filter { $0.element.cd == cd }
                    Gruppentitel(text: String(localized: "CD \(cd)"))
                        .padding(.horizontal, Musikstil.rand)
                        .padding(.top, cd == cds.min() ? 0 : 18)
                    Liedliste(lieder: teil.map(\.element),
                              laufend: teil.firstIndex { $0.offset == laufend },
                              spielt: spieler.spielt,
                              unter: gaeste,
                              tippen: { i in spielen(lieder, ab: teil[i].offset) },
                              rand: Musikstil.rand,
                              links: { _, lied in warteschlange(lied) }) { lied in
                        Handlungen.lied(lied, mitAlbum: !istAlbum, modell)
                    }
                }
            } else {
                Liedliste(lieder: lieder, laufend: laufend, spielt: spieler.spielt,
                          nummer: { i, lied in istAlbum ? (lied.nummer ?? i + 1) : i + 1 },
                          unter: gaeste,
                          tippen: { i in spielen(lieder, ab: i) },
                          rand: Musikstil.rand,
                          links: { _, lied in warteschlange(lied) },
                          rechts: { i, lied in entfernbar(i, lied) }) { lied in
                    Handlungen.lied(lied, mitAlbum: !istAlbum, modell)
                }
            }
        } else if let fehler {
            Stoerhinweis(stoerung: fehler) { Task { await laden() } }
                .padding(.top, 30)
        } else {
            // In der Höhe der echten Zeilen (48, ohne Abstand wie in der
            // `Liedliste`) — vorher 36 mit 12 Luft, und die Liste sprang,
            // als die Lieder kamen.
            VStack(spacing: 0) {
                ForEach(0 ..< 6, id: \.self) { _ in Liedplatzhalter() }
            }
            .padding(.horizontal, Musikstil.rand)
        }
    }

    /// Was bei null Liedern dasteht — je nach Art der Sammlung.
    @ViewBuilder private var leer: some View {
        switch ziel {
        case .playlist:
            Leerzustand(symbol: "music.note.list", kopfzeile: Text("Die Playlist ist leer"),
                        text: Text("Über „Zu Playlist hinzufügen“ kommen Lieder hinein."))
        case .lieblingssongs:
            Leerzustand(symbol: "heart", kopfzeile: Text("Noch keine Lieblingssongs"),
                        text: Text("Tipp bei einem Lied aufs Herz, dann steht es hier."))
        case .hoerbuch:
            Leerzustand(symbol: "book", kopfzeile: Text("Das Hörbuch ist leer"),
                        text: Text("Auf deinem Server liegen dazu keine Teile."))
        case .album, .kuenstler:
            Leerzustand(symbol: "square.stack", kopfzeile: Text("Das Album ist leer"),
                        text: Text("Auf deinem Server liegen dazu keine Lieder."))
        }
    }

    // MARK: Wischen

    /// Wisch nach rechts: hinten an die Warteschlange.
    private func warteschlange(_ lied: Lied) -> Wischhandlung? {
        guard !hoerbuch else { return nil }
        return Wischhandlung(symbol: "text.line.last.and.arrowtriangle.forward", text: "Warteschlange") {
            modell.zurWarteschlange(lied)
        }
    }

    /// Wisch nach links: aus der Playlist (bzw. aus den Lieblingssongs).
    private func entfernbar(_ i: Int, _ lied: Lied) -> Wischhandlung? {
        if ziel == .lieblingssongs {
            return Wischhandlung(symbol: "heart.slash", text: "Entfernen", farbe: Stil.fehler) {
                modell.favoritSetzen(.lied(lied.id), id: lied.id, an: false, lied: lied)
                modell.rueckgaengigAnbieten(String(localized: "Aus den Lieblingssongs.")) {
                    modell.favoritSetzen(.lied(lied.id), id: lied.id, an: true, lied: lied)
                }
            }
        }
        guard playlist != nil else { return nil }
        return Wischhandlung(symbol: "minus.circle", text: "Entfernen", farbe: Stil.fehler) { entfernen(i) }
    }

    /// **Aus der Playlist nehmen, mit „Rückgängig".** Die Zeile ist sofort
    /// weg; der Server erfährt es erst, wenn der Hinweis vorbei ist und
    /// niemand „Rückgängig" gedrückt hat — mehrere Wische in einem Aufruf.
    /// Lehnt er ab, kommen die Zeilen zurück.
    private func entfernen(_ i: Int) {
        guard let detail else { return }
        let sichtbar = zip(detail.lieder, detail.eintraege).filter { !ausstehend.contains($0.1) }
        guard sichtbar.indices.contains(i) else { return }
        let (lied, eintrag) = sichtbar[i]
        ausstehend.append(eintrag)
        abschicken(nach: detail)
        modell.rueckgaengigAnbieten(String(localized: "„\(lied.titel)“ entfernt.")) {
            ausstehend.removeAll { $0 == eintrag }
            if ausstehend.isEmpty { entfernen?.cancel() }
        }
    }

    private func abschicken(nach vorher: Playlistdetail) {
        guard let p = playlist else { return }
        entfernen?.cancel()
        let quelle = modell.quelle
        entfernen = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, let quelle, !ausstehend.isEmpty else { return }
            let stellen = ausstehend.compactMap { vorher.eintraege.firstIndex(of: $0) }
            do {
                try await quelle.playlistEntfernen(p.id, stellen: stellen, vorher: vorher)
                await laden()
                ausstehend = []
                modell.playlistwechsel += 1
            } catch {
                ausstehend = []
                modell.hinweis = Fehlertext.lesbar(error)
            }
        }
    }

    private var istAlbum: Bool { if case .album = ziel { true } else { false } }

    /// **Gäste unter dem Titel**: auf einer Albumseite dort, wo der
    /// Liedkünstler vom Albumkünstler abweicht (Features). Die übrigen Zeilen
    /// bleiben einzeilig.
    private func gaeste(_ lied: Lied) -> String? {
        let namen = lied.kuenstlernamen
        guard istAlbum, !namen.isEmpty, !kopf.kuenstlernamen.isEmpty,
              !Kuenstlernamen.gleich(namen, kopf.kuenstlernamen) else { return nil }
        return lied.kuenstlerzeile
    }

    /// Playlists mit Herz kennt nur Jellyfin.
    private func favoritErlaubt(_ ziel: Favoritziel) -> Bool {
        if case .playlist = ziel { return modell.quelle?.faehigkeiten.playlistFavoriten == true }
        return true
    }

    private var zielID: String {
        switch ziel {
        case let .album(a): a.id
        case let .playlist(p): p.id
        case let .hoerbuch(h): h.id
        case let .kuenstler(k): k.id
        case .lieblingssongs: Musikmodell.lieblingskennung
        }
    }

    // MARK: Abspielen

    private func spielen(_ lieder: [Lied]?, ab index: Int) {
        guard let lieder else { return }
        modell.spielen(lieder, ab: index, herkunft: verweis)
    }

    /// Ein Hörbuch geht dort weiter, wo es aufgehört hat.
    private func fortsetzen(_ lieder: [Lied]?) -> Int? {
        lieder?.firstIndex { $0.fortsetzen != nil }
    }

    private func abspielen(_ lieder: [Lied]?, mischen: Bool) {
        guard let lieder, !lieder.isEmpty else { return }
        if hoerbuch, let weiter = fortsetzen(lieder) {
            modell.spielen(lieder, ab: weiter, herkunft: verweis, eintragen: true)
        } else {
            modell.spielen(lieder, ab: mischen ? nil : 0, mischen: mischen, herkunft: verweis, eintragen: true)
        }
    }

    private func vonVorn(_ lieder: [Lied]?) {
        guard var lieder, !lieder.isEmpty else { return }
        for i in lieder.indices { lieder[i].fortsetzen = nil }
        modell.spielen(lieder, ab: 0, herkunft: verweis)
    }

    // MARK: Laden

    private func laden() async {
        guard let quelle = modell.quelle else { return }
        do {
            switch ziel {
            case let .album(a):
                let d = try await quelle.album(a.id)
                kopf = Self.kopf(.album(d.album))
                albumart = Veroeffentlichung.art(d.album, liedtitel: d.lieder.map(\.titel))
                geholt = d.lieder
            case let .playlist(p):
                let d = try await quelle.playlist(p.id)
                var k = Self.kopf(.playlist(d.playlist))
                k.zeile = d.playlist.besitzer ?? modell.benutzername
                kopf = k
                detail = d
                geholt = d.lieder
            case let .hoerbuch(h):
                let d = try await quelle.hoerbuch(h.id)
                kopf = Self.kopf(.hoerbuch(d.hoerbuch))
                geholt = d.teile
            case .lieblingssongs:
                geholt = try await quelle.lieblingssongs()
            case .kuenstler:
                geholt = []
            }
            fehler = nil
        } catch {
            // Ohne Netz: was geladen ist, spielt trotzdem.
            if let geladen = modell.ablage.verzeichnis.sammlungen[Musikmodell.verweis(ziel).id]?.lieder,
               !geladen.isEmpty {
                geholt = geladen
            } else {
                fehler = Stoerung(error)
            }
        }
    }

    static func kopf(_ ziel: Ziel) -> Kopfdaten {
        switch ziel {
        case let .album(a):
            let meta = [a.jahr.map(String.init), a.genres.first].compactMap { $0 }.joined(separator: " · ")
            return Kopfdaten(titel: a.titel, zeile: a.kuenstlerzeile, meta: meta.isEmpty ? nil : meta, bild: a.bild,
                             favorit: a.favorit, favoritziel: .album(a.id),
                             kuenstler: a.kuenstlerID.map { Kuenstler(id: $0, name: a.kuenstlernamen.first ?? "") },
                             kuenstlernamen: a.kuenstlernamen)
        case let .playlist(p):
            return Kopfdaten(titel: p.name, zeile: String(localized: "Playlist"), meta: nil, bild: p.bild,
                             favorit: p.favorit, favoritziel: .playlist(p.id), kuenstler: nil)
        case let .hoerbuch(h):
            return Kopfdaten(titel: h.titel, zeile: h.autor, meta: h.jahr.map(String.init), bild: h.bild,
                             favorit: false, favoritziel: nil, kuenstler: nil)
        case let .kuenstler(k):
            return Kopfdaten(titel: k.name, zeile: nil, meta: nil, bild: k.bild, favorit: k.favorit,
                             favoritziel: .kuenstler(k.id), kuenstler: k)
        case .lieblingssongs:
            return Kopfdaten(titel: String(localized: "Lieblingssongs"), zeile: String(localized: "Playlist"),
                             meta: nil, bild: nil, favorit: false, favoritziel: nil, kuenstler: nil)
        }
    }
}
