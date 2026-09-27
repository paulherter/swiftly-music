import MusikKit
import SwiftUI
import UIKit

// **Playlists wie bei Spotify** — anlegen, umbenennen, löschen, Lieder
// hinzufügen, entfernen, umsortieren. Jede Änderung steht sofort da und
// dreht sich bei einem Fehler des Servers zurück, mit einem kurzen Hinweis.

// MARK: - Nach einem Namen fragen

/// Was das Namensblatt fragt.
struct Namensfrage: Identifiable {
    let id = UUID()
    let titel: String
    var vorgabe: String = ""
    let knopf: String
    let tun: @MainActor (String) -> Void
}

/// **Ein Blatt mit einem Feld** — für „Neue Playlist" und „Umbenennen".
/// Eigenes Blatt statt einer Systemabfrage (die erscheint als Glas).
struct Namensebene: View {
    @Environment(Musikmodell.self) private var modell
    @State private var zuletzt: Namensfrage?
    @State private var name = ""
    @FocusState private var imFeld: Bool
    /// **Was das Blatt zeigt, steht schon im Baum, bevor es aufgeht** — wie
    /// bei `Handlungsebene`: hing der Inhalt direkt an `modell.namensfrage`,
    /// entstand er im selben Augenblick, in dem das Blatt aufging, und fuhr
    /// den animierten Versatz nicht mit. Jetzt steht `zuletzt` zuerst, und
    /// das Blatt geht einen Takt später auf.
    @State private var offen = false

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .musikblatt(offen: Binding(get: { offen },
                                       set: { if !$0 { offen = false; modell.namensfrage = nil } })) {
                if let frage = zuletzt { inhalt(frage) }
            }
            .onChange(of: modell.namensfrage?.id) { _, neu in
                guard neu != nil, let frage = modell.namensfrage else {
                    offen = false
                    imFeld = false
                    return
                }
                zuletzt = frage
                name = frage.vorgabe
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(30))
                    offen = modell.namensfrage != nil
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    imFeld = true
                }
            }
    }

    private func inhalt(_ frage: Namensfrage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: frage.titel)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.136)
                .foregroundStyle(Stil.schrift)
                .padding(.top, 5)
                .padding(.bottom, 14)
                .accessibilityAddTraits(.isHeader)
            TextField("", text: $name, prompt: Text("Name").foregroundColor(Stil.schriftSehrLeise))
                .font(.system(size: 17))
                .foregroundStyle(Stil.schrift)
                .tint(Stil.akzent)
                .focused($imFeld)
                .submitLabel(.done)
                .onSubmit { fertig(frage) }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Stil.gruppenflaeche, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button { fertig(frage) } label: { Text(verbatim: frage.knopf) }
                .buttonStyle(HauptknopfStil())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.top, 16)
            Button { modell.namensfrage = nil } label: {
                Text("Abbrechen")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Stil.schriftLeise)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(Druckknopf())
            .padding(.top, 4)
        }
        .padding(.horizontal, Musikstil.rand)
        .padding(.bottom, 8)
    }

    private func fertig(_ frage: Namensfrage) {
        let neu = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !neu.isEmpty else { return }
        modell.namensfrage = nil
        frage.tun(neu)
    }
}

// MARK: - Wischen auf einer Zeile

/// Was ein Wisch auf einer Zeile tut.
struct Wischhandlung {
    let symbol: String
    let text: LocalizedStringKey
    var farbe: Color = Stil.akzent
    let tun: () -> Void
}

/// **Eine Zeile, die sich wischen lässt** — nach rechts für „Zur
/// Warteschlange", nach links für „Entfernen". Gebaut wie `Wischzeile` im
/// Player: eine waagerechte Scrollfläche je Zeile statt einer eigenen Geste,
/// damit das senkrechte Scrollen der Liste nicht hängt; ein weiter Wisch löst
/// aus, ein kurzer lässt die Handlung stehen.
struct Wischzeile<Inhalt: View>: View {
    var links: Wischhandlung?
    var rechts: Wischhandlung?
    @ViewBuilder var inhalt: () -> Inhalt

