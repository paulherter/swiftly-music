import MusikKit
import SwiftUI

// MARK: - Maße

extension Musikstil {
    /// **Eine Ecke für jede Hervorhebung einer Zeile** — die laufende und die
    /// gedrückte, in Liedliste, „Oft gehört", Suche und Bibliothek: die Ecke
    /// der Pille unten (`eckeMini`, 24.09.: „Es muss immer dieselbe
    /// sein"). Vorher trug das laufende Lied Ecke 10 und die gedrückte
    /// Zeile gar keine.
    static let eckeZeile: CGFloat = Musikstil.eckeMini
}

/// **Der Hauptknopf einer Seite in Seitenfarbe** — wie `HauptknopfStil`
/// (Musikstil.swift), aber mit der Ecke der Zeile (``Musikstil/eckeZeile``)
/// statt `eckeKnopf`: „Abspielen" auf Album-, Playlist-, Künstler- und
/// Hörbuchseite stand als einziger Knopf darauf eckiger da als Pille und
/// Zeilen (24.09.: „darf vom Video-Player abweichen, es ist ein
/// Musikplayer"). Player und Minispieler bleiben bei `HauptknopfStil`.
struct SeitenHauptknopfStil: ButtonStyle {
    @Environment(\.isEnabled) private var freigegeben

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(freigegeben ? Stil.aufAkzent : Stil.schriftSehrLeise)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(freigegeben ? Color.white.opacity(configuration.isPressed ? 0.75 : 1) : Stil.flaeche,
                        in: RoundedRectangle(cornerRadius: Musikstil.eckeZeile, style: .continuous))
            .scaleEffect(configuration.isPressed && !Musikstil.bewegungReduziert ? 0.97 : 1)
            .animation(Musikstil.druckkurve(configuration.isPressed), value: configuration.isPressed)
    }
}

// MARK: - Die Fläche einer Zeile

/// **Weiß, durchscheinend** statt `erhoeht`: auf einer Seite in der Farbe
/// ihrer Hülle kommt die Farbe durch, auf `grund` sieht es aus wie bisher.
/// Der Kontrast darauf ist in `SeitenfarbeTests` gerechnet.
struct Zeilenflaeche: View {
    var deckung = Seitenfarbe.laufend

    var body: some View {
        RoundedRectangle(cornerRadius: Musikstil.eckeZeile, style: .continuous)
            .fill(Color.white.opacity(deckung))
    }
}

/// **Der Druck auf einer Zeile** — wie `Druckzeile`, aber mit der Ecke und
/// dem Weiß der laufenden Zeile, damit gedrückt und laufend gleich aussehen.
/// `links`/`rechts` rücken die Fläche ein (positiv) oder über den Rand des
/// Knopfs hinaus (negativ): eine Zeile, die bis an den Schirmrand reicht,
/// bekommt 8 Einzug — so steht die Fläche wie in der Liedliste 10 Punkt
/// neben dem Text.
struct Zeilendruck: ButtonStyle {
    var links: CGFloat = 0
    var rechts: CGFloat = 0

    /// Für Zeilen, die bis an den Schirmrand reichen und den Rand innen tragen.
    static let randbreit = Zeilendruck(links: Musikstil.rand - 10, rechts: Musikstil.rand - 10)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Zeilenflaeche(deckung: configuration.isPressed ? Seitenfarbe.gedrueckt : 0)
                    .padding(.leading, links)
                    .padding(.trailing, rechts)
            }
            .animation(Musikstil.druckkurve(configuration.isPressed), value: configuration.isPressed)
    }
}

// MARK: - Die Seite in der Farbe ihrer Hülle

