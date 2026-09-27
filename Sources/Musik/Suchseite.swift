import MusikKit
import SwiftUI

/// Die Kapseln unter dem Suchfeld grenzen die Art ein — wie in der
/// Bibliothek (``Kapselwahl``): keine gewählt heißt alles.
enum Sucheart: String, CaseIterable, Identifiable {
    case playlists, alben, kuenstler, lieder
    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .playlists: "Playlists"
        case .alben: "Alben"
        case .kuenstler: "Künstler*innen"
        case .lieder: "Lieder"
        }
    }
}

/// **Suche** — aufgebaut wie die Suche im Player (`SucheView`): oben der
/// Kopf mit Titel „Suche" und Profilbild wie auf jeder Wurzelseite, darunter
/// das Feld, die Kapseln und dann die Treffer als eigene Scrollfläche. Die
/// Treffer laufen nicht unter Kopf und Kapseln durch, sondern beginnen unter
/// ihnen.
///
/// **Tippt man ins Feld, fährt es nach oben**: der Kopf blendet aus, das Feld
/// rückt an seine Stelle, rechts kommt der Ausweg. Die Bewegung liegt an der
/// ganzen Spalte, nicht am Feld allein, und entsteht aus dem Layout
/// (`blattbewegung`). Die Tastatur geht bei jedem Tipp ins Leere zu, der
/// Suchzustand nicht — zu ist er erst mit dem Ausweg.
struct Suchseite: View {
    @Environment(Musikmodell.self) private var modell
    @Environment(\.bereichAktiv) private var bereichAktiv
    @State private var begriff = ""
    @State private var art: Sucheart?
    @State private var position = ScrollPosition(edge: .top)
    @State private var ergebnis: Suchergebnis?
    @State private var fuer = ""
    @State private var fehler: String?
    @State private var sucht = false
    @State private var suchmodus = false
    @State private var kennungen = Zeilenkennungen()
    @State private var blick = Blickmerker()
    @FocusState private var imFeld: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !suchmodus {
                Wurzelkopf(unten: 12) {
                    HStack(alignment: .center, spacing: 0) {
                        Text("Suche")
                            .font(Musikstil.seitentitel)
                            .tracking(Musikstil.sperrungSeitentitel)
                            .foregroundStyle(Stil.schrift)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        Kontoziel()
                    }
                }
                // Nur ausblenden, nicht wegfahren: das Feld rückt nach, die
                // Bewegung kommt aus dem Layout (`SucheView`).
                .transition(.opacity)
            }

            HStack(spacing: 12) {
                Suchfeld(text: $begriff, imFeld: $imFeld)
                if suchmodus {
                    Suchausweg {
                        begriff = ""
                        imFeld = false
                        suchmodus = false
                    }
                }
            }
            .padding(.horizontal, Musikstil.rand)
            // Ist der Kopf weg, trägt das Feld den oberen Abstand selbst.
            .padding(.top, suchmodus ? 8 : 4)

