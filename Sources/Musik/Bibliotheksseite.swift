import MusikKit
import SwiftUI

/// Die Kapseln unter dem Titel: eine gilt oder keine (dann alles gemischt).
///
/// Drei, nicht fünf (24.09.): „Lieder" ist weg, „Geladen" ist eine
/// angeheftete Zeile unter den Lieblingssongs. Eine gespeicherte alte Wahl
/// („lieder", „geladen") liest sich als keine.
enum Bibliothekskapsel: String, CaseIterable, Identifiable {
    case playlists, alben, kuenstler
    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .playlists: "Playlists"
        case .alben: "Alben"
        case .kuenstler: "Künstler*innen"
        }
    }
}

/// **Die Bibliothek wie bei Spotify** (24.09.): eine Liste statt
/// Kacheln, oben fest „Lieblingssongs" und — wenn etwas geladen ist —
/// „Geladen", darunter was je gespielt wurde, neueste zuerst, danach der
/// Rest.
///
/// Kopf: Titel „Bibliothek", rechts Sortieren, Plus (neue Playlist) und
/// Profil — gesucht wird auf der Seite „Suche" (24.09.). Darunter die Kapseln Playlists · Alben · Künstler*innen —
/// Einfachauswahl, ein zweiter Tipp hebt sie auf. Die gewählte trägt
/// Akzent.
///
/// **Sortieren ist ein Zeichen im Kopf, keine Pille neben den Kapseln** und
/// keine Textzeile über der Liste wie bei Spotify: es öffnet Swiftlys
/// Auswahlblatt, die gewählte Ordnung mit Haken in Akzent.
///
/// **Die Kapseln gehen beim Scrollen weg** wie die Wertreihe auf Serien und
/// Filme im Player (`Wertreihe` in `Stil.swift`): Deckkraft über 44 Punkt
/// Scrollweg, am Finger, ihren Platz behalten sie.
struct Bibliotheksseite: View {
    @Environment(Musikmodell.self) private var modell
    @Environment(\.bereichAktiv) private var bereichAktiv
    @AppStorage("musik.bibliothek.kapsel") private var kapselRoh = ""
    @AppStorage("musik.bibliothek.ordnung") private var sortierung: Bibliothekssortierung = .zuletztGespielt
    @State private var stand = Bibliotheksdaten()
    @State private var weg = Scrollweg()
    @State private var position = ScrollPosition(edge: .top)
    @State private var kennungen = Zeilenkennungen()
    @State private var blick = Blickmerker()

    private var kapsel: Bibliothekskapsel? { Bibliothekskapsel(rawValue: kapselRoh) }

    /// **Eine andere Kapsel lädt nichts**: die Liste jeder Art liegt schon
    /// bereit (``Bibliotheksdaten/faecher``), sie wird nur getauscht.
    ///
    /// **Und die Einträge fliegen wieder** (24.09.): wer bleibt, zieht
    /// mit der Feder an seinen neuen Platz, wer wegfällt, geht mit ein paar
    /// Punkt Versatz aus, wer dazukommt, blendet ein. Quer über den Schirm
    /// zieht keiner — ``Zeilenkennungen`` gibt solchen Zeilen für diesen
    /// Wechsel eine neue Kennung, dann blenden sie. Die Feder nimmt jeden
    /// neuen Tipp aus dem Stand auf, in dem sie gerade ist; schnelles Hin und
    /// Her staut nichts.
    ///
    /// Vorher (``Kapselinhalt``) wurde die ganze Liste ausgetauscht: sauber,
    /// aber man sah nicht mehr, wohin ein Eintrag geht.
    private var kapselwahl: Binding<Bibliothekskapsel?> {
        Binding(get: { kapsel }, set: { neu in
            let alt = kapsel
            var k = kennungen
            k.wechsel(von: stand.liste(alt).map(\.id), nach: stand.liste(neu).map(\.id),
                      vorAlt: angeheftet(alt), vorNeu: angeheftet(neu),
                      sichtbar: blick.sichtbareZeilen(zeilenhoehe: Self.zeilenhoehe))
            position.sofortNachOben()
            withAnimation(Musikstil.blattbewegung) {
                kennungen = k
                kapselRoh = neu?.rawValue ?? ""
            }
        })
    }

