import MusikKit
import SwiftUI

/// **Der Künstler** (Übergabe §4): Heldbild 300 aus dem Foto, der Name 28
/// Bold im Bild, darunter „3 Alben · 34 Lieder · Synth-Pop" in 14. Dann
/// „Abspielen", die Aktionsreihe mit Sofortmix, „Oft gehört" nach der eigenen
/// Zählung des Servers und die Alben als Reihe. Unter dem Foto geht die Seite
/// in dessen Farbe weiter (``Seitenhintergrund``) — das Foto läuft unten in
/// sie aus statt in `grund`.
struct Kuenstlerseite: View {
    let kuenstler: Kuenstler
    @Environment(Musikmodell.self) private var modell

    @State private var detail: Kuenstlerdetail?
    @State private var oft: [Lied] = []
    @State private var fehler: Stoerung?
    @State private var deckung: Double = 0
    /// Die Farbe der Seite, sobald sie aus der Hülle gerechnet ist — für die
    /// Detailleiste (``Titelleistenglas``).
    @State private var seitenton: Seitenfarbe.Seitenton?

    private static let heldhoehe: CGFloat = 300
    /// Wo die erste Schrift stehen kann: zwei Zeilen Name und die Angabe
    /// über dem unteren Rand des Fotos.
    private static let textAb: CGFloat = heldhoehe - 16 - 94

