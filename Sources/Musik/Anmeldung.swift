import JellyfinKit
import MusikKit
import SubsonicKit
import SwiftUI

/// **Anmelden: erst die Adresse, dann Name und Passwort.**
///
/// Welcher Server dort läuft, findet die App selbst heraus: erst Jellyfin
/// (`/System/Info/Public`), dann Subsonic (`/rest/ping.view` ohne Anmeldung —
/// ein Subsonic antwortet darauf mit einem Fehler, aber in seinem Umschlag).
/// Aussehen und Ablauf wie Swiftlys `ConnectView` und `LoginView`
/// (`Sources/Shared/RootView.swift`); einen Musik-Entwurf dafür gibt es nicht.
@MainActor
@Observable
final class Anmeldemodell {

    struct Erkannt: Equatable {
        let art: Serverart
        let adresse: URL
        let name: String
        /// „Jellyfin 10.10.3", „Navidrome 0.64.0".
        let beschreibung: String
    }

    var adresse = ""
    var benutzer = ""
    var passwort = ""
    private(set) var erkannt: Erkannt?
    private(set) var arbeitet = false
    private(set) var fehler: String?
    /// Quick Connect bietet nur Jellyfin — und nur, wenn der Server es anhat.
    private(set) var quickConnect = false
    /// **Wer hier Musik hört** — die öffentlichen Benutzer eines Jellyfin
    /// (`Users/Public`), mit ihren Bildern. Subsonic kennt so etwas nicht.
    private(set) var bekannte: [OeffentlicherBenutzer] = []
    private(set) var bilder: [String: URL] = [:]

    @ObservationIgnored private var jellyfin: JellyfinClient?

    init() {
        adresse = UserDefaults.standard.string(forKey: "musik.letzteAdresse") ?? ""
    }

    // MARK: Adresse

    func verbinden() async {
        guard !adresse.isEmpty, !arbeitet else { return }
        fehler = nil
        guard let url = AppModelURLNormalizer.normalize(adresse) else {
            fehler = lesbarerFehler(JellyfinError.invalidServerURL)
            return
        }
        arbeitet = true
        defer { arbeitet = false }
        do {
            try await erkennen(url)
        } catch let erster {
            // Ohne Schema geraten und an der Verbindung gescheitert: das andere
            // Schema versuchen, wie im Player (nie bei einer Fehlerantwort).
            if !adresse.contains("://"), erster is URLError || (erster as? JellyfinError)?.urlFehlercode != nil,
               let anders = AppModelURLNormalizer.andersHerum(url),
               (try? await erkennen(anders)) != nil {
                return
            }
            fehler = anschlussfehler(erster, adresse: url)
        }
    }

    private func erkennen(_ url: URL) async throws {
        let client = JellyfinClient(baseURL: url, deviceID: Geraetekennung.wert,
                                    deviceName: UIDevice.current.name, programm: Quellenbau.programm)
        let jellyfinFehler: any Error
        do {
            let info = try await client.publicSystemInfo()
            jellyfin = client
            // **Die Maske kommt sofort nach der Erkennung**, wie im Player
            // (`AppModel.verbindeMit`, dann `LoginView.task`). Quick Connect,
            // die öffentlichen Benutzer und ihre Bilder holt die Maske selbst
            // (``bekannteLaden()``) — vorher wartete die Seite der Reihe nach
            // auf alles, bevor sich überhaupt etwas tat.
            quickConnect = false
            bekannte = []
            bilder = [:]
            let name = info.serverName.flatMap { $0.isEmpty ? nil : $0 } ?? url.host() ?? "Jellyfin"
            fertigErkannt(Erkannt(art: .jellyfin, adresse: url, name: name,
                                  beschreibung: "Jellyfin \(info.version ?? "")".trimmingCharacters(in: .whitespaces)))
            return
        } catch {
            jellyfinFehler = error
        }
        do {
            let server = try await SubsonicClient.erkennen(server: url) { anfrage in
                try await URLSession.ortsnetzfaehig.data(for: anfrage)
            }
            jellyfin = nil
            quickConnect = false
            bekannte = []
            bilder = [:]
            fertigErkannt(Erkannt(art: .subsonic, adresse: url, name: url.host() ?? server.anzeigename,
                                  beschreibung: server.anzeigename))
        } catch {
            // Kam nirgends eine Verbindung zustande, zählt der Netzfehler —
            // sonst läuft dort schlicht keiner der beiden.
            if jellyfinFehler is URLError || (jellyfinFehler as? JellyfinError)?.urlFehlercode != nil
                || (jellyfinFehler as? JellyfinError).map({ if case .zertifikat = $0 { true } else { false } }) == true {
                throw jellyfinFehler
            }
            throw SubsonicFehler.keinSubsonic
        }
    }