    /// Die Höhe einer Zeile: Hülle 52 und zweimal 7 Rand (``Bibliothekszeile``).
    static let zeilenhoehe: CGFloat = 66

    /// Wie viele Zeilen über der Liste angeheftet sind.
    private func angeheftet(_ k: Bibliothekskapsel?) -> Int {
        guard (k == nil || k == .playlists) && !modell.offline else { return 0 }
        return modell.ablage.verzeichnis.sammlungen.isEmpty ? 1 : 2
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                inhalt
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        // Wo die Liste steht und wie hoch der Schirm ist — nur gemerkt, nicht
        // beobachtet: gebraucht wird es erst beim nächsten Kapselwechsel.
        .onScrollGeometryChange(for: CGPoint.self) {
            CGPoint(x: $0.containerSize.height, y: $0.contentOffset.y + $0.contentInsets.top)
        } action: { _, neu in
            blick.hoehe = neu.x
            blick.versatz = neu.y
        }
        // Der rohe Versatz plus der obere Rand — wie in der Bibliothek des
        // Players (`HauptView`, Messung vom 22.09.): die Summe ist der
        // Scrollweg, auch wenn sich der Kopf ändert.
        .onScrollGeometryChange(for: CGPoint.self) {
            CGPoint(x: $0.contentInsets.top, y: $0.contentOffset.y)
        } action: { _, neu in
            guard bereichAktiv else { return }
            // Der eine Zwischenstand beim Umrechnen der Geometrie: Versatz 0
            // bei schon gesetztem Rand wäre rechnerisch die ganze Kopfhöhe.
            guard !(abs(neu.y) < 1 && neu.x > 1) else { return }
            weg.setzen(neu.y + neu.x)
        }
        .bereichsinhalt()
        .refreshable { await laden() }
        .safeAreaInset(edge: .top, spacing: 0) { kopf }
        .background(Stil.grund)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: Anfrage(sortierung: sortierung, offline: modell.offline,
                          bibliothek: modell.bibliothekswechsel, playlists: modell.playlistwechsel)) {
            await laden()
        }
    }

    /// Alles, wovon der Inhalt abhängt — ändert sich eins, wird neu geladen.
    /// Die Kapsel gehört nicht dazu: geladen wird immer alles.
    private struct Anfrage: Equatable {
        let sortierung: Bibliothekssortierung
        let offline: Bool
        let bibliothek: Int
        let playlists: Int
    }

    // MARK: Kopf

    private var kopf: some View {
        Wurzelkopf(unten: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    Text("Bibliothek")
                        .font(Musikstil.seitentitel)
                        .tracking(Musikstil.sperrungSeitentitel)
                        .foregroundStyle(Stil.schrift)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    kopfknopf(name: "Sortierung") {
                        Symbolbild(zeichen: .sortieren, groesse: 22)
                    } tun: {
                        let bindung = $sortierung
                        modell.handlungen = Handlungen.auswahl(
                            String(localized: "Sortierung"), werte: Bibliothekssortierung.allCases,
                            gewaehlt: sortierung, name: Self.name) { bindung.wrappedValue = $0 }
                    }
                    .accessibilityValue(Text(verbatim: Self.name(sortierung)))
                    kopfknopf(name: "Neue Playlist") {
                        Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                    } tun: {
                        modell.neuePlaylist()
                    }
                    .disabled(modell.offline)
                    Kontoziel()
                }
                Kapselreihe(weg: weg, gewaehlt: kapselwahl)
            }
        }
    }

    private func kopfknopf<Zeichen: View>(name: LocalizedStringKey, @ViewBuilder zeichen: () -> Zeichen,
                                          tun: @escaping () -> Void) -> some View {
        Button(action: tun) {
            zeichen()
                .foregroundStyle(Stil.schrift)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(Druckknopf())
        .accessibilityLabel(Text(name))
    }

    static func name(_ s: Bibliothekssortierung) -> String {
        switch s {
        case .zuletztGespielt: String(localized: "Zuletzt gespielt")
        case .zuletztHinzugefuegt: String(localized: "Zuletzt hinzugefügt")
        case .name: String(localized: "A–Z")
        }
    }

    // MARK: Inhalt

    @ViewBuilder private var inhalt: some View {
        let liste = stand.liste(kapsel)
        if angeheftet(kapsel) > 0 {
            lieblingszeile
                .transition(.kapselzeile)
            geladenzeile
                .transition(.kapselzeile)
        }
        if stand.laedt && stand.eintraege.isEmpty {
            Bibliotheksplatzhalter()
        } else if let fehler = stand.fehler, stand.eintraege.isEmpty {
            Stoerhinweis(stoerung: fehler) { Task { await laden() } }
                .padding(.top, 80)
        } else if liste.isEmpty, !stand.laedt {
            // Leer erst melden, wenn gefragt ist (`!laedt` wie in `HauptView`).
            leer.padding(.top, 80)
        } else {
            let zeilen = liste.enumerated().map { Kapselzeile(id: kennungen.kennung($1.id), platz: $0, wert: $1) }
            ForEach(zeilen) { z in
                Bibliothekseintragzeile(eintrag: z.wert)
                    .onAppear { if z.platz >= liste.count - 15 { Task { await weiterLaden() } } }
                    .transition(.kapselzeile)
            }
        }
    }

    /// **Lieblingssongs, oben angeheftet** — ihre Kachel im Kleinen, wie im
    /// Kopf ihrer Seite (``Lieblingskachel``), und sofort aktuell, wenn
    /// irgendwo ein Herz gesetzt wird.
    private var lieblingszeile: some View {
        let zahl = stand.lieblinge.map { liste in
            let da = Set(liste.map(\.id))
            return liste.filter { modell.istFavorit($0.id, sonst: true) }.count
                + modell.neueLieblinge.filter { !da.contains($0.id) && modell.istFavorit($0.id, sonst: true) }.count
        }
        return Button { if modell.frei { modell.oeffnen(.lieblingssongs) } } label: {
            Bibliothekszeile(titel: String(localized: "Lieblingssongs"),
                             angabe: [String(localized: "Playlist"), zahl.map { String(localized: "\($0) Lieder") }]
                                .compactMap { $0 }.joined(separator: " · ")) {
                Lieblingskachel()
            }
        }
        .buttonStyle(Zeilendruck.randbreit)
    }

    /// **Geladen, unter den Lieblingssongs** — nur, wenn etwas auf dem Gerät
    /// liegt. Führt auf eine eigene Seite mit allem, was geladen ist.
    @ViewBuilder private var geladenzeile: some View {
        let verzeichnis = modell.ablage.verzeichnis
        if !verzeichnis.sammlungen.isEmpty {
            let zahl = verzeichnis.dateien.count
            Button { if modell.frei { modell.pfade[modell.bereich, default: []].append(.geladen) } } label: {
                Bibliothekszeile(titel: String(localized: "Geladen"),
                                 angabe: zahl == 1 ? String(localized: "1 Lied") : String(localized: "\(zahl) Lieder")) {
                    ZStack {
                        Stil.erhoeht
                        Symbolbild(zeichen: .geladen, groesse: 24).foregroundStyle(Stil.akzent)
                    }
                }
            }
            .buttonStyle(Zeilendruck.randbreit)
        }
    }

    @ViewBuilder private var leer: some View {
        if modell.offline {
            Leerzustand(symbol: "arrow.down.circle", kopfzeile: Text("Noch nichts geladen"),
                        text: Text("Tipp auf einem Album auf Laden. Dann läuft es auch ohne Netz."))
        } else {
            switch kapsel {
            case .playlists:
                Leerzustand(symbol: "music.note.list", kopfzeile: Text("Noch keine Playlists"),
                            text: Text("Mit dem Plus oben legst du eine an."))
            default:
                Leerzustand(symbol: "music.note.list", kopfzeile: Text("Hier ist noch nichts"),
                            text: Text("Sobald auf deinem Server Musik liegt, steht sie hier."))
            }
        }
    }

    // MARK: Laden

    private func laden() async {
        stand.laedt = true
        let neu = await Bibliotheksdaten.laden(nurGeladen: modell.offline, sortierung: sortierung, modell: modell)
        guard !Task.isCancelled else { return }
        withAnimation(Musikstil.einblenden) { stand = neu }
    }

    private func weiterLaden() async {
        let kapsel = kapsel
        guard !stand.laedt, stand.hatWeitere(kapsel) else { return }
        let kennung = stand.kennung
        stand.laedt = true
        var neu = stand
        await neu.weiter(fuer: kapsel, sortierung: sortierung, modell: modell)
        guard stand.kennung == kennung else { return }
        stand = neu
    }
}