    private enum Feld: Hashable { case links, inhalt, rechts }
    @State private var sichtbar: Feld? = .inhalt
    @State private var weite: CGFloat = 0
    @State private var ausgeloest = false
    @State private var lauf = 0

    private let breite: CGFloat = 96
    private let schwelle: CGFloat = 150

    var body: some View {
        let anfang: CGFloat = links == nil ? 0 : breite
        // **Die `.id(lauf)` braucht einen Behälter um sich.** Ein
        // `LazyVStack` sucht die Kennung einer Zeile durch Modifikatoren wie
        // `.background` hindurch — auch im `body` dieser Ansicht. Ohne den
        // `ZStack` hießen alle Zeilen `0`, und Album, Playlist und
        // Lieblingssongs zeigten nur das erste Lied (gemessen 24.09.: 14
        // Lieder, Liste 672 hoch, gezeichnet eine Zeile; ohne `.id` zehn,
        // so viele wie auf den Schirm passen).
        ZStack {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    if let links { knopf(links).id(Feld.links) }
                    inhalt()
                        .containerRelativeFrame(.horizontal)
                        .overlay(alignment: .topLeading) { RandGesteVorrang().frame(width: 0, height: 0) }
                        .id(Feld.inhalt)
                    if let rechts { knopf(rechts).id(Feld.rechts) }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, neu in
                weite = neu - anfang
                if !ausgeloest, weite > schwelle, let rechts { ausloesen(rechts) }
                if !ausgeloest, weite < -schwelle, let links { ausloesen(links) }
                if abs(weite) <= 1 { ausgeloest = false }
            }
            .scrollTargetBehavior(.viewAligned)
            // **Zu Beginn steht der Inhalt da, nicht die linke Handlung.** Den
            // Anfangswert von `scrollPosition` nimmt eine frische Scrollfläche
            // nicht an — sie begann bei 0, und „Warteschlange" stand offen.
            // Links und rechts sind gleich breit: mit beiden liegt der Inhalt in
            // der Mitte, mit nur links am Ende.
            .defaultScrollAnchor(links == nil ? .leading : rechts == nil ? .trailing : .center, for: .initialOffset)
            .scrollPosition(id: $sichtbar, anchor: .leading)
            .id(lauf)
        }
        // **Farbe nur, wo die Handlung aufgedeckt ist.** Vorher lag unter der
        // ganzen Zeile die Farbe und über dem Inhalt `grund`, der sie
        // verdeckte — auf einer Seite in der Farbe ihrer Hülle stand dann
        // jede Zeile als grauer Streifen. Jetzt ist die Zeile durchsichtig,
        // und die Farbe ist so breit, wie der Wisch weit ist.
        .background(alignment: weite > 0 ? .trailing : .leading) {
            if let farbe = weite > 0.5 ? rechts?.farbe : weite < -0.5 ? links?.farbe : nil {
                farbe.frame(width: abs(weite))
            }
        }
    }

    private func knopf(_ h: Wischhandlung) -> some View {
        Button { ausloesen(h) } label: {
            VStack(spacing: 4) {
                Image(systemName: h.symbol).font(.system(size: 17, weight: .semibold))
                Text(h.text).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Stil.grund)
            .frame(width: breite)
            .frame(maxHeight: .infinity)
        }
        .buttonStyle(Druckknopf())
    }

    private func ausloesen(_ h: Wischhandlung) {
        ausgeloest = true
        Musikstil.ruck(.mittel)
        h.tun()
        lauf += 1
        sichtbar = .inhalt
    }
}

/// **Der Wisch vom Rand geht zurück, nicht in die Zeile** (`RandGesteVorrang`
/// in `Sources/iOS/Orientierung.swift`): die Scrollfläche der Zeile wartet,
/// bis die Zurück-Geste des Stapels aufgegeben hat.
struct RandGesteVorrang: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Halter() }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}

    private final class Halter: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            DispatchQueue.main.async { [weak self] in self?.verknuepfen() }
        }

        private func verknuepfen() {
            guard let zurueck = navigationController?.interactivePopGestureRecognizer else { return }
            var ansicht: UIView? = view.superview
            while let a = ansicht {
                if let scroll = a as? UIScrollView {
                    scroll.panGestureRecognizer.require(toFail: zurueck)
                    return
                }
                ansicht = a.superview
            }
        }
    }
}