            // Gefiltert wird, was schon da ist — eine Kapsel fragt den Server
            // nicht neu. Die Treffer ziehen an ihren Platz wie in der
            // Bibliothek (``Zeilenkennungen``), Gruppen gehen und kommen.
            Kapselwahl(werte: Sucheart.allCases, name: \.name, gewaehlt: Binding(get: { art }, set: { neu in
                var k = kennungen
                if let ergebnis {
                    k.wechsel(von: Self.folge(ergebnis, art), nach: Self.folge(ergebnis, neu),
                              sichtbar: blick.sichtbareZeilen(zeilenhoehe: Bibliotheksseite.zeilenhoehe))
                }
                position.sofortNachOben()
                withAnimation(Musikstil.blattbewegung) {
                    kennungen = k
                    art = neu
                }
            }))
            .contentMargins(.horizontal, Musikstil.rand, for: .scrollContent)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    treffer
                }
                .padding(.bottom, 24)
            }
            .scrollPosition($position)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGPoint.self) {
                CGPoint(x: $0.containerSize.height, y: $0.contentOffset.y + $0.contentInsets.top)
            } action: { _, neu in
                blick.hoehe = neu.x
                blick.versatz = neu.y
            }
            .scrollDismissesKeyboard(.interactively)
            // Tippen ins Leere schließt die Tastatur.
            .simultaneousGesture(TapGesture().onEnded { imFeld = false })
            // Nur die Trefferfläche zieht sich beim Bereichswechsel heran,
            // Kopf und Feld liegen fest.
            .bereichsinhalt()
        }
        .animation(Musikstil.blattbewegung, value: suchmodus)
        .background(Stil.grund)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: begriff) { await suchen() }
        .onChange(of: imFeld) { _, drin in if drin { suchmodus = true } }
        .onChange(of: modell.sucheNochmal) { _, _ in imFeld = true }
        // Beim Verlassen geht nur die Tastatur zu; die Suche bleibt.
        .onChange(of: bereichAktiv) { _, aktiv in if !aktiv { imFeld = false } }
    }

    // MARK: Treffer

    @ViewBuilder private var treffer: some View {
        let sauber = begriff.trimmingCharacters(in: .whitespaces)
        if sauber.isEmpty {
            Text("Such nach Liedern, Alben, Künstler*innen oder Playlists.")
                .font(.system(size: 15))
                .foregroundStyle(Stil.schriftSehrLeise)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .padding(.top, 60)
        } else if let fehler, ergebnis == nil {
            Text(verbatim: fehler)
                .font(.system(size: 15))
                .foregroundStyle(Stil.schriftLeise)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .padding(.top, 60)
        } else if let ergebnis {
            let leer = sichtbarLeer(ergebnis)
            if leer, !sucht {
                VStack(spacing: 7) {
                    Text("Nichts gefunden")
                        .font(Musikstil.reihe)
                        .tracking(Musikstil.sperrungReihe)
                        .foregroundStyle(Stil.schrift)
                    Text("Zu „\(fuer)“ hat dein Server nichts.")
                        .font(.system(size: 15))
                        .foregroundStyle(Stil.schriftLeise)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 34)
                .padding(.top, 60)
            } else {
                gruppen(ergebnis)
                    .opacity(sucht ? 0.6 : 1)
            }
        } else {
            VStack(spacing: 14) {
                ForEach(0 ..< 5, id: \.self) { _ in Ladefeld(ecke: 8).frame(height: 52) }
            }
            .padding(.horizontal, Musikstil.rand)
            .padding(.top, 24)
        }
    }

    private func sichtbarLeer(_ e: Suchergebnis) -> Bool {
        switch art {
        case nil: e.istLeer
        case .lieder: e.lieder.isEmpty
        case .alben: e.alben.isEmpty
        case .kuenstler: e.kuenstler.isEmpty
        case .playlists: e.playlists.isEmpty
        }
    }

    @ViewBuilder
    private func gruppen(_ e: Suchergebnis) -> some View {
        let spieler = modell.spieler
        if zeigt(.kuenstler), !e.kuenstler.isEmpty {
            gruppentitel("Künstler*innen", .kuenstler)
            ForEach(zeilen(e.kuenstler, .kuenstler)) { z in
                let k = z.wert
                Button { modell.oeffnen(.kuenstler(k)) } label: {
                    Trefferzeile(bild: modell.bildadresse(k.bild, punkte: 52), rund: true,
                                 titel: markiert(k.name), angabe: String(localized: "Künstler (einer)")) {
                        winkel
                    }
                }
                .buttonStyle(Zeilendruck.randbreit)
                .transition(.kapselzeile)
            }
        }
        if zeigt(.alben), !e.alben.isEmpty {
            gruppentitel("Alben", .alben)
            ForEach(zeilen(e.alben, .alben)) { z in
                let a = z.wert
                Button { if modell.frei { modell.albumTippen(a) } } label: {
                    Trefferzeile(bild: modell.bildadresse(a.bild, punkte: 52), titel: markiert(a.titel),
                                 angabe: ([a.artname] + [a.kuenstlerzeile, a.jahr.map(String.init)]
                                    .compactMap { $0 }).joined(separator: " · ")) {
                        winkel
                    }
                }
                .buttonStyle(Zeilendruck.randbreit)
                .langerDruck { Handlungen.album(a, modell) }
                .transition(.kapselzeile)
            }
        }
        if zeigt(.lieder), !e.lieder.isEmpty {
            gruppentitel("Lieder", .lieder)
            ForEach(zeilen(e.lieder, .lieder)) { z in
                let i = z.platz, l = z.wert
                // **„Mehr" neben der Zeile, nicht in ihr** (`Zeilen.swift` im
                // Player): ein Knopf im Knopf war für VoiceOver eine Station
                // mit zwei Handlungen, und welche galt, blieb offen.
                let laeuft = spieler.aktuell?.id == l.id
                HStack(spacing: 13) {
                    Button {
                        guard modell.frei else { return }
                        modell.spielen([l], ab: 0, herkunft: l.albumID.map {
                            Sammlungsverweis(art: .album, kennung: $0, titel: l.album ?? l.titel, bild: l.bild)
                        })
                    } label: {
                        Trefferzeile(bild: modell.bildadresse(l.bild, punkte: 52), titel: markiert(l.titel),
                                     angabe: [l.kuenstlerzeile, l.dauer.map(Zeitformat.dauer)]
                                        .compactMap { $0 }.joined(separator: " · "),
                                     laeuft: laeuft ? spieler.spielt : nil, randRechts: 0) { EmptyView() }
                    }
                    // Rechts endet der Knopf vor „Mehr" (oder am Rand, wenn es
                    // läuft) — die Fläche reicht dort 10 hinaus.
                    .buttonStyle(Zeilendruck(links: Musikstil.rand - 10, rechts: -10))
                    .langerDruck { Handlungen.lied(l, modell) }
                    if !laeuft {
                        Mehrknopf(groesse: 18, farbe: Musikstil.gesungen) { Handlungen.lied(l, modell) }
                    }
                }
                .padding(.trailing, Musikstil.rand)
                .id("\(i)-\(l.id)")
                .transition(.kapselzeile)
            }
        }
        if zeigt(.playlists), !e.playlists.isEmpty {
            gruppentitel("Playlists", .playlists)
            ForEach(zeilen(e.playlists, .playlists)) { z in
                let p = z.wert
                Button { modell.oeffnen(.playlist(p)) } label: {
                    Trefferzeile(bild: modell.bildadresse(p.bild, punkte: 52), titel: markiert(p.name),
                                 angabe: ([String(localized: "Playlist")]
                                    + [p.liedzahl.map { String(localized: "\($0) Lieder") }].compactMap { $0 })
                                    .joined(separator: " · ")) {
                        winkel
                    }
                }
                .buttonStyle(Zeilendruck.randbreit)
                .transition(.kapselzeile)
            }
        }
    }

    /// Die Treffer einer Gruppe mit ihren Kennungen aus ``Zeilenkennungen``.
    private func zeilen<W: Identifiable>(_ werte: [W], _ gruppe: Sucheart) -> [Kapselzeile<W>]
        where W.ID == String {
        werte.enumerated().map { Kapselzeile(id: kennungen.kennung("\(gruppe.rawValue):\($1.id)"), platz: $0, wert: $1) }
    }

    /// **Die Zeilen in der Folge, in der sie dastehen** — Gruppentitel
    /// mitgezählt —, für ``Zeilenkennungen``.
    static func folge(_ e: Suchergebnis, _ art: Sucheart?) -> [String] {
        var folge: [String] = []
        func gruppe(_ g: Sucheart, _ ids: [String]) {
            guard art == nil || art == g, !ids.isEmpty else { return }
            folge.append("titel:\(g.rawValue)")
            folge += ids.map { "\(g.rawValue):\($0)" }
        }
        gruppe(.kuenstler, e.kuenstler.map(\.id))
        gruppe(.alben, e.alben.map(\.id))
        gruppe(.lieder, e.lieder.map(\.id))
        gruppe(.playlists, e.playlists.map(\.id))
        return folge
    }

    private func zeigt(_ a: Sucheart) -> Bool { art == nil || art == a }

    private func gruppentitel(_ text: LocalizedStringKey, _ gruppe: Sucheart) -> some View {
        Text(text)
            .font(Musikstil.zeile)
            .foregroundStyle(Stil.schriftSehrLeise)
            .padding(.horizontal, Musikstil.rand)
            .padding(.top, 20)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
            .id(kennungen.kennung("titel:\(gruppe.rawValue)"))
            .transition(.kapselzeile)
    }

    private var winkel: some View {
        Symbolbild(zeichen: .winkelRechts, groesse: 16)
            .foregroundStyle(Musikstil.gesungen)
            .frame(width: 24)
    }

    /// Der Titel in 15 Medium, der getroffene Teil in Semibold.
    private func markiert(_ titel: String) -> AttributedString {
        var text = AttributedString(titel)
        text.font = .system(size: 15, weight: .medium)
        let gesucht = fuer.trimmingCharacters(in: .whitespaces)
        guard !gesucht.isEmpty,
              let bereich = titel.range(of: gesucht, options: [.caseInsensitive, .diacriticInsensitive]),
              let anfang = AttributedString.Index(bereich.lowerBound, within: text),
              let ende = AttributedString.Index(bereich.upperBound, within: text) else { return text }
        text[anfang ..< ende].font = .system(size: 15, weight: .semibold)
        return text
    }

    // MARK: Suchen

    /// Eine Drittelsekunde nach dem letzten Tastendruck; ein neuer Tastendruck
    /// bricht die laufende Suche ab (`task(id:)`).
    private func suchen() async {
        let sauber = begriff.trimmingCharacters(in: .whitespaces)
        guard !sauber.isEmpty else {
            ergebnis = nil
            fehler = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, let quelle = modell.quelle else { return }
        sucht = true
        defer { if !Task.isCancelled { sucht = false } }
        do {
            let neu = try await quelle.suche(sauber)
            guard !Task.isCancelled else { return }
            ergebnis = neu
            fuer = sauber
            fehler = nil
        } catch {
            guard !Task.isCancelled else { return }
            // Keine alten Treffer unter einem neuen Begriff: die gehörten zu
            // einer anderen Frage (`SucheView` im Player leert sie auch).
            ergebnis = nil
            fehler = Fehlertext.lesbar(error)
        }
    }
}