/// **Eine Zeile unter Kapseln**, mit der Kennung aus ``Zeilenkennungen``
/// statt der eigenen.
struct Kapselzeile<Wert>: Identifiable {
    let id: String
    let platz: Int
    let wert: Wert
}

/// **Wo eine Liste unter Kapseln steht** — gemerkt, nicht beobachtet: ein
/// Wert je Scrollbild würde sonst die ganze Liste neu rechnen lassen.
final class Blickmerker {
    var versatz: CGFloat = 0
    var hoehe: CGFloat = 0

    /// Wie viele Zeilen auf den Schirm passen; `0`, wenn die Liste gescrollt
    /// ist — dann springt sie nach oben, und es wird nur überblendet.
    func sichtbareZeilen(zeilenhoehe: CGFloat) -> Int {
        guard versatz < zeilenhoehe / 2, hoehe > 0 else { return 0 }
        return Int((hoehe / zeilenhoehe).rounded(.up))
    }
}

extension AnyTransition {
    /// **Beim Kapselwechsel:** neue Zeilen blenden ein, wegfallende gehen mit
    /// acht Punkt nach unten aus. Ohne Bewegung (Bedienungshilfen) nur die
    /// Blende.
    @MainActor static var kapselzeile: AnyTransition {
        Musikstil.bewegungReduziert
            ? .opacity
            : .asymmetric(insertion: .opacity, removal: .opacity.combined(with: .offset(y: 8)))
    }
}