    /// **Wer hört, und geht Quick Connect?** Aus dem `task` der Maske;
    /// alles zugleich, die Bilder nebeneinander.
    func bekannteLaden() async {
        guard let client = jellyfin, erkannt?.art == .jellyfin else { return }
        async let qc = client.quickConnectVerfuegbar()
        let leute = (try? await client.oeffentlicheBenutzer()) ?? []
        let karte = await withTaskGroup(of: (String, URL?).self) { gruppe in
            for person in leute {
                gruppe.addTask { (person.id, await client.benutzerbild(person)) }
            }
            var karte: [String: URL] = [:]
            for await (id, bild) in gruppe {
                if let bild { karte[id] = bild }
            }
            return karte
        }
        let geht = await qc
        guard !Task.isCancelled, jellyfin === client else { return }
        withAnimation(Musikstil.einblenden) {
            quickConnect = geht
            bekannte = leute
            bilder = karte
        }
        // Bei genau einem Konto gibt es nichts zu wählen (wie im Player).
        if leute.count == 1, benutzer.isEmpty { benutzer = leute[0].name }
    }

    private func fertigErkannt(_ neu: Erkannt) {
        UserDefaults.standard.set(adresse, forKey: "musik.letzteAdresse")
        withAnimation(Musikstil.einblenden) { erkannt = neu }
    }

    private func anschlussfehler(_ fehler: any Error, adresse: URL) -> String {
        if AppModelURLNormalizer.istImHeimnetz(adresse.host() ?? ""),
           (fehler as? URLError)?.code == .notConnectedToInternet
            || (fehler as? JellyfinError)?.urlFehlercode == .notConnectedToInternet {
            return String(localized: "Der Server war nicht erreichbar. Hat Swiftly Music die Erlaubnis, Geräte im heimischen Netz zu suchen? Sie steht in den Einstellungen unter „Swiftly Music · Lokales Netzwerk“.")
        }
        return Fehlertext.lesbar(fehler)
    }

    /// Zurück zur Adresse.
    func andererServer() {
        withAnimation(Musikstil.einblenden) {
            erkannt = nil
            fehler = nil
            passwort = ""
            bekannte = []
            bilder = [:]
        }
        jellyfin = nil
    }

    // MARK: Anmelden

    func anmelden(_ modell: Musikmodell) async {
        guard let erkannt, !benutzer.isEmpty, !arbeitet else { return }
        fehler = nil
        arbeitet = true
        defer { arbeitet = false }
        do {
            switch erkannt.art {
            case .jellyfin:
                guard let jellyfin else { return }
                let sitzung = try await jellyfin.authenticate(username: benutzer, password: passwort)
                await fertig(jellyfin: jellyfin, sitzung: sitzung, erkannt: erkannt, modell: modell)
            case .subsonic:
                let (client, server) = try await SubsonicClient.anmelden(
                    server: erkannt.adresse, benutzer: benutzer, passwort: passwort
                ) { anfrage in try await URLSession.ortsnetzfaehig.data(for: anfrage) }
                let zugang = GespeicherterZugang(serverart: .subsonic, subsonic: client.geltenderZugang,
                                                 servername: erkannt.name,
                                                 serverbeschreibung: server.anzeigename)
                // Eine neue Quelle mit der Sitzung fürs Netz im Heim, nicht mit
                // der Attrappe der Anmeldung.
                modell.angemeldet(SubsonicQuelle(client: SubsonicClient(zugang: client.geltenderZugang,
                                                                        sitzung: .ortsnetzfaehig)),
                                  zugang: zugang)
            }
            passwort = ""
        } catch {
            fehler = Fehlertext.lesbar(error)
        }
    }

    private func fertig(jellyfin: JellyfinClient, sitzung: Session, erkannt: Erkannt,
                        modell: Musikmodell) async {
        let zugang = GespeicherterZugang(
            serverart: .jellyfin,
            jellyfin: .init(server: erkannt.adresse, token: sitzung.accessToken,
                            benutzerID: sitzung.userID, benutzername: sitzung.userName),
            servername: erkannt.name, serverbeschreibung: erkannt.beschreibung)
        modell.angemeldet(JellyfinQuelle(client: jellyfin, sitzung: sitzung, geraeteID: Geraetekennung.wert),
                          zugang: zugang)
    }