    private var aktuell: Kuenstler { detail?.kuenstler ?? kuenstler }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Seitenzugmesser()
                held
                VStack(alignment: .leading, spacing: 0) {
                    Button { Task { await modell.abspielen(.kuenstler(aktuell)) } } label: {
                        HStack(spacing: 9) {
                            Symbolbild(zeichen: .abspielen, groesse: 17)
                            Text("Abspielen")
                        }
                    }
                    .buttonStyle(SeitenHauptknopfStil())
                    .padding(.top, 4)
                    aktionen.padding(.top, 20)
                }
                .padding(.horizontal, Musikstil.rand)
                // Ohne Seitenrand, damit sich die Zeilen wischen lassen; der
                // Rand liegt in der Zeile.
                if !oft.isEmpty { oftGehoert }
                alben
                // **Beim ersten Laden steht die Reihe schon da**, in ihrer
                // Form (`PersonView` im Player: „Drei Lagen, ein Bild") —
                // vorher stand unter der Aktionsreihe nichts, und die Seite
                // wuchs, als die Antwort kam.
                if detail == nil, fehler == nil {
                    Reihenplatzhalter()
                        .padding(.top, 26)
                }
                if let fehler, detail == nil {
                    Stoerhinweis(stoerung: fehler) { Task { await laden() } }
                        .padding(.top, 30)
                }
                // Ohne Alben und ohne „Oft gehört" endete die Seite stumm
                // unter den Knöpfen. Satz wie `PersonView` im Player.
                if let detail, detail.alben.isEmpty, oft.isEmpty {
                    Text("Auf deinem Server gibt es sonst nichts von \(aktuell.name).")
                        .font(.system(size: 15))
                        .foregroundStyle(Stil.schriftLeise)
                        .padding(.horizontal, Musikstil.rand)
                        .padding(.top, 26)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .modifier(Scrolldeckung(heldhoehe: Self.heldhoehe, deckung: $deckung))
        .seitenfarbe(.huelle(modell.bildadresse(aktuell.bild, punkte: 132)), textAb: Self.textAb, heldhoehe: Self.heldhoehe,
                     farbton: $seitenton)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            Detailleiste(titel: aktuell.name, deckung: deckung, seitenfarbe: true,
                         farbe: seitenton.map { Color($0.farbe) } ?? Stil.grund) {
                Heldmehr { Handlungen.sammlung(.kuenstler(aktuell), titel: aktuell.name, modell) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(WischZurueck())
        .task { await laden() }
    }

    // MARK: Heldbild

    private var held: some View {
        GeometryReader { g in
            let dehnung = max(0, g.frame(in: .scrollView).minY)
            ZStack(alignment: .bottomLeading) {
                Netzhuelle(adresse: modell.heldbildadresse(aktuell.heldbild ?? aktuell.bild, breite: g.size.width),
                           zeichengroesse: 1)
                    .frame(width: g.size.width, height: Self.heldhoehe + dehnung)
                    .clipped()
                    // **Unten ins Durchsichtige statt in `grund`**: dieselben
                    // Stufen wie der untere Verlauf von `Heldverlaeufe` (150,
                    // bei 45 % noch 40 %), nur als Maske — darunter liegt die
                    // Farbe der Seite, nicht mehr ein grauer Streifen.
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(stops: [.init(color: .black, location: 0),
                                                   .init(color: .black.opacity(0.4), location: 0.45),
                                                   .init(color: .black.opacity(0), location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 150)
                        }
                    }
                    .accessibilityHidden(true)
                // Der obere Verlauf von `Heldverlaeufe`, für die Statusleiste.
                LinearGradient(colors: [Stil.grund.opacity(0.8), Stil.grund.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: aktuell.name)
                        .font(Musikstil.seitentitel)
                        .tracking(Musikstil.sperrungSeitentitel)
                        .foregroundStyle(Stil.schrift)
                        .lineLimit(2)
                    if let angabe {
                        Text(verbatim: angabe)
                            .font(.system(size: 14))
                            .foregroundStyle(Stil.schriftLeise)
                            .lineLimit(1)
                            .padding(.top, 3)
                    }
                }
                // Name und Angabe als eine Station, wie der `Heldkopf` im Player.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Musikstil.rand)
                .padding(.bottom, 16)
            }
            .offset(y: -dehnung)
        }
        .frame(height: Self.heldhoehe)
    }

    private var angabe: String? {
        guard let detail else { return nil }
        var teile: [String] = []
        if !detail.alben.isEmpty {
            teile.append(detail.alben.count == 1 ? String(localized: "1 Album")
                                                 : String(localized: "\(detail.alben.count) Alben"))
        }
        if let lieder = detail.liedzahl, lieder > 0 {
            teile.append(lieder == 1 ? String(localized: "1 Lied") : String(localized: "\(lieder) Lieder"))
        }
        if let genre = detail.genres.first { teile.append(genre) }
        return teile.isEmpty ? nil : teile.joined(separator: " · ")
    }

    // MARK: Aktionen

    private var aktionen: some View {
        let favorit = modell.istFavorit(aktuell.id, sonst: aktuell.favorit)
        return HStack(spacing: 0) {
            Aktion(zeichen: .sofortmix, titel: Text("Sofortmix")) {
                Task {
                    await modell.sofortmix(.kuenstler(id: aktuell.id, name: aktuell.name),
                                           herkunft: Sammlungsverweis(aktuell))
                }
            }
            Aktion(zeichen: .zufall, titel: Text("Zufall")) {
                Task { await modell.abspielen(.kuenstler(aktuell), mischen: true) }
            }
            if modell.quelle?.faehigkeiten.kuenstlerFavoriten == true {
                Aktion(zeichen: favorit ? .herz : .herzUmriss, titel: Text("Favorit"), aktiv: favorit) {
                    modell.favoritSetzen(.kuenstler(aktuell.id), id: aktuell.id, an: !favorit)
                }
            }
            Aktion(zeichen: .mehr, titel: Text("Mehr")) {
                modell.handlungen = Handlungen.sammlung(.kuenstler(aktuell), titel: aktuell.name, modell)
            }
        }
    }

    // MARK: Oft gehört

    private var oftGehoert: some View {
        let spieler = modell.spieler
        return VStack(alignment: .leading, spacing: 0) {
            Reihentitel(text: "Oft gehört")
                .padding(.top, 26)
                .padding(.bottom, 4)
                .padding(.horizontal, Musikstil.rand)
            ForEach(Array(oft.enumerated()), id: \.element.id) { i, lied in
                Wischzeile(links: Wischhandlung(symbol: "text.line.last.and.arrowtriangle.forward",
                                                text: "Warteschlange") { modell.zurWarteschlange(lied) }) {
                // „Mehr" neben der Zeile, nicht als Knopf im Knopf.
                let laeuft = spieler.aktuell?.id == lied.id
                HStack(spacing: 14) {
                    Button {
                        guard modell.frei else { return }
                        modell.spielen(oft, ab: i, herkunft: Sammlungsverweis(aktuell))
                    } label: {
                        Zeilemitbild(bild: modell.bildadresse(lied.bild, punkte: 48), titel: lied.titel,
                                     angabe: lied.gespielt.map { String(localized: "\($0)-mal gehört") },
                                     laeuft: laeuft, spielt: spieler.spielt) { EmptyView() }
                    }
                    // Die Fläche reicht 10 über die Zeile hinaus, wie die der
                    // laufenden (`Zeilemitbild`).
                    .buttonStyle(Zeilendruck(links: -10, rechts: -10))
                    .langerDruck { Handlungen.lied(lied, modell) }
                    if !laeuft { Mehrknopf { Handlungen.lied(lied, modell) } }
                }
                .padding(.horizontal, Musikstil.rand)
                }
            }
        }
    }

    // MARK: Alben

    /// **Alben, darunter Singles & EPs** — eigene Reihen, damit ein Album
    /// nicht zwischen zwanzig Singles verschwindet.
    @ViewBuilder private var alben: some View {
        if let detail {
            let grosse = detail.alben.filter { ![.single, .ep].contains(Veroeffentlichung.art($0)) }
            let kleine = detail.alben.filter { [.single, .ep].contains(Veroeffentlichung.art($0)) }
            if !grosse.isEmpty { albenreihe("Alben", grosse) }
            if !kleine.isEmpty { albenreihe("Singles & EPs", kleine) }
        }
    }

    private func albenreihe(_ titel: LocalizedStringKey, _ liste: [Album]) -> some View {
            VStack(alignment: .leading, spacing: Musikstil.reihentitelAbstand) {
                Reihentitel(text: titel).padding(.horizontal, Musikstil.rand)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Musikstil.kachelAbstand) {
                        ForEach(liste) { album in
                            Button { if modell.frei { modell.albumTippen(album) } } label: {
                                Kachel(bild: modell.bildadresse(album.bild, punkte: Musikstil.kachelbild),
                                       titel: album.titel, angabe: Self.albumangabe(album))
                            }
                            .buttonStyle(Druckknopf())
                            .langerDruck { Handlungen.album(album, modell) }
                        }
                    }
                }
                .contentMargins(.horizontal, Musikstil.rand, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
            .padding(.top, 26)
    }

    /// „2024", „EP · 2019", „Single · 2021".
    static func albumangabe(_ album: Album) -> String? {
        let jahr = album.jahr.map(String.init)
        let art: String? = switch album.art {
        case .ep: String(localized: "EP")
        case .single: String(localized: "Single")
        case .live: String(localized: "Live")
        default: nil
        }
        let teile = [art, jahr].compactMap { $0 }
        return teile.isEmpty ? nil : teile.joined(separator: " · ")
    }

    // MARK: Laden

    /// **In einem Zug**: Künstler und „Oft gehört" zugleich gefragt und
    /// zusammen gesetzt. Vorher kam „Oft gehört" nach den Alben und schob
    /// sie ein Stück hinunter.
    private func laden() async {
        guard let quelle = modell.quelle else { return }
        let wer = aktuell
        async let antwort = quelle.kuenstler(kuenstler.id)
        async let gehoert = try? quelle.oftGehoert(von: wer, anzahl: 5)
        do {
            let neu = try await antwort
            let lieder = await gehoert ?? []
            withAnimation(Musikstil.einblenden) {
                detail = neu
                oft = lieder
            }
            fehler = nil
        } catch {
            fehler = Stoerung(error)
        }
    }
}