/// **Wie weit die Bibliothek gescrollt ist** — für die Kapseln, die dabei
/// weggehen. Ein eigenes Objekt, damit nur die Kapselreihe neu zeichnet und
/// nicht die ganze Liste; neu gesetzt wird erst ab einem halben Punkt und an
/// den Grenzen (`Scrollweg.setzen` in `HomeView`).
@MainActor @Observable
final class Scrollweg {
    /// 30 Punkt Kapselhöhe plus die 14 Abstand darüber (`Stil.wertreihenWeg`).
    static let weite: CGFloat = 44
    private(set) var wert: CGFloat = 0

    func setzen(_ neu: CGFloat) {
        let n = min(max(neu, 0), Self.weite)
        guard abs(n - wert) >= 0.5 || (n != wert && (n == 0 || n == Self.weite)) else { return }
        wert = n
    }
}

/// **Die Kapseln unter dem Titel** — gehen am Finger weg wie die Wertreihe
/// im Player: Deckkraft über 44 Punkt, ihren Platz behalten sie (ein Kopf,
/// der mit dem Scrollen seine Höhe ändert, schaukelt sich auf — Messung vom
/// 22.09. in `Wertreihe`). Halb zu nehmen sie keinen Tipp mehr an.
private struct Kapselreihe: View {
    let weg: Scrollweg
    @Binding var gewaehlt: Bibliothekskapsel?

    var body: some View {
        let offen = 1 - Double(weg.wert / Scrollweg.weite)
        Kapselwahl(werte: Bibliothekskapsel.allCases, name: \.name, gewaehlt: $gewaehlt)
        .scrollClipDisabled()
        .opacity(offen)
        .allowsHitTesting(offen > 0.5)
        .accessibilityHidden(offen < 0.5)
        .padding(.top, 14)
    }
}

/// Platzhalter in der Form der Zeilen, solange nichts da ist.
private struct Bibliotheksplatzhalter: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0 ..< 8, id: \.self) { _ in
                HStack(spacing: 13) {
                    Ladefeld(ecke: Musikstil.eckeKlein).frame(width: 52, height: 52)
                    Ladefeld(ecke: 3).frame(width: 160, height: 13)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Musikstil.rand)
        .padding(.top, 7)
    }
}