    // MARK: Quick Connect

    func quickConnectStarten() async throws -> Anmeldecode {
        guard let jellyfin else { throw JellyfinError.notAuthenticated }
        return try await jellyfin.quickConnectStarten()
    }

    func quickConnectWarten(_ vorgang: Anmeldecode) -> AsyncStream<Quickconnectwarten.Ereignis>? {
        jellyfin?.quickConnectWarten(vorgang)
    }

    func anmeldenMitQuickConnect(_ vorgang: Anmeldecode, modell: Musikmodell) async {
        guard let jellyfin, let erkannt else { return }
        arbeitet = true
        defer { arbeitet = false }
        do {
            let sitzung = try await jellyfin.anmeldenMitQuickConnect(vorgang)
            await fertig(jellyfin: jellyfin, sitzung: sitzung, erkannt: erkannt, modell: modell)
        } catch {
            fehler = Fehlertext.lesbar(error)
        }
    }
}

// MARK: - Seiten

struct Anmeldeseite: View {
    @Environment(Musikmodell.self) private var modell
    @State private var anmeldung = Anmeldemodell()
    @State private var quickConnectOffen = false

    var body: some View {
        ZStack {
            Stil.grund.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    if let erkannt = anmeldung.erkannt {
                        anmeldeteil(erkannt)
                            .transition(.opacity)
                    } else {
                        adressteil.transition(.opacity)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .fullScreenCover(isPresented: $quickConnectOffen) {
            QuickConnectSeite(anmeldung: anmeldung)
        }
    }

    // Die Adresse — wie `ConnectView`.
    private var adressteil: some View {
        VStack(spacing: 0) {
            Image("WortmarkeGross")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 40)
                .padding(.top, 172)
                .accessibilityLabel(Text(verbatim: "Swiftly Music"))

            Text("Wo läuft dein Musikserver?")
                .font(.system(size: 15))
                .foregroundStyle(Stil.schriftLeise)
                .padding(.top, 44)

            Adressfeld(anmeldung: anmeldung)
                .padding(.top, 18)

            Anmeldefehler(text: anmeldung.fehler ?? modell.anmeldehinweis)
        }
    }

    // Name und Passwort — wie `LoginView`.
    private func anmeldeteil(_ erkannt: Anmeldemodell.Erkannt) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Serverkopf(erkannt: erkannt, titel: true)
                .padding(.top, 48)

            Anmeldefelder(anmeldung: anmeldung, quickConnectOffen: $quickConnectOffen)

            Button("Anderer Server") { anmeldung.andererServer() }
                .buttonStyle(Druckzeile())
                .font(Musikstil.angabe)
                .foregroundStyle(Stil.schriftSehrLeise)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
        }
    }
}

/// **Ein weiteres Konto** — von der Kontoseite hereingeschoben, wie
/// `ServerAufnahmeView` im Player: oben der Rückweg mit dem Seitennamen,
/// darunter ein Satz, dann Adresse, Name und Passwort. Auf demselben Server
/// oder einem anderen. Ist es angemeldet, gilt es sofort, und die Seite geht.
struct Kontoaufnahme: View {
    @Environment(Musikmodell.self) private var modell
    @Environment(\.dismiss) private var zurueck
    @State private var anmeldung = Anmeldemodell()
    @State private var quickConnectOffen = false

