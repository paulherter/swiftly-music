import JellyfinKit
import MusikKit
import SwiftUI

/// **Das Konto** — im Stil von Swiftlys Profil- und Einstellungsseiten
/// (`Sources/Shared/ProfilView.swift`, `EinstellungenView.swift`): eine
/// Unterseite, die von rechts hereinfährt, oben die Konten, darunter Gruppen
/// mit Titel und Karte (`Einstellungsgruppe`). Abmelden fragt vorher, denn
/// danach ist die Anmeldung weg (BRAND.md §7).
///
/// **Eine Seite statt Profil und Einstellungen getrennt wie im Player** —
/// bei fünf Gruppen trägt eine Seite noch; wächst es, wird geteilt wie dort.
///
/// **Was vom Profil des Players fehlt, fehlt mit Grund:** „Swiftly
/// bewerten" (Swiftly Music hat noch keinen Eintrag im App Store — eine
/// erfundene Adresse wäre ein toter Link), „Fehler melden" (die Issues auf
/// GitHub gehören dem Player) und „Eigene Header" (jeder Abruf — Stream,
/// Hülle, Download, Subsonic — müsste sie tragen; nicht für 1.0.4).
struct Kontoseite: View {
    @Environment(Musikmodell.self) private var modell
    @Environment(\.openURL) private var oeffnen
    @State private var protokoll: Protokolldatei?
    @State private var pruefe = false
    @State private var pruefung: String?

    var body: some View {
        VStack(spacing: 0) {
            Unterseitenkopf(titel: Text("Konto"))
            ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Kontokarte()

                wiedergabe

                Einstellungsgruppe(titel: String(localized: "Offline")) {
                    Kontozeile(symbol: "arrow.down.circle", titel: Text("Geladene Musik"),
                               unter: Text(verbatim: belegt))
                    nurWLANZeile
                    if modell.ablage.belegt > 0 {
                        Button { leerenFragen() } label: {
                            Kontozeile(symbol: "trash", titel: Text("Alles Geladene entfernen"), letzte: true,
                                       pfeil: true)
                        }
                        .buttonStyle(Druckzeile(ecke: 0))
                    }
                }

                server

                Einstellungsgruppe(titel: String(localized: "Konten")) {
                    NavigationLink {
                        Kontoaufnahme()
                    } label: {
                        Kontozeile(symbol: "person.badge.plus", titel: Text("Konto hinzufügen"),
                                   unter: Text("Ein zweiter Server oder ein weiteres Konto"), pfeil: true)
                    }
                    .buttonStyle(Druckzeile(ecke: 0))
                    // **Trifft nur das aktive Konto.** Sind noch andere da,
                    // gilt danach das nächste (``Musikmodell/abmelden()``).
                    Button { abmeldenFragen() } label: {
                        Kontozeile(symbol: "rectangle.portrait.and.arrow.right", titel: Text("Abmelden"),
                                   letzte: true, pfeil: true)
                    }
                    .buttonStyle(Druckzeile(ecke: 0))
                }

                // **Discord und Protokoll — ganz unten**, wie im Profil des
                // Players. Wer im Discord einen Fehler meldet, hängt das
                // Protokoll an.
                Einstellungsgruppe(titel: String(localized: "Hilfe")) {
                    Button { oeffnen(Gemeinschaft.discord) } label: {
                        Kontozeile(symbol: "bubble.left.and.bubble.right", titel: Text("Discord beitreten"),
                                   unter: Text("Fragen stellen und sagen, was fehlt"), pfeil: true)
                    }
                    .buttonStyle(Druckzeile(ecke: 0))
                    Button { protokoll = Protokolldatei.schreiben() } label: {
                        Kontozeile(symbol: "doc.text", titel: Text("Protokoll teilen"),
                                   unter: Text("Die letzte Stunde, ohne Zugangsdaten"), letzte: true, pfeil: true)
                    }
                    .buttonStyle(Druckzeile(ecke: 0))
                }

                // Die Fassung an einer Stelle gerechnet (``Fassung``), wie
                // die `Fusszeile` im Player: 12, `schriftSehrLeise`.
                Text(verbatim: Fassung.zeile)
                    .font(Musikstil.angabe)
                    .foregroundStyle(Stil.schriftSehrLeise)
                    .padding(.horizontal, Musikstil.rand)
                    .padding(.top, 26)
            }
            .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(Stil.grund)
        .toolbar(.hidden, for: .navigationBar)
        .background(WischZurueck())
        .sheet(item: $protokoll) { datei in
            Teilenblatt(datei: datei.url)
        }
    }