// MARK: - Die Handlungen

extension Musikmodell {

    /// **„Zu Playlist hinzufügen"**: ein eigenes Blatt, oben „Neue
    /// Playlist", darunter die Lieblingssongs (ab zwei Liedern,
    /// ``lieblingszeile(_:)``), dann die Playlists, zuletzt geänderte zuerst.
    func zuPlaylist(_ lieder: [Lied]) {
        guard !lieder.isEmpty, let quelle else { return }
        Task { [weak self] in
            let liste: [Playlist]
            do {
                liste = try await quelle.playlists()
            } catch {
                self?.hinweis = Fehlertext.lesbar(error)
                return
            }
            guard let self else { return }
            let sortiert = liste.sorted { ($0.geaendert ?? .distantPast) > ($1.geaendert ?? .distantPast) }
            var handlungen = [Handlung(text: String(localized: "Neue Playlist"), symbol: "plus") { [weak self] in
                self?.neuePlaylist(mit: lieder)
            }]
            if let zeile = lieblingszeile(lieder) { handlungen.append(zeile) }
            handlungen += sortiert.map { p in
                Handlung(text: p.name, symbol: "music.note.list") { [weak self] in
                    Task { await self?.hinzufuegen(lieder, zu: p) }
                }
            }
            self.handlungen = Handlungsliste(titel: String(localized: "Zu Playlist hinzufügen"), handlungen: handlungen)
        }
    }

    /// **Die Lieblingssongs im Blatt** — für ein Album, eine Playlist, einen
    /// Künstler oder mehrere Lieder; bei einem einzelnen Lied nicht, dort
    /// ist das Herz am Lied. Was sie anbietet, rechnet ``Lieblingsauswahl``:
    /// hinzufügen, was noch kein Herz hat, oder — haben alle eins — alle
    /// heraus, ab zwei Liedern nach einer Rückfrage.
    private func lieblingszeile(_ lieder: [Lied]) -> Handlung? {
        guard let angebot = Lieblingsauswahl.angebot(lieder.map(\.id), istFavorit: { id in
            istFavorit(id, sonst: lieder.first { $0.id == id }?.favorit ?? false)
        }) else { return nil }
        let betroffen = angebot.ids.compactMap { id in lieder.first { $0.id == id } }
        let name = String(localized: "Lieblingssongs")
        guard !angebot.an else {
            return Handlung(text: name, lieblingskachel: true) { [weak self] in
                Task {
                    guard await self?.favoritenSetzen(betroffen, an: true) == true else { return }
                    self?.hinweis = String(localized: "In „\(name)“ gelegt.")
                }
            }
        }
        let entfernen = { @MainActor [weak self] in
            Task {
                guard await self?.favoritenSetzen(betroffen, an: false) == true else { return }
                self?.hinweis = String(localized: "Aus den Lieblingssongs.")
            }
            return
        }
        return Handlung(text: String(localized: "Aus Lieblingssongs entfernen"), lieblingskachel: true) { [weak self] in
            guard angebot.rueckfrage else { return entfernen() }
            // Die Rückfrage folgt im selben Blatt, wie beim Löschen aus „Mehr".
            self?.handlungen = Handlungen.rueckfrage(
                String(localized: "\(betroffen.count) Lieder aus den Lieblingssongs nehmen?"),
                hinweis: String(localized: "Die Lieder bleiben, nur das Herz geht weg."),
                handlung: String(localized: "Entfernen"), symbol: "heart.slash", tun: entfernen)
        }
    }

