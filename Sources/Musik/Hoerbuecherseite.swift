import MusikKit
import SwiftUI

/// **Hörbücher** — der vierte Bereich, nur wenn der Server welche hat
/// (Übergabe §4 und „Drei Bereiche, ein vierter nur mit Hörbüchern").
/// Aufgebaut wie die Bibliothek: Titel, Raster mit drei Spalten.
struct Hoerbuecherseite: View {
    @Environment(Musikmodell.self) private var modell
    @Environment(\.kachelkante) private var kachelkante
    @State private var buecher: [Hoerbuch]?
    @State private var fehler: Stoerung?
    /// Zählt jedes Laden; nur die Antwort des letzten gilt. Ziehen zum
    /// Aktualisieren und „Erneut versuchen" laufen neben dem `task`.
    @State private var lauf = 0
    /// Wofür zuletzt geladen wurde — ein neuer Blick auf den Reiter lädt
    /// nicht neu, eine andere Bibliothek schon.
    @State private var geladenFuer: Anlass?

    /// Wovon die Liste abhängt. Ändert sich eins, bricht der laufende
    /// `task` ab und ein neuer beginnt — ein einziger Weg statt drei.
    private struct Anlass: Equatable {
        let bibliothek: Int
        let offline: Bool
    }

    var body: some View {
        ScrollView {
            Group {
                if modell.offline, buecher == nil {
                    // Wie die Startseite: ohne Netz kein Warten auf den
                    // Server, sondern der Weg zu dem, was geladen ist.
                    Leerzustand(symbol: "wifi.slash",
                                kopfzeile: Text("Kein Netz"),
                                text: Text("Was du geladen hast, liegt in der Bibliothek und läuft auch so."),
                                knopf: (Text("Zur Bibliothek"), { modell.bereich = .bibliothek }))
                        .padding(.top, 80)
                } else if let buecher {
                    if buecher.isEmpty {
                        Leerzustand(symbol: "book", kopfzeile: Text("Keine Hörbücher"),
                                    text: Text("Der Server hat gerade keine."))
                            .padding(.top, 80)
                    } else {
                        LazyVGrid(columns: Kachelraster.spalten(kachelkante), alignment: .leading,
                                  spacing: Musikstil.rasterZeile) {
                            ForEach(buecher) { buch in
                                Button { if modell.frei { modell.oeffnen(.hoerbuch(buch)) } } label: {
                                    Kachel(bild: modell.bildadresse(buch.bild, punkte: Musikstil.kachelbild), titel: buch.titel,
                                           angabe: buch.autor)
                                }
                                .buttonStyle(Druckknopf())
                                .langerDruck { Handlungen.sammlung(.hoerbuch(buch), titel: buch.titel, modell) }
                            }
                        }
                        .padding(.horizontal, Musikstil.rand)
                    }
                } else if let fehler {
                    Stoerhinweis(stoerung: fehler) {
                        self.fehler = nil
                        Task { await laden() }
                    }
                        .padding(.top, 80)
                } else {
                    Rasterplatzhalter()
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .bereichsinhalt()
        .refreshable { await laden() }
        .safeAreaInset(edge: .top, spacing: 0) {
            Wurzelkopf {
                HStack(alignment: .bottom) {
                    Text("Hörbücher")
                        .font(Musikstil.seitentitel)
                        .tracking(Musikstil.sperrungSeitentitel)
                        .foregroundStyle(Stil.schrift)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Kontoziel()
                }
            }
        }
        .background(Stil.grund)
        .toolbar(.hidden, for: .navigationBar)
        // Eine andere Bibliothek, oder wieder im Netz: frisch holen (wie
        // die Startseite).
        .task(id: Anlass(bibliothek: modell.bibliothekswechsel, offline: modell.offline)) {
            let anlass = Anlass(bibliothek: modell.bibliothekswechsel, offline: modell.offline)
            guard anlass != geladenFuer || buecher == nil, !anlass.offline else { return }
            let andereBibliothek = geladenFuer.map { $0.bibliothek != anlass.bibliothek } ?? false
            geladenFuer = anlass
            // Kein alter Störhinweis, keine Bücher der vorigen Bibliothek
            // bis zur Antwort: der Ladezustand steht da.
            fehler = nil
            if andereBibliothek { buecher = nil }
            await laden()
        }
    }

    private func laden() async {
        guard let quelle = modell.quelle, !modell.offline else { return }
        lauf += 1
        let meiner = lauf
        do {
            let neu = try await quelle.hoerbuecher()
            guard !Task.isCancelled, meiner == lauf else { return }
            withAnimation(Musikstil.einblenden) { buecher = neu }
            fehler = nil
        } catch {
            guard !Task.isCancelled, meiner == lauf else { return }
            fehler = Stoerung(error)
        }
    }
}