/// **Ein Treffer**: Hülle 52 (Ecke 8), 13 Abstand, Titel 15 Medium, darunter
/// 13 `schriftSehrLeise`; Innenabstand 7 / 18.
private struct Trefferzeile<Rechts: View>: View {
    let bild: URL?
    var rund = false
    let titel: AttributedString
    let angabe: String
    /// Läuft gerade: der Pegel statt „Mehr".
    var laeuft: Bool?
    /// Der Rand rechts — 0, wenn daneben noch ein Knopf steht.
    var randRechts: CGFloat = Musikstil.rand
    @ViewBuilder var rechts: () -> Rechts

    var body: some View {
        HStack(spacing: 13) {
            Netzhuelle(adresse: bild, zeichengroesse: 18)
                .frame(width: 52, height: 52)
                .clipShape(rund ? AnyShape(Circle())
                           : AnyShape(RoundedRectangle(cornerRadius: Musikstil.eckeKlein, style: .continuous)))
            VStack(alignment: .leading, spacing: 2) {
                Text(titel)
                    .foregroundStyle(Stil.schrift)
                    .lineLimit(1)
                Text(verbatim: angabe)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Stil.schriftSehrLeise)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let laeuft {
                Pegel(laeuft: laeuft).frame(width: 44, height: 44)
            } else {
                rechts()
            }
        }
        .padding(.leading, Musikstil.rand)
        .padding(.trailing, randRechts)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        // Titel und Angabe als eine Station (`BrowseViews` im Player).
        .accessibilityElement(children: .combine)
    }
}