    /// Fragt nach dem Namen und legt an, auf Wunsch gleich mit Liedern.
    func neuePlaylist(mit lieder: [Lied] = []) {
        namensfrage = Namensfrage(titel: String(localized: "Neue Playlist"), knopf: String(localized: "Anlegen")) {
            [weak self] name in
            Task { await self?.playlistAnlegen(name: name, lieder: lieder) }
        }
    }

    func playlistAnlegen(name: String, lieder: [Lied]) async {
        guard let quelle else { return }
        do {
            _ = try await quelle.playlistAnlegen(name: name, lieder: lieder)
            playlistwechsel += 1
            hinweis = lieder.isEmpty ? String(localized: "Playlist angelegt.")
                                     : String(localized: "In „\(name)“ gelegt.")
        } catch {
            hinweis = Fehlertext.lesbar(error)
        }
    }

    /// **Doppelte erlaubt, aber erst nach Rückfrage** — steht schon etwas
    /// davon in der Playlist, fragt das Blatt „trotzdem hinzufügen?".
    func hinzufuegen(_ lieder: [Lied], zu playlist: Playlist, pruefen: Bool = true) async {
        guard let quelle else { return }
        if pruefen, let vorhanden = try? await quelle.playlist(playlist.id).lieder,
           !Playlistfolge.schonDarin(lieder, in: vorhanden).isEmpty {
            handlungen = Handlungsliste(
                titel: String(localized: "Schon in der Playlist"),
                hinweis: lieder.count == 1 ? String(localized: "Das Lied steht schon in „\(playlist.name)“.")
                                           : String(localized: "Ein Teil davon steht schon in „\(playlist.name)“."),
                handlungen: [Handlung(text: String(localized: "Trotzdem hinzufügen"), symbol: "plus") { [weak self] in
                    Task { await self?.hinzufuegen(lieder, zu: playlist, pruefen: false) }
                }])
            return
        }
        do {
            try await quelle.playlistErgaenzen(playlist.id, lieder: lieder)
            playlistwechsel += 1
            hinweis = String(localized: "In „\(playlist.name)“ gelegt.")
        } catch {
            hinweis = Fehlertext.lesbar(error)
        }
    }

    func umbenennen(_ playlist: Playlist, bei erfolg: @escaping @MainActor (String) -> Void) {
        namensfrage = Namensfrage(titel: String(localized: "Umbenennen"), vorgabe: playlist.name,
                                  knopf: String(localized: "Sichern")) { [weak self] name in
            guard let self, let quelle = self.quelle else { return }
            // Sofort umbenannt; lehnt der Server ab, wieder zurück.
            erfolg(name)
            Task {
                do {
                    try await quelle.playlistUmbenennen(playlist.id, name: name)
                    self.playlistwechsel += 1
                } catch {
                    erfolg(playlist.name)
                    self.hinweis = Fehlertext.lesbar(error)
                }
            }
        }
    }

    /// Löschen fragt vorher — da geht etwas verloren.
    func loeschenFragen(_ playlist: Playlist, danach: @escaping @MainActor () -> Void) {
        handlungen = Handlungen.rueckfrage(
            String(localized: "„\(playlist.name)“ löschen?"),
            hinweis: String(localized: "Die Playlist ist dann auch auf dem Server weg. Die Lieder bleiben."),
            handlung: String(localized: "Löschen"), symbol: "trash") { [weak self] in
                guard let self, let quelle = self.quelle else { return }
                danach()
                Task {
                    do {
                        try await quelle.playlistLoeschen(playlist.id)
                        self.playlistwechsel += 1
                        self.hinweis = String(localized: "Playlist gelöscht.")
                    } catch {
                        self.hinweis = Fehlertext.lesbar(error)
                        self.playlistwechsel += 1
                    }
                }
            }
    }

    /// Hinten an die Schlange, mit kurzer Bestätigung — der Wisch nach rechts.
    func zurWarteschlange(_ lied: Lied) {
        hintenAn([lied])
    }
}

// MARK: - Bearbeiten