    var body: some View {
        VStack(spacing: 0) {
            Unterseitenkopf(titel: Text(verbatim: anmeldung.erkannt?.name ?? String(localized: "Konto hinzufügen")))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let erkannt = anmeldung.erkannt {
                        VStack(alignment: .leading, spacing: 0) {
                            Serverkopf(erkannt: erkannt, titel: false)
                                .padding(.top, 8)
                            Anmeldefelder(anmeldung: anmeldung, quickConnectOffen: $quickConnectOffen)
                            Button("Anderer Server") { anmeldung.andererServer() }
                                .buttonStyle(Druckzeile())
                                .font(Musikstil.angabe)
                                .foregroundStyle(Stil.schriftSehrLeise)
                                .frame(minHeight: 44)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 28)
                        }
                        .transition(.opacity)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Die Adresse deines Musikservers. Du bleibst bei allen Konten angemeldet und wechselst auf der Kontoseite.")
                                .font(.system(size: 15))
                                .lineSpacing(3)
                                .foregroundStyle(Stil.schriftLeise)
                                .padding(.top, 8)
                            Adressfeld(anmeldung: anmeldung)
                                .padding(.top, 28)
                            Anmeldefehler(text: anmeldung.fehler)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Stil.grund)
        .toolbar(.hidden, for: .navigationBar)
        .background(WischZurueck())
        .fullScreenCover(isPresented: $quickConnectOffen) {
            QuickConnectSeite(anmeldung: anmeldung)
        }
        // Angemeldet: das neue Konto gilt, die Seite hat ihren Zweck erfüllt.
        .onChange(of: modell.quelle?.konto) { _, _ in zurueck() }
    }
}

/// Das Feld für die Adresse und „Verbinden".
private struct Adressfeld: View {
    let anmeldung: Anmeldemodell

    var body: some View {
        @Bindable var anmeldung = anmeldung
        VStack(spacing: 0) {
            Eingabefeld(text: $anmeldung.adresse, symbol: "globe", platzhalter: "musik.beispiel.de",
                        tastatur: .adresse) { Task { await anmeldung.verbinden() } }

            Text("Jellyfin oder Navidrome, die App erkennt es selbst. https:// kannst du weglassen.")
                .font(Musikstil.angabe)
                .foregroundStyle(Stil.schriftSehrLeise)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 9)
                .padding(.leading, 2)

            Button(anmeldung.arbeitet ? "Verbinden…" : "Verbinden") {
                Task { await anmeldung.verbinden() }
            }
            .buttonStyle(HauptknopfStil())
            .padding(.top, 22)
            .disabled(anmeldung.adresse.isEmpty || anmeldung.arbeitet)
            .opacity(anmeldung.adresse.isEmpty ? 0.4 : 1)
        }
    }
}

/// „Verbunden · Jellyfin 10.10.3" und, an der Wurzel, der Servername groß.
private struct Serverkopf: View {
    let erkannt: Anmeldemodell.Erkannt
    let titel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(Stil.akzent).frame(width: 7, height: 7)
                Text("Verbunden · \(erkannt.beschreibung)")
                    .font(Musikstil.angabe)
                    .foregroundStyle(Stil.schriftSehrLeise)
            }
            if titel {
                Text(verbatim: erkannt.name)
                    .font(Musikstil.seitentitel)
                    .tracking(Musikstil.sperrungSeitentitel)
                    .foregroundStyle(Stil.schrift)
                    .lineLimit(2)
            }
        }
    }
}

/// **Wer hört?, Name, Passwort, Anmelden und Quick Connect** — an der
/// Wurzel und beim Hinzufügen dieselben.
private struct Anmeldefelder: View {
    let anmeldung: Anmeldemodell
    @Binding var quickConnectOffen: Bool
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        @Bindable var anmeldung = anmeldung
        VStack(alignment: .leading, spacing: 0) {
            if !anmeldung.bekannte.isEmpty { wahl }

            VStack(spacing: 10) {
                Eingabefeld(text: $anmeldung.benutzer, symbol: "person", platzhalter: "Benutzername")
                Eingabefeld(text: $anmeldung.passwort, symbol: "lock", platzhalter: "Passwort",
                            geheim: true) { Task { await anmeldung.anmelden(modell) } }
                Button(anmeldung.arbeitet ? "Anmelden…" : "Anmelden") {
                    Task { await anmeldung.anmelden(modell) }
                }
                .buttonStyle(HauptknopfStil())
                .padding(.top, 10)
                .disabled(anmeldung.benutzer.isEmpty || anmeldung.arbeitet)
                .opacity(anmeldung.benutzer.isEmpty ? 0.4 : 1)
                Anmeldefehler(text: anmeldung.fehler)
            }
            .padding(.top, 28)

            if anmeldung.quickConnect {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        Rectangle().fill(Stil.linie).frame(height: 1)
                        Text("oder").font(Musikstil.angabe).foregroundStyle(Stil.schriftSehrLeise)
                        Rectangle().fill(Stil.linie).frame(height: 1)
                    }
                    Button { quickConnectOffen = true } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "rectangle.and.text.magnifyingglass")
                            Text("Mit Quick Connect anmelden")
                        }
                    }
                    .buttonStyle(NebenknopfStil(akzent: true))
                }
                .padding(.top, 26)
            }
        }
        // Die Maske steht schon; wer hier hört, kommt dazu (`LoginView` im
        // Player). Eine neue Adresse ist eine neue Maske und fragt neu.
        .task(id: anmeldung.erkannt?.adresse) { await anmeldung.bekannteLaden() }
    }

    /// **Wer hört?** — die öffentlichen Benutzer des Servers als Zeichen,
    /// wie „Wer schaut?" im Player (`LoginView.wahl`). Ein Tipp setzt den
    /// Namen; der Server kennt ihn schon, abtippen muss ihn niemand.
    private var wahl: some View {
        VStack(alignment: .leading, spacing: 0) {
            Gruppentitel(text: String(localized: "Wer hört?"))
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(anmeldung.bekannte) { person in
                        Button { anmeldung.benutzer = person.name } label: {
                            Kontozeichen(name: person.name, bild: anmeldung.bilder[person.id],
                                         gewaehlt: anmeldung.benutzer == person.name)
                        }
                        .buttonStyle(Druckzeile())
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 22)
    }
}