    // MARK: Gruppen

    /// Wiedergabe: Lautstärke, Streamen, Radio, Technik.
    private var wiedergabe: some View {
        @Bindable var einstellungen = modell.einstellungen
        return Einstellungsgruppe(titel: String(localized: "Wiedergabe")) {
            Einstellzeile(symbol: "speaker.wave.2", titel: Text("Lautstärke angleichen"),
                          unter: Text("Leise und laute Lieder spielen gleich laut."), letzte: false) {
                Schalter(an: $einstellungen.lautheitAngleichen)
            }
            ratenzeile(symbol: "wifi", titel: String(localized: "Streamen über WLAN"),
                       wert: einstellungen.bitrateWLAN) { einstellungen.bitrateWLAN = $0 }
            ratenzeile(symbol: "antenna.radiowaves.left.and.right", titel: String(localized: "Streamen über Mobilfunk"),
                       wert: einstellungen.bitrateMobil) { einstellungen.bitrateMobil = $0 }
            Einstellzeile(symbol: "dot.radiowaves.left.and.right", titel: Text("Danach Ähnliches spielen"),
                          unter: Text("Ist die Schlange zu Ende, geht es mit passenden Liedern weiter."),
                          letzte: false) {
                Schalter(an: $einstellungen.radio)
            }
            // Dasselbe Zeichen und derselbe Name wie im Player.
            Einstellzeile(symbol: "waveform.badge.magnifyingglass", titel: Text("Technische Daten im Player"),
                          unter: Text("Direct Play oder transkodiert, Format und Auflösung")) {
                Schalter(an: $einstellungen.technischeDaten)
            }
        }
        .onChange(of: einstellungen.lautheitAngleichen) { _, _ in modell.spieler.lautstaerkeSetzen() }
    }

    /// **Server** wie in den Einstellungen des Players: Name und Fassung,
    /// darunter „Verbindung prüfen" mit dem Ergebnis in der Zeile.
    private var server: some View {
        Einstellungsgruppe(titel: String(localized: "Server")) {
            Kontozeile(symbol: "externaldrive.connected.to.line.below",
                       titel: Text(verbatim: modell.zugang?.servername ?? ""),
                       unter: Text(verbatim: serverzeile))
            Button { pruefen() } label: {
                Einstellzeile(symbol: "wifi", titel: Text("Verbindung prüfen"),
                              unter: pruefung.map { Text(verbatim: $0) },
                              letzte: (modell.bibliotheken?.count ?? 0) < 2) {
                    if pruefe {
                        Text("Moment…")
                            .font(.system(size: 15))
                            .foregroundStyle(Stil.schriftLeise)
                    } else {
                        Pfeil()
                    }
                }
            }
            .buttonStyle(Druckzeile(ecke: 0))
            .disabled(pruefe)
            // Erst, wenn bekannt ist, wie viele es gibt — vorbelegt mit dem
            // letzten Stand des Kontos (``Musikmodell/bibliotheken``).
            if let liste = modell.bibliotheken, liste.count > 1 { bibliothekszeile(liste) }
        }
    }

    private func pruefen() {
        pruefe = true
        Task {
            pruefung = await modell.verbindungPruefen()
            pruefe = false
        }
    }

    /// Welche Bibliothek Start, Bibliothek und Suche zeigen.
    private func bibliothekszeile(_ liste: [Musikbibliothek]) -> some View {
        let name: (String?) -> String = { id in
            id.flatMap { id in liste.first { $0.id == id }?.name } ?? String(localized: "Alle")
        }
        return Button {
            modell.handlungen = Handlungen.auswahl(String(localized: "Bibliothek"),
                                                   werte: [nil] + liste.map(\.id) as [String?],
                                                   gewaehlt: modell.bibliothek, name: name) { modell.bibliothekWaehlen($0) }
        } label: {
            Einstellzeile(symbol: "books.vertical", titel: Text("Bibliothek")) {
                Wertanzeige(wert: name(modell.bibliothek))
            }
        }
        .buttonStyle(Druckzeile(ecke: 0))
    }