/// **Eine Playlist bearbeiten** — umsortieren am Griff, entfernen mit dem
/// Minus oder per Wisch. Jede Änderung steht sofort da und geht gleich an
/// den Server; lehnt er ab, springt die Liste zurück.
struct Playlistbearbeitung: View {
    let playlist: Playlist
    @Environment(Musikmodell.self) private var modell
    @State private var detail: Playlistdetail?
    @State private var fehler: Stoerung?

    var body: some View {
        VStack(spacing: 0) {
            Unterseitenkopf(titel: Text(verbatim: playlist.name))
            if let detail {
                if detail.lieder.isEmpty {
                    Leerzustand(symbol: "music.note.list", kopfzeile: Text("Die Playlist ist leer"),
                                text: Text("Über „Zu Playlist hinzufügen“ kommen Lieder hinein."))
                        .padding(.top, 60)
                    Spacer(minLength: 0)
                } else {
                    List {
                        ForEach(Array(zip(detail.lieder, detail.eintraege)), id: \.1) { lied, _ in
                            zeile(lied)
                                .listRowBackground(Stil.grund)
                                .listRowSeparatorTint(Stil.linie)
                                .listRowInsets(EdgeInsets(top: 6, leading: Musikstil.rand, bottom: 6, trailing: 12))
                        }
                        .onMove { von, vor in verschieben(von, vor) }
                        .onDelete { stellen in entfernen(stellen) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(.active))
                    .tint(Stil.fehler)
                }
            } else if let fehler {
                Stoerhinweis(stoerung: fehler) { Task { await laden() } }
                    .padding(.top, 60)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 12) {
                    ForEach(0 ..< 8, id: \.self) { _ in Ladefeld(ecke: 8).frame(height: 44) }
                }
                .padding(.horizontal, Musikstil.rand)
                Spacer(minLength: 0)
            }
        }
        .background(Stil.grund)
        .toolbar(.hidden, for: .navigationBar)
        .background(WischZurueck())
        .task { await laden() }
    }

    private func zeile(_ lied: Lied) -> some View {
        HStack(spacing: 12) {
            Netzhuelle(adresse: modell.bildadresse(lied.bild, punkte: 44), zeichengroesse: 16)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: Musikstil.eckeKlein, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: lied.titel)
                    .font(Musikstil.zeile)
                    .foregroundStyle(Stil.schrift)
                    .lineLimit(1)
                if let k = lied.kuenstlerzeile {
                    Text(verbatim: k)
                        .font(.system(size: 13))
                        .foregroundStyle(Stil.schriftSehrLeise)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func laden() async {
        guard let quelle = modell.quelle else { return }
        do {
            detail = try await quelle.playlist(playlist.id)
            fehler = nil
        } catch {
            fehler = Stoerung(error)
        }
    }

    private func verschieben(_ von: IndexSet, _ vor: Int) {
        guard let alt = detail, let quelle = modell.quelle, let erste = von.first else { return }
        let nach = Playlistfolge.zielstelle(von: erste, vorStelle: vor)
        guard nach != erste else { return }
        var neu = alt
        neu.lieder = Playlistfolge.verschoben(alt.lieder, von: erste, nach: nach)
        neu.eintraege = Playlistfolge.verschoben(alt.eintraege, von: erste, nach: nach)
        detail = neu
        Task {
            do {
                try await quelle.playlistVerschieben(playlist.id, von: erste, nach: nach, vorher: alt)
                await laden()
                modell.playlistwechsel += 1
            } catch {
                detail = alt
                modell.hinweis = Fehlertext.lesbar(error)
            }
        }
    }

    private func entfernen(_ stellen: IndexSet) {
        guard let alt = detail, let quelle = modell.quelle else { return }
        var neu = alt
        neu.lieder = Playlistfolge.ohne(alt.lieder, stellen: Set(stellen))
        neu.eintraege = Playlistfolge.ohne(alt.eintraege, stellen: Set(stellen))
        detail = neu
        Task {
            do {
                try await quelle.playlistEntfernen(playlist.id, stellen: Array(stellen), vorher: alt)
                await laden()
                modell.playlistwechsel += 1
            } catch {
                detail = alt
                modell.hinweis = Fehlertext.lesbar(error)
            }
        }
    }
}