/// **Ein bekanntes Konto auf der Anmeldeseite** — `Kontozeichen` im Player:
/// Profilzeichen 60, gewählt mit weißem Ring 2 (Rangfolge unter
/// Geschwistern trägt nie der Akzent), darunter der Name 13 Medium.
private struct Kontozeichen: View {
    let name: String
    let bild: URL?
    let gewaehlt: Bool

    var body: some View {
        VStack(spacing: 8) {
            Profilzeichen(name: name, bild: bild, groesse: 60)
                .overlay {
                    if gewaehlt { Circle().strokeBorder(Stil.schrift, lineWidth: 2) }
                }
            Text(verbatim: name)
                .font(Musikstil.kacheltitel)
                .foregroundStyle(gewaehlt ? Stil.schrift : Stil.schriftLeise)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
        .frame(width: 84)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(gewaehlt ? [.isButton, .isSelected] : .isButton)
    }
}

/// Ein Fehler unter den Feldern, 12 in `fehler`, mittig.
private struct Anmeldefehler: View {
    let text: String?

    var body: some View {
        if let text {
            Text(verbatim: text)
                .font(Musikstil.angabe)
                .foregroundStyle(Stil.fehler)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
    }
}

/// **Quick Connect**: der Code, das Warten, die Anleitung — wie
/// `QuickConnectAnmeldung` in `Sources/Shared`, mit derselben Frist und
/// derselben Wartelogik aus JellyfinKit (`Quickconnectwarten`).
///
/// **Nachgebaut, nicht geteilt:** `QuickConnectAnmeldung` hängt am
/// `AppModel` des Players und übersetzt ohne ihn nicht. Aufbau, Maße und
/// Wortlaut sind dieselben; die Logik liegt ohnehin im Paket.
struct QuickConnectSeite: View {
    let anmeldung: Anmeldemodell
    @Environment(Musikmodell.self) private var modell
    @Environment(\.dismiss) private var schliessen

    @State private var vorgang: Anmeldecode?
    @State private var fehler: String?
    @State private var rest = Quickconnectfrist.sekunden
    @State private var runde = 0

    var body: some View {
        ZStack(alignment: .top) {
            Stil.grund.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Derselbe Kopf wie jede Unterseite, wie im Player
                    // (`QuickConnectAnmeldung`): Rückweg und Titel.
                    Unterseitenkopf(titel: Text("Quick Connect"))
                        .padding(.horizontal, -Musikstil.rand)

                    Text("Gib diesen Code in Jellyfin auf einem Gerät ein, an dem du schon angemeldet bist.")
                        .font(.system(size: 15))
                        .foregroundStyle(Stil.schriftLeise)
                        .lineSpacing(3)
                        .padding(.top, 10)

                    if let vorgang {
                        codefelder(vorgang.code)
                        HStack(spacing: 9) {
                            Circle().fill(Stil.akzent).frame(width: 8, height: 8)
                            Text("Warte auf Freigabe · noch \(rest / 60):\(String(format: "%02d", rest % 60))")
                                .font(Musikstil.angabe)
                                .foregroundStyle(Stil.schriftLeise)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 22)
                    } else if let fehler {
                        Text(verbatim: fehler)
                            .font(.system(size: 15))
                            .foregroundStyle(Stil.fehler)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        Ladefeld(ecke: 12).frame(height: 60).frame(maxWidth: 260)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle().fill(Stil.linie).frame(height: 1)
                        Gruppentitel(text: String(localized: "So gehts")).padding(.top, 18)
                        schritt(1, "Jellyfin im Browser öffnen und anmelden")
                        schritt(2, "Oben rechts aufs Profil, dann Quick Connect")
                        schritt(3, "Code eingeben, dann geht es hier von selbst weiter")
                    }
                    .padding(.top, 38)
                }
                .padding(.horizontal, Musikstil.rand)
                .padding(.bottom, 40)
            }
            .contentMargins(.top, 8, for: .scrollContent)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Neuen Code holen") { runde += 1 }
                .buttonStyle(NebenknopfStil())
                .padding(.horizontal, Musikstil.rand)
                .padding(.bottom, 24)
        }
        .task(id: runde) { await warten() }
    }