    private var nurWLANZeile: some View {
        @Bindable var einstellungen = modell.einstellungen
        return Einstellzeile(symbol: "wifi", titel: Text("Nur über WLAN laden"),
                             unter: modell.ablage.wartetAufNetz ? Text("Wartet auf WLAN.") : nil,
                             letzte: modell.ablage.belegt == 0) {
            Schalter(an: $einstellungen.nurWLANLaden)
        }
        .onChange(of: einstellungen.nurWLANLaden) { _, _ in modell.ladeerlaubnisGeaendert() }
    }

    /// Eine Höchstrate: „Original" oder kbit/s, gewählt im eigenen Blatt.
    private func ratenzeile(symbol: String, titel: String, wert: Int, letzte: Bool = false,
                            waehlen: @escaping @MainActor (Int) -> Void) -> some View {
        Button {
            modell.handlungen = Handlungen.auswahl(titel, werte: Musikeinstellungen.raten, gewaehlt: wert,
                                                   name: Musikeinstellungen.name(rate:), waehlen: waehlen)
        } label: {
            Einstellzeile(symbol: symbol, titel: Text(verbatim: titel),
                          unter: wert == 0 ? Text("Die Datei, wie sie auf dem Server liegt.") : nil,
                          letzte: letzte) {
                Wertanzeige(wert: Musikeinstellungen.name(rate: wert))
            }
        }
        .buttonStyle(Druckzeile(ecke: 0))
    }

    private func abmeldenFragen() {
        let modell = modell
        let andere = !(modell.konten?.andere.isEmpty ?? true)
        modell.handlungen = Handlungen.rueckfrage(
            String(localized: "Abmelden?"),
            hinweis: andere
                ? String(localized: "Danach gilt dein nächstes Konto. Die geladene Musik bleibt auf dem iPhone.")
                : String(localized: "Die geladene Musik bleibt auf dem iPhone und ist wieder da, wenn du dich mit diesem Konto anmeldest."),
            handlung: String(localized: "Abmelden"), symbol: "rectangle.portrait.and.arrow.right") {
                Task { await modell.abmelden() }
            }
    }

    private func leerenFragen() {
        let ablage = modell.ablage
        modell.handlungen = Handlungen.rueckfrage(
            String(localized: "Alles Geladene entfernen?"),
            hinweis: String(localized: "Die Lieder lassen sich jederzeit neu laden."),
            handlung: String(localized: "Entfernen"), symbol: "trash") { ablage.alleEntfernen() }
    }

    private var serverzeile: String {
        guard let quelle = modell.quelle else { return "" }
        let adresse = quelle.konto.server
        let ort = adresse.host().map { host in adresse.port.map { "\(host):\($0)" } ?? host } ?? adresse.absoluteString
        guard let beschreibung = modell.zugang?.serverbeschreibung, !beschreibung.isEmpty else { return ort }
        return "\(ort) · \(beschreibung)"
    }

    private var belegt: String {
        let byte = modell.ablage.belegt
        guard byte > 0 else { return String(localized: "Nichts geladen") }
        return ByteCountFormatter.string(fromByteCount: byte, countStyle: .file)
    }
}

// MARK: - Konten