/// **Hinter der ganzen Seite die Hülle, groß und verschwommen** — dieselbe
/// Machart wie der Hintergrund im Player (24.09.: „dass die ganze
/// Seite so eine Farbe davon hat").
///
/// - Das Bild kommt fertig aus `Blattbilder` (je Hülle einmal gerechnet und
///   gemerkt, 96 Punkt, verschwommen, satt, nirgends heller als
///   Leuchtdichte 0,09). Beim Scrollen wird nichts verwischt, nur
///   verschoben.
/// - Darüber ein Schleier aus `grund` nach ``Seitenfarbe/schleier(bei:textAb:hoehe:)``:
///   oben dünn, ab dem Titel so dicht, dass auch `schriftSehrLeise` 4,5 : 1
///   hat, und über eine Bildschirmhöhe in `grund` aus.
/// - Der Schleier geht 1 : 1 mit dem Inhalt, das Bild mit 70 % —
///   eine ruhige Parallaxe. Ohne Bewegung (Bedienungshilfen) gehen beide 1 : 1.
/// - Zieht man oben über den Anfang, dehnt sich das Bild wie vorher das
///   Heldbild — und der Schleier darüber bleibt an seiner Oberkante stehen
///   (``Seitenfarbe/schleieroberkante(versatz:)``), statt sich mit dem
///   Überzug mitzuziehen: sonst blieb genau dort eine harte, graue Kante
///   stehen, unter der der Verlauf sichtbar wurde (25.09.).
/// - **Unter der Detailleiste dieselbe Farbe**: ist der Kopf weggescrollt,
///   deckte die Leiste vorher mit `grund` — ein grauer Balken über einer
///   farbigen Seite. Jetzt liegt dort ein Ausschnitt desselben Hintergrunds,
///   an derselben Stelle des Schirms, und blendet mit der Deckung der Leiste
///   ein (``Scrolldeckung/deckung(versatz:heldhoehe:)``). Die Leiste trägt
///   dafür `seitenfarbe: true`.
struct Seitenhintergrund: ViewModifier {
    enum Quelle: Equatable {
        /// Die Hülle der Sammlung — dieselbe Adresse wie die Hülle im Kopf,
        /// dann liegt das Bild schon im `Bildlager`.
        case huelle(URL?)
        /// Die Lieblingssongs haben keine Hülle, sondern ihre eigene Glut.
        case lieblinge
    }

    let quelle: Quelle
    /// Wo die erste Schrift stehen kann, in Punkt vom oberen Rand.
    let textAb: CGFloat
    /// Die Höhe des Kopfs, wenn eine Detailleiste darüber liegt.
    let heldhoehe: CGFloat?
    /// **Die Farbe der Seite**, für die Detailleiste (``Titelleistenglas``) —
    /// eine leere Bindung, wer sie nicht braucht.
    @Binding var farbton: Seitenfarbe.Seitenton?
    @State private var versatz: CGFloat = 0
    @State private var verschwommen: Image?
    /// **Wie weit der Kopf gerade überzogen ist** — in Echtzeit über
    /// ``Seitenzugmesser`` gemeldet, nicht aus `versatz`: der kommt aus dem
    /// Zustand einen Bildaufbau zu spät und riss oben eine gerade, graue
    /// Kante auf, wo das Bild noch nicht mitgewachsen war (24.09.; wie
    /// `Heldbild` in `Stil.swift`, das aus demselben Grund `GeometryReader`
    /// statt Zustand misst).
    @State private var ueberzug: CGFloat = 0

    /// Die Leiste: 44 Ziel, 2 höher, 4 darunter (`Detailleiste`), unter der
    /// Statusleiste.
    private static let leiste: CGFloat = 46

    /// **Zusätzliche Unschärfe über dem Seitenhintergrund** (25.09.:
    /// „man erkennt das Cover fast, Personen sichtbar — vorher war besser").
    /// `Blattbilder` liefert dasselbe kleine, verwischte Bild wie im Player —
    /// dort füllt es nur das Heldbild, hier die ganze, randlose Seite, wo
    /// große Flächen Konturen wieder erkennbar machen. Ein eigener
    /// Weichzeichner nur für die Seite löst sie auf, ohne `Blattbilder`
    /// selbst anzutasten (das bleibt Sache des Players).
    private static let zusatzUnschaerfe: CGFloat = 40