    /// Ein Code, dann warten, bis er freigegeben ist oder die Frist um.
    private func warten() async {
        vorgang = nil
        fehler = nil
        rest = Quickconnectfrist.sekunden
        do {
            let neu = try await anmeldung.quickConnectStarten()
            vorgang = neu
            guard let strom = anmeldung.quickConnectWarten(neu) else { return }
            for await ereignis in strom {
                switch ereignis {
                case let .rest(s):
                    rest = s
                case .freigegeben:
                    await anmeldung.anmeldenMitQuickConnect(neu, modell: modell)
                    schliessen()
                    return
                case let .ende(letzte):
                    vorgang = nil
                    fehler = Quickconnectfrist.schlusstext(letzte: letzte)
                    return
                }
            }
        } catch {
            fehler = Fehlertext.lesbar(error)
        }
    }

    private func codefelder(_ code: String) -> some View {
        let zeichen = Array(code)
        return HStack(spacing: 8) {
            ForEach(Array(zeichen.enumerated()), id: \.offset) { paar in
                if paar.offset == zeichen.count / 2 { Color.clear.frame(width: 6) }
                Text(verbatim: String(paar.element))
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Stil.schrift)
                    .frame(width: 46, height: 60)
                    .background(Stil.flaeche, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: code))
    }

    private func schritt(_ zahl: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(zahl)")
                .font(Musikstil.angabe)
                .foregroundStyle(Stil.schriftSehrLeise)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(Musikstil.angabe)
                .foregroundStyle(Stil.schriftLeise)
                .lineSpacing(2)
        }
        .padding(.top, 10)
    }
}

/// **Das Eingabefeld** aus `Stil.swift` (`Eingabefeld`): 48 hoch, Ecke 12,
/// `flaeche`, Rand 12 % — beim Tippen 2 Punkt.
struct Eingabefeld: View {
    @Binding var text: String
    let symbol: String
    var platzhalter: LocalizedStringKey = ""
    var geheim = false
    var tastatur: Weise = .normal
    var abschluss: () -> Void = {}

    enum Weise { case normal, adresse }

    @State private var zeigt = false
    @FocusState private var amTippen: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(Stil.schriftSehrLeise)
                .frame(width: 20)
                .accessibilityHidden(true)

            Group {
                if geheim, !zeigt {
                    SecureField("", text: $text, prompt: Text(platzhalter).foregroundColor(Stil.schriftSehrLeise))
                } else {
                    TextField("", text: $text, prompt: Text(platzhalter).foregroundColor(Stil.schriftSehrLeise))
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(Stil.schrift)
            .tint(Stil.akzent)
            .focused($amTippen)
            .onSubmit(abschluss)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(tastatur == .adresse ? .URL : .default)
            .textContentType(geheim ? .password : (tastatur == .adresse ? .URL : .username))
            .submitLabel(.go)

            if geheim, !text.isEmpty {
                Button { zeigt.toggle() } label: {
                    Image(systemName: zeigt ? "eye.slash" : "eye")
                        .font(.system(size: 15))
                        .foregroundStyle(Stil.schriftSehrLeise)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(Druckknopf())
                .accessibilityLabel(zeigt ? Text("Passwort verbergen") : Text("Passwort zeigen"))
                .padding(.trailing, -13)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Stil.flaeche, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Stil.rand, lineWidth: amTippen ? 2 : 1)
        }
        .animation(.easeOut(duration: 0.10), value: amTippen)
    }
}