/// **Eine Zeile mit Playlist, Album oder Künstler** — Tipp öffnet, langer
/// Druck bietet an, was es dazu gibt.
private struct Bibliothekseintragzeile: View {
    let eintrag: Bibliothekseintrag
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        switch eintrag {
        case let .playlist(p):
            Button { if modell.frei { modell.oeffnen(.playlist(p)) } } label: {
                Bibliothekszeile(titel: p.name,
                                 angabe: [String(localized: "Playlist"), p.liedzahl.map { String(localized: "\($0) Lieder") }]
                                    .compactMap { $0 }.joined(separator: " · ")) {
                    Netzhuelle(adresse: modell.bildadresse(p.bild, punkte: 52), zeichengroesse: 18)
                }
            }
            .buttonStyle(Zeilendruck.randbreit)
            .langerDruck { Handlungen.sammlung(.playlist(p), titel: p.name, modell) }
        case let .album(a):
            Button { if modell.frei { modell.albumTippen(a) } } label: {
                Bibliothekszeile(titel: a.titel,
                                 angabe: [a.artname, a.kuenstlerzeile].compactMap { $0 }.joined(separator: " · ")) {
                    Netzhuelle(adresse: modell.bildadresse(a.bild, punkte: 52), zeichengroesse: 18)
                }
            }
            .buttonStyle(Zeilendruck.randbreit)
            .langerDruck { Handlungen.album(a, modell) }
        case let .kuenstler(k):
            Button { if modell.frei { modell.oeffnen(.kuenstler(k)) } } label: {
                Bibliothekszeile(titel: k.name, angabe: String(localized: "Künstler (einer)"), rund: true) {
                    Netzhuelle(adresse: modell.bildadresse(k.bild, punkte: 52), zeichengroesse: 18)
                }
            }
            .buttonStyle(Zeilendruck.randbreit)
            .langerDruck { Handlungen.sammlung(.kuenstler(k), titel: k.name, modell) }
        case .lied:
            // Lieder stehen nicht mehr in der Bibliothek.
            EmptyView()
        }
    }
}

/// **Alles, was auf dem Gerät liegt** — hinter der angehefteten Zeile
/// „Geladen" in der Bibliothek. Dieselben Zeilen, dieselbe Sortierung.
struct Geladenseite: View {
    @Environment(Musikmodell.self) private var modell
    @AppStorage("musik.bibliothek.ordnung") private var sortierung: Bibliothekssortierung = .zuletztGespielt
    @State private var stand = Bibliotheksdaten()

    var body: some View {
        VStack(spacing: 0) {
            Unterseitenkopf(titel: Text("Geladen"))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if stand.eintraege.isEmpty, !stand.laedt {
                        Leerzustand(symbol: "arrow.down.circle", kopfzeile: Text("Noch nichts geladen"),
                                    text: Text("Tipp auf einem Album auf Laden. Dann läuft es auch ohne Netz."))
                            .padding(.top, 60)
                    } else {
                        ForEach(stand.eintraege) { Bibliothekseintragzeile(eintrag: $0) }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Stil.grund)
        .toolbar(.hidden, for: .navigationBar)
        .background(WischZurueck())
        .task(id: Geladenstand(sortierung: sortierung, zahl: modell.ablage.verzeichnis.sammlungen.count)) {
            stand = await Bibliotheksdaten.laden(nurGeladen: true, sortierung: sortierung, modell: modell)
        }
    }

    private struct Geladenstand: Equatable {
        let sortierung: Bibliothekssortierung
        let zahl: Int
    }
}

/// **Eine Zeile der Bibliothek** — Maße wie die Suchtreffer: Hülle 52
/// (Künstler rund), Titel 15 Semibold, darunter 13 `schriftSehrLeise`.
private struct Bibliothekszeile<Huelle: View>: View {
    let titel: String
    let angabe: String
    var rund = false
    var laeuft: Bool?
    @ViewBuilder var huelle: () -> Huelle