    init(quelle: Quelle, textAb: CGFloat, heldhoehe: CGFloat?, farbton: Binding<Seitenfarbe.Seitenton?>) {
        self.quelle = quelle
        self.textAb = textAb
        self.heldhoehe = heldhoehe
        _farbton = farbton
        if case let .huelle(adresse?) = quelle {
            _verschwommen = State(initialValue: Blattbilder.geteilt.fertig(adresse))
        }
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { g in
                g.contentOffset.y + g.contentInsets.top
            } action: { _, neu in
                // Ist die Farbe weggescrollt, ändert sich nichts mehr.
                let wert = min(neu, 3000)
                if abs(wert - versatz) >= 0.5 { versatz = wert }
            }
            .onPreferenceChange(UeberzugSchluessel.self) { neu in
                if abs(neu - ueberzug) >= 0.5 { ueberzug = neu }
            }
            .background {
                GeometryReader { g in
                    flaeche(g.size)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .overlay(alignment: .top) {
                if let heldhoehe {
                    let deckung = Scrolldeckung.deckung(versatz: versatz, heldhoehe: heldhoehe)
                    if deckung > 0 {
                        GeometryReader { g in
                            let oben = g.safeAreaInsets.top
                            GeometryReader { voll in
                                flaeche(voll.size)
                            }
                            .ignoresSafeArea()
                            .mask(alignment: .top) {
                                Rectangle().frame(height: oben + Self.leiste)
                                    .ignoresSafeArea(edges: .top)
                            }
                        }
                        .opacity(deckung)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
            }
            .task(id: quelle) {
                assert(Blattbilder.hoechsteLeuchtdichte <= Seitenfarbe.hoechsteLeuchtdichte,
                       "Der Schleier ist für ein dunkleres Bild gerechnet")
                guard case let .huelle(adresse?) = quelle else {
                    verschwommen = nil
                    farbton = nil
                    return
                }
                async let bild = Blattbilder.geteilt.laden(adresse)
                async let ton = Seitentoene.geteilt.laden(adresse)
                let (neuBild, neuTon) = await (bild, ton)
                guard !Task.isCancelled else { return }
                withAnimation(Musikstil.bewegungReduziert ? nil : .easeInOut(duration: 0.4)) { verschwommen = neuBild }
                farbton = neuTon
            }
    }

    private func flaeche(_ groesse: CGSize) -> some View {
        let s = versatz
        let mitlauf = Musikstil.bewegungReduziert ? 1 : CGFloat(Seitenfarbe.mitlauf)
        // Nach unten gezogen: das Bild bleibt oben stehen und wird länger —
        // um `ueberzug`, in Echtzeit gemessen (siehe oben).
        let bildhoehe = groesse.height + ueberzug
        let bildversatz = s > 0 ? -s * mitlauf : 0
        return ZStack(alignment: .top) {
            Stil.grund
            if bildversatz > -bildhoehe {
                Group {
                    switch quelle {
                    case .lieblinge:
                        Lieblingsglut()
                    case .huelle:
                        if let verschwommen {
                            ZStack {
                                verschwommen
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fill)
                                    .blur(radius: Self.zusatzUnschaerfe)
                                // **Die Tönung blasser Cover**: der
                                // lebendigste Ton statt eines toten Grauwerts
                                // (24.09., ``Seitenfarbe.seitenton``).
                                // Bei einem kräftigen Cover ist die Deckung 0.
                                if let farbton, farbton.deckung > 0 {
                                    Color(farbton.farbe).opacity(farbton.deckung)
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                }
                .frame(width: groesse.width, height: bildhoehe)
                .clipped()
                .offset(y: bildversatz)
            }
            VStack(spacing: 0) {
                Schleier(hoehe: groesse.height, textAb: textAb)
                    .frame(height: groesse.height)
                // Unter dem Ausklang ist nur noch Grund — das langsamere Bild
                // reicht dort noch hin.
                Stil.grund
            }
            .frame(height: groesse.height * 2, alignment: .top)
            // Nie ueber die Ruhelage hinaus nach unten (``Seitenfarbe/
            // schleieroberkante(versatz:)``) — sonst zieht sich diese Ebene
            // beim Ueberziehen am oberen Rand mit und reisst eine harte
            // Kante auf, wo das Bild schon bis y 0 reicht (25.09.).
            .offset(y: Seitenfarbe.schleieroberkante(versatz: s))
        }
        .frame(width: groesse.width, height: groesse.height, alignment: .top)
        .clipped()
    }
}

extension View {
    /// Die Seite in der Farbe ihrer Hülle (``Seitenhintergrund``) — an die
    /// `ScrollView` der Seite, statt `.background(Stil.grund)`. `farbton`
    /// füllt sich, sobald die Farbe da ist — für die Detailleiste
    /// (``Titelleistenglas``); ohne Bedarf einfach weglassen.
    func seitenfarbe(_ quelle: Seitenhintergrund.Quelle, textAb: CGFloat, heldhoehe: CGFloat? = nil,
                      farbton: Binding<Seitenfarbe.Seitenton?> = .constant(nil)) -> some View {
        modifier(Seitenhintergrund(quelle: quelle, textAb: textAb, heldhoehe: heldhoehe, farbton: farbton))
    }
}

/// **Meldet, wie weit der Kopf der Seite gerade überzogen ist** — für
/// ``Seitenhintergrund``, das sein Bild sonst nur aus dem Scrollversatz im
/// Zustand dehnt (siehe dort). Als erstes Element im Inhalt der `ScrollView`,
/// ohne eigene Höhe — wie `held` in `Kuenstlerseite.swift`, nur ohne eigenes
/// Bild, für Seiten ohne Heldbild (Albumseite).
struct Seitenzugmesser: View {
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: UeberzugSchluessel.self, value: max(0, g.frame(in: .scrollView).minY))
        }
        .frame(height: 0)
        .accessibilityHidden(true)
    }
}

private struct UeberzugSchluessel: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// **Der Ton je Hülle, einmal gerechnet** (``Seitenfarbe/seitenton(rgba:)``)
/// — eigens für die Seiten: dieselben Bildpunkte wie `Blattbilder`, aber ein
/// eigener, kleiner Griff hinein, damit die Wahl der Ansicht den
/// Player-Hintergrund nicht berührt (24.09.).
@MainActor
final class Seitentoene {
    static let geteilt = Seitentoene()
    private var gemerkt: [String: Seitenfarbe.Seitenton] = [:]
    private var reihe: [String] = []

    func fertig(_ url: URL) -> Seitenfarbe.Seitenton? { gemerkt[Bildlager.schluessel(url)] }

    func laden(_ url: URL) async -> Seitenfarbe.Seitenton? {
        let schluessel = Bildlager.schluessel(url)
        if let da = gemerkt[schluessel] { return da }
        guard let roh = await Bildlager.geteilt.rohbildLaden(url) else { return nil }
        let ton = await Task.detached(priority: .utility) { Self.abtasten(roh) }.value
        gemerkt[schluessel] = ton
        reihe.append(schluessel)
        if reihe.count > 12 { gemerkt.removeValue(forKey: reihe.removeFirst()) }
        return ton
    }

    /// Klein herunterrechnen und die Bildpunkte lesen — kein Verwischen
    /// nötig, es zählt nur die Verteilung der Töne.
    nonisolated private static func abtasten(_ bild: CGImage) -> Seitenfarbe.Seitenton {
        let n = 24
        var punkte = [UInt8](repeating: 0, count: n * n * 4)
        guard let raum = CGColorSpace(name: CGColorSpace.sRGB),
              let kontext = CGContext(data: &punkte, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: raum, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Seitenfarbe.seitenton(rgba: []) }
        kontext.interpolationQuality = .medium
        kontext.draw(bild, in: CGRect(x: 0, y: 0, width: n, height: n))
        return Seitenfarbe.seitenton(rgba: punkte)
    }
}

/// **Der Schleier** als Verlauf, einmal je Höhe gerechnet: 25 Stufen aus
/// ``Seitenfarbe/schleier(bei:textAb:hoehe:)``, dazu die Punkte, an denen
/// sich die Kurve ändert. Eine eigene Ansicht, damit er beim Scrollen nicht
/// neu entsteht — es ändert sich nur der Versatz außen.
private struct Schleier: View, Equatable {
    let hoehe: CGFloat
    let textAb: CGFloat

    var body: some View {
        let h = Double(max(hoehe, 1))
        let t = Double(textAb)
        var punkte = (0 ... 24).map { h * Double($0) / 24 }
        punkte += [t - Seitenfarbe.anstieg, t, max(t, h * Seitenfarbe.ausklangAb)].filter { $0 > 0 && $0 < h }
        let stufen = punkte.sorted().map { y in
            Gradient.Stop(color: Stil.grund.opacity(Seitenfarbe.schleier(bei: y, textAb: t, hoehe: h)),
                          location: y / h)
        }
        return LinearGradient(stops: stufen, startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Lieblingssongs

extension Color {
    init(_ f: Farbwert) {
        self.init(red: f.rot, green: f.gruen, blue: f.blau)
    }
}

/// **Der Hintergrund der Lieblingssongs**: kein Bild des obersten Liedes
/// mehr (24.09.: „dadurch sieht die ganze Playlist traurig aus"),
/// sondern eine Glut im Blaugrün des Akzents oben rechts, ein bläulicher
/// Schein links, dazwischen tiefes Blaugrün. Jeder Ton liegt unter
/// Leuchtdichte 0,09 wie das verschwommene Bild — derselbe Schleier hält die
/// Schrift lesbar.
private struct Lieblingsglut: View {
    var body: some View {
        GeometryReader { g in
            ZStack {
                Color(Seitenfarbe.glutgrund)
                RadialGradient(colors: [Color(Seitenfarbe.schein), Color(Seitenfarbe.schein).opacity(0)],
                               center: UnitPoint(x: 0.08, y: 0.40),
                               startRadius: 0, endRadius: max(g.size.width * 0.85, 1))
                RadialGradient(colors: [Color(Seitenfarbe.glut), Color(Seitenfarbe.glut).opacity(0)],
                               center: UnitPoint(x: 0.80, y: 0.12),
                               startRadius: 0, endRadius: max(g.size.width * 1.05, 1))
            }
        }
    }
}

/// **Die Kachel der Lieblingssongs** — im Kopf der Seite (132) und in der
/// angehefteten Zeile der Bibliothek (52): ein weißes Herz auf einem
/// Verlauf aus `akzent` in tiefes Blaugrün, dahinter ein heller Schein.
///
/// **Der Akzent als Marke.** BRAND.md hält ihn sonst für Zustand zurück
/// (laufend, geladen, gewählt). Die Lieblingssongs sind die eine Sammlung,
/// die Swiftly selbst führt und keine Hülle hat — ihre Kachel trägt deshalb
/// die Farbe der App, wie ein Zeichen, nicht wie ein Zustand. Nur hier, nicht
/// auf anderen Kacheln. Kein Glas: der Schein ist ein Verlauf, keine
/// Unschärfe, und kostet beim Scrollen nichts.
struct Lieblingskachel: View {
    var body: some View {
        GeometryReader { g in
            let k = min(g.size.width, g.size.height)
            ZStack {
                LinearGradient(colors: [Color(Seitenfarbe.kachelHell), Color(Seitenfarbe.kachelMitte),
                                        Color(Seitenfarbe.kachelTief)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Stil.akzentHell.opacity(0.55), Stil.akzentHell.opacity(0)],
                               center: UnitPoint(x: 0.5, y: 0.48),
                               startRadius: 0, endRadius: max(k * 0.48, 1))
                Symbolbild(zeichen: .herz, groesse: k * 0.42)
                    .foregroundStyle(.white)
                    .shadow(color: Color(Seitenfarbe.kachelTief).opacity(0.5), radius: k * 0.05, y: k * 0.025)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .accessibilityHidden(true)
    }
}