/// **Die Konten oben auf der Seite**, wie die `Kontokarte` im Profil des
/// Players: vorn das aktive (Zeichen 56, Name, Server), darunter eine Reihe
/// der anderen (40) und ein gestrichelter Kreis zum Hinzufügen. Ein Tipp auf
/// ein anderes Konto wechselt.
///
/// Anders als im Player eine Karte für alle Server statt einer Seite je
/// Server: Swiftly Music hat selten mehr als zwei Konten, und eine Reihe
/// liest sich schneller als ein Blättern.
private struct Kontokarte: View {
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        Einstellungskarte {
            kopfzeile
            Rectangle().fill(Stil.linie).frame(height: 1)
                .padding(.leading, 16)
            reihe
        }
    }

    private var kopfzeile: some View {
        HStack(spacing: 14) {
            Profilzeichen(name: modell.benutzername, bild: modell.quelle?.profilbildadresse(kante: 180),
                          groesse: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: modell.benutzername)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.136)
                    .foregroundStyle(Stil.schrift)
                    .lineLimit(1)
                Text(verbatim: modell.zugang?.servername ?? "")
                    .font(Musikstil.angabe)
                    .foregroundStyle(Stil.schriftSehrLeise)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(Stil.akzent).frame(width: 6, height: 6)
                    Text("Verbunden · \(modell.zugang?.serverbeschreibung ?? "")")
                        .font(Musikstil.angabe)
                        .foregroundStyle(Stil.schriftSehrLeise)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private var reihe: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(modell.konten?.andere ?? [], id: \.kontokennung.schluessel) { konto in
                    Button { Task { await modell.kontoWechseln(zu: konto) } } label: {
                        Profilzeichen(name: konto.benutzername, bild: konto.profilbild, groesse: 40)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(Druckknopf())
                    .accessibilityLabel(Text("Wechseln zu \(konto.benutzername), \(konto.servername)"))
                }
                NavigationLink {
                    Kontoaufnahme()
                } label: {
                    Image(systemName: "plus")
                        .font(Musikstil.zeile)
                        .foregroundStyle(Stil.schriftSehrLeise)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Circle().strokeBorder(Stil.rand, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(Druckknopf())
                .accessibilityLabel(Text("Weiteres Konto hinzufügen"))
            }
            .padding(14)
        }
        .scrollIndicators(.hidden)
    }
}

/// Der Winkel am Ende einer Zeile, die weiterführt oder etwas tut
/// (`Profilzeile` im Player: 13 Semibold, `schriftSehrLeise`).
struct Pfeil: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Stil.schriftSehrLeise)
            .accessibilityHidden(true)
    }
}

/// Die Listenzeile: Symbol 17 in 20 breiter Spalte, 14 Abstand, Titel 15
/// Semibold, Unterzeile 12 `schriftSehrLeise`, Haarlinie ab der Textkante.
/// **Wer tippbar ist, trägt den Winkel** (`pfeil`) — auch eine Handlung wie
/// „Abmelden", wie jede `Profilzeile` im Player.
private struct Kontozeile: View {
    let symbol: String
    let titel: Text
    var unter: Text?
    var letzte = false
    var pfeil = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(Stil.schrift)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    titel
                        .font(Musikstil.zeile)
                        .foregroundStyle(Stil.schrift)
                        .lineLimit(1)
                    if let unter {
                        unter
                            .font(Musikstil.angabe)
                            .foregroundStyle(Stil.schriftSehrLeise)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if pfeil { Pfeil() }
            }
            .padding(.horizontal, Musikstil.rand)
            .padding(.vertical, 14)
            if !letzte {
                Rectangle().fill(Stil.linie).frame(height: 1)
                    .padding(.leading, Musikstil.rand + 34)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// **Eine Einstellung**: Zeichen, Titel und Unterzeile wie `Kontozeile`,
/// rechts ein Schalter oder der gewählte Wert (`Profilzeile` im Player).
struct Einstellzeile<Rechts: View>: View {
    let symbol: String
    let titel: Text
    var unter: Text?
    var letzte = true
    @ViewBuilder var rechts: () -> Rechts

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(Stil.schrift)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    titel
                        .font(Musikstil.zeile)
                        .foregroundStyle(Stil.schrift)
                    if let unter {
                        unter
                            .font(Musikstil.angabe)
                            .foregroundStyle(Stil.schriftSehrLeise)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                rechts()
            }
            .padding(.horizontal, Musikstil.rand)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            if !letzte {
                Rectangle().fill(Stil.linie).frame(height: 1)
                    .padding(.leading, Musikstil.rand + 34)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Der gewählte Wert mit Winkel — tippen öffnet die Auswahl.
struct Wertanzeige: View {
    let wert: String

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: wert)
                .font(.system(size: 15))
                .foregroundStyle(Stil.schriftLeise)
            Pfeil()
        }
    }
}