    var body: some View {
        HStack(spacing: 13) {
            huelle()
                .frame(width: 52, height: 52)
                .clipShape(rund ? AnyShape(Circle())
                           : AnyShape(RoundedRectangle(cornerRadius: Musikstil.eckeKlein, style: .continuous)))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: titel)
                    .font(Musikstil.zeile)
                    .foregroundStyle(Stil.schrift)
                    .lineLimit(1)
                Text(verbatim: angabe)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Stil.schriftSehrLeise)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let laeuft { Pegel(laeuft: laeuft).frame(width: 44, height: 44) }
        }
        .padding(.horizontal, Musikstil.rand)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Was die Bibliothek gerade zeigt, und woher es kommt.
struct Bibliotheksdaten {
    /// Neu je Laden von vorn — eine spätere Seite gehört nur zu ihrem Stand.
    let kennung = UUID()
    /// Nur, was auf dem Gerät liegt — ohne Netz und auf der Seite „Geladen".
    var nurGeladen = false
    var playlists: [Playlist] = []
    var alben: [Album] = []
    var kuenstler: [Kuenstler] = []
    /// Die Lieblingssongs — für die Zahl in der angehefteten Zeile.
    var lieblinge: [Lied]?
    /// Wann auf dem Gerät gespielt, je Eintrag (``Bibliothekseintrag/id``).
    var gespielt: [String: Date] = [:]
    var weiterAlben: Int?
    var weiterKuenstler: Int?
    /// **Am Anfang wird geladen**, nicht „ist leer": mit `false` stand im
    /// ersten Bild „Hier ist noch nichts", bis der `task` lief (wie
    /// `Bibliotheksmodell` im Player, `laedt = true` von Beginn an).
    var laedt = true
    var fehler: Stoerung?
    /// Fertig sortiert — nach jedem Laden einmal gerechnet, nicht je Zeichnen.
    var eintraege: [Bibliothekseintrag] = []
    /// Dieselbe Folge nach Art, im selben Zug gerechnet: der Wechsel einer
    /// Kapsel sortiert nichts und fragt keinen Server.
    var faecher = Bibliotheksfaecher()

    /// Was unter einer Kapsel steht — ohne Kapsel alles gemischt.
    func liste(_ kapsel: Bibliothekskapsel?) -> [Bibliothekseintrag] {
        switch kapsel {
        case nil: eintraege
        case .playlists: faecher.playlists
        case .alben: faecher.alben
        case .kuenstler: faecher.kuenstler
        }
    }

    /// Ob unter dieser Kapsel noch etwas vom Server kommt.
    func hatWeitere(_ kapsel: Bibliothekskapsel?) -> Bool {
        switch kapsel {
        case nil: weiterAlben != nil || weiterKuenstler != nil
        case .playlists: false
        case .alben: weiterAlben != nil
        case .kuenstler: weiterKuenstler != nil
        }
    }

    @MainActor
    mutating func ordnen(_ sortierung: Bibliothekssortierung) {
        var alles: [Bibliothekseintrag] = playlists.map { .playlist($0) } + alben.map { .album($0) }
        if !nurGeladen { alles += kuenstler.map { .kuenstler($0) } }
        eintraege = Bibliotheksordnung.ordnen(alles, nach: sortierung, gespielt: gespielt)
        faecher = Bibliotheksfaecher(eintraege)
    }

    /// Serverseitige Sortierung der Alben zur gewählten.
    static func albensortierung(_ s: Bibliothekssortierung) -> Albumsortierung {
        switch s {
        case .zuletztGespielt: .zuletztGehoert
        case .zuletztHinzugefuegt: .neu
        case .name: .name
        }
    }