/// **Das Suchfeld** — Maße wie im Player (`Suchfeld` in `Stil.swift`):
/// mindestens 48 hoch, `flaeche`, Ecke 12 statt voller Kapsel, Lupe 17,
/// Text 15, Cursor in `akzent`, Löschen als gefüllter Kreis 17 in einem 44er
/// Ziel.
struct Suchfeld: View {
    @Binding var text: String
    var imFeld: FocusState<Bool>.Binding
    var platzhalter: LocalizedStringKey = "Lieder, Alben, Künstler*innen"

    var body: some View {
        HStack(spacing: 10) {
            Symbolbild(zeichen: .suche, groesse: 17)
                .foregroundStyle(Stil.schriftSehrLeise)
            TextField("", text: $text, prompt: Text(platzhalter).foregroundColor(Stil.schriftSehrLeise))
                .font(Musikstil.suchfeld)
                .foregroundStyle(Stil.schrift)
                .tint(Stil.akzent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(imFeld)
            if !text.isEmpty {
                Button { text = "" } label: {
                    // Zwei Töne: Kreuz in `flaeche`, Scheibe in
                    // `schriftSehrLeise` — das Kreuz liest sich als Aussparung.
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Stil.flaeche, Stil.schriftSehrLeise)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(Druckknopf())
                // Sonst schöbe das 44er Ziel das Feld auseinander.
                .padding(.trailing, -13)
                .accessibilityLabel(Text("Eingabe löschen"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Stil.flaeche, in: RoundedRectangle(cornerRadius: Musikstil.eckeFeld, style: .continuous))
    }
}

/// **Der Ausweg aus dem Suchzustand** — neben dem Feld, nicht darin: im Feld
/// liegt schon das Löschen, und das löscht nur das Wort (`SucheView`).
/// Kreuz 15 Semibold auf einem 36er Kreis in `flaeche`, Ziel 44.
///
/// Kommt zuletzt und geht zuerst: beim Öffnen wartet es, bis der Kopf weg
/// ist, beim Schließen steht es dem Profilbild nicht im Weg.
struct Suchausweg: View {
    let tun: () -> Void

    var body: some View {
        Button(action: tun) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Stil.schriftLeise)
                .frame(width: 36, height: 36)
                .background(Stil.flaeche, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(Druckknopf())
        .accessibilityLabel(Text("Suche schließen"))
        .transition(.asymmetric(
            insertion: .opacity.animation(Musikstil.bewegungReduziert ? Musikstil.blendeReduziert
                                                                       : Musikstil.blattbewegung.delay(0.14)),
            removal: .opacity.animation(.easeOut(duration: 0.09))))
    }
}