    @MainActor
    static func laden(nurGeladen: Bool = false, sortierung: Bibliothekssortierung,
                      modell: Musikmodell) async -> Bibliotheksdaten {
        var neu = Bibliotheksdaten(nurGeladen: nurGeladen, laedt: false)
        // Was auf diesem Gerät gespielt wurde, nach der Kennung des Eintrags.
        for v in modell.zuletzt {
            guard let zeit = v.zeit else { continue }
            let art = switch v.art {
            case .album: "album"
            case .kuenstler: "kuenstler"
            case .playlist, .hoerbuch: "playlist"
            }
            neu.gespielt["\(art):\(v.kennung)"] = zeit
        }
        if nurGeladen {
            neu.geladen(modell: modell)
            neu.ordnen(sortierung)
            return neu
        }
        guard let quelle = modell.quelle else { return neu }
        do {
            async let lieblinge = try? quelle.lieblingssongs()
            async let kuenstlerseite = quelle.kuenstlerliste(Listenanfrage(sortierung: .name, anzahl: 200))
            neu.playlists = try await quelle.playlists()
            try await neu.albenLaden(sortierung: sortierung, ab: 0, quelle: quelle)
            let seite = try await kuenstlerseite
            neu.kuenstler = seite.eintraege
            neu.weiterKuenstler = seite.weiterAb
            neu.lieblinge = await lieblinge
        } catch {
            neu.fehler = Stoerung(error)
        }
        neu.ordnen(sortierung)
        return neu
    }

    /// **Alben ohne Singles** — die stehen auf der Seite ihres Künstlers. Bei „zuletzt
    /// gespielt" erst die gespielten, dann der Rest nach Namen.
    private mutating func albenLaden(sortierung: Bibliothekssortierung, ab: Int,
                                     quelle: any Musikquelle) async throws {
        let s = Self.albensortierung(sortierung)
        var holen = s
        if s == .zuletztGehoert, ab == 0 {
            let gespielt = try await quelle.alben(Listenanfrage(sortierung: .zuletztGehoert, anzahl: 100)).eintraege
            // Ohne Zeit vom Server: die Folge des Servers als Rang, hinter
            // allem, was eine echte Zeit hat.
            for (i, a) in gespielt.enumerated() where gespielt[i].zuletztGespielt == nil && self.gespielt["album:\(a.id)"] == nil {
                self.gespielt["album:\(a.id)"] = Date(timeIntervalSince1970: Double(gespielt.count - i))
            }
            alben = gespielt.filter { !$0.istSingle }
            holen = .name
        } else if s == .zuletztGehoert {
            holen = .name
        }
        let seite = try await quelle.alben(Listenanfrage(sortierung: holen, ab: ab, anzahl: 100))
        let da = Set(alben.map(\.id))
        alben += seite.eintraege.filter { !da.contains($0.id) && !$0.istSingle }
        weiterAlben = seite.weiterAb
    }

    /// Die nächste Seite dessen, was unter der Kapsel noch nicht ganz da
    /// ist — unter „Künstler*innen" die Künstler*innen, nicht erst alle Alben.
    @MainActor
    mutating func weiter(fuer kapsel: Bibliothekskapsel?, sortierung: Bibliothekssortierung,
                         modell: Musikmodell) async {
        guard let quelle = modell.quelle else { return }
        do {
            if kapsel != .kuenstler, let ab = weiterAlben {
                weiterAlben = nil
                try await albenLaden(sortierung: sortierung == .zuletztGespielt ? .name : sortierung, ab: ab,
                                     quelle: quelle)
            } else if kapsel != .alben, let ab = weiterKuenstler {
                let seite = try await quelle.kuenstlerliste(Listenanfrage(sortierung: .name, ab: ab, anzahl: 200))
                kuenstler += seite.eintraege
                weiterKuenstler = seite.weiterAb
            }
        } catch {
            weiterAlben = nil
            weiterKuenstler = nil
        }
        laedt = false
        ordnen(sortierung)
    }

    /// Was auf dem Gerät liegt.
    @MainActor
    private mutating func geladen(modell: Musikmodell) {
        let v = modell.ablage.verzeichnis
        alben = v.sammlungen(.album).map { s in
            Album(id: s.verweis.kennung, titel: s.verweis.titel, kuenstler: s.lieder.first?.kuenstler,
                  kuenstlerID: s.lieder.first?.kuenstlerID, liedzahl: s.lieder.count, bild: s.verweis.bild)
        }
        playlists = v.sammlungen(.playlist).map { s in
            Playlist(id: s.verweis.kennung, name: s.verweis.titel, liedzahl: s.lieder.count, bild: s.verweis.bild)
        }
        weiterAlben = nil
        weiterKuenstler = nil
    }
}
