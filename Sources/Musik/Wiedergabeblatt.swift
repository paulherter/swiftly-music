import MusikKit
import SwiftUI

/// **Das Wiedergabeblatt** (Übergabe §6, §10): es wächst aus dem
/// Mini-Player heraus, beginnt knapp unter der Statusleiste (y 50 auf den
/// Geräten mit Insel), Ecke 28, Griff 36 × 5 weiß 18 %, 8 von oben.
///
/// **Die Bewegung ist die von cdca8169** — die bisher weichste (24.09.). Der `body` sieht den Anteil einmal, mit dem Zielwert; Rahmen,
/// Versatz und Ecke rechnet er daraus, und SwiftUI führt sie unter der
/// Feder selbst hinüber. Was Bild für Bild vom Anteil abhängt statt nur
/// von seinem Ziel — Deckkraft am Ende des Wegs —, sitzt in einem kleinen
/// animierbaren Baustein (``Anteilsdeckung``).
///
/// **Die Pille wird zum Blatt — dieselbe Fläche, nie eine Überblendung**
/// (24.09.: „wie als würde das Element sich logisch vergrößern";
/// beim Schließen sah man eine Sekunde lang beides). Alles hängt an einer
/// Zahl, ``Blattstand/anteil`` — 0 ist die Pille, 1 das offene Blatt. Die
/// Karte wächst vom Rahmen des Mini-Players auf den des Blatts, die Ecke
/// von 14 auf 28, die Fläche von der Pillenfarbe auf den Grund des Blatts;
/// sie ist zu jedem Zeitpunkt deckend. Hülle, Titel und Künstler fliegen
/// von ihrer Stelle in der Pille an ihre Stelle im Blatt (beide gemessen,
/// dazwischen gemischt). **Alles andere hängt am Blatt**: Griff, Spur,
/// Steuerung und Aktionsreihe fahren mit der Oberkante und laufen beim
/// Schließen unten aus der Karte hinaus, statt stehen zu bleiben oder zu
/// verblassen. Die Leiste fährt im selben Takt nach unten weg und wieder
/// herauf.
///
/// **Bühne und Pille schalten hart um** (``Blattstand/buehne``): die Bühne
/// steht ab dem ersten Bild des Öffnens und bis die Feder des Schließens
/// ganz ausgeschwungen ist; so lange ist die echte Pille weg. Vorher hing
/// die Deckkraft beider am Zielwert — beim Schließen blendete die Bühne
/// über die ganze Feder aus und die Pille ein (gemessen: nach 110 ms
/// beide zu 50 %).
///
/// **Am Finger geht das ganze Blatt mit** — nach unten eins zu eins, nach
/// oben nur ein kleines Stück gegen eine Gummikante. Beim Loslassen läuft
/// alles unter derselben Feder mit dem Schwung des Fingers; Öffnen und
/// Schließen nehmen dieselbe (``Blattphysik/blattfeder(von:nach:schwung:)``).
///
/// Warum nicht `matchedGeometryEffect`: der kennt nur „hier" und „dort",
/// keinen Stand dazwischen, und der Finger braucht jeden Stand dazwischen.
///
/// **Liedtext und Als Nächstes bauen nichts um.** Spur, Zeiten, Steuerung
/// und Aktionsreihe bleiben, wo sie sind. Nur oben wechselt es: die Hülle
/// schrumpft auf 48 nach links oben, Titel und Künstler gleiten daneben —
/// dieselbe Mischung mit einer zweiten Zahl (`kopf`) —, und der Text oder
/// die Liste blendet von leicht unten ein. Zurück genau rückwärts.
///
/// **Bewegung reduzieren**: keine Wege, nur Überblendung — das Blatt steht
/// gleich an seiner Stelle und blendet über die Pille.
struct Wiedergabeblatt: View {
    @Environment(Musikmodell.self) private var modell
    @Environment(Blattstand.self) private var stand
    @State private var ansicht: Blattansicht = .wiedergabe
    /// Liedtext oder Schlange — bleibt stehen, während sie ausblendet.
    @State private var inhalt: Blattansicht = .liedtext
    /// 0: Wiedergabe mit großer Hülle, 1: Liedtext oder Schlange.
    @State private var kopf: CGFloat = 0
    /// Der Wechsel zum Kopf oder zurück ist durch — der `body` sieht von
    /// `kopf` nur den Zielwert, schon im ersten Bild.
    @State private var kopfRuht = true
    @State private var kopfLauf = 0
    /// Wie weit das offene Blatt am Finger hängt: nach unten eins zu eins,
    /// nach oben gegen die Gummikante (negativ).
    @State private var versatz: CGFloat = 0
    @State private var zieht = false
    /// Der Weg der Oberkante von offen bis zur Pille.
    @State private var reise: CGFloat = 600
    /// Die Teile der großen Lage stehen an ihrem Platz — beim Öffnen kommen
    /// sie gestaffelt von leicht unten (``Auftritt``).
    @State private var auftritt = false
    @State private var lagen = Blattlagen()
    /// **Gemessen wird nur in Ruhe.** Der Inhalt fährt mit der Karte, und
    /// solange eine Feder läuft, meldete die Messung die Stellen um den
    /// laufenden Versatz verschoben (gemessen: Hülle bei y −641 statt 167,
    /// die Hülle flog dann von oben statt aus der Pille herein).
    @State private var ruht = true
    /// **Nach jeder Bewegung neu gemessen.** Wechselte das Lied, während
    /// die Feder lief, verwarf `ruht` die neue Lage, und danach meldete sich
    /// niemand mehr — Titel und Künstler flogen beim nächsten Öffnen an die
    /// Stelle des alten Lieds. Eine neue Runde baut die Platzhalter neu, und
    /// sie melden sich in Ruhe noch einmal.
    @State private var messrunde = 0
    @State private var zugstelle = Zugstelle()
    /// **Was zuletzt wirklich gezeigt wurde** — Anteil und Versatz aus dem
    /// letzten Bild (``Praesenz``). Ein Griff in die Feder fängt dort.
    @State private var praesenz = Praesenz()
    /// Der Finger hält das Blatt mitten in einer Feder (``Fang``).
    @State private var fang: Fang?
    /// Wo die Ziehgeste ihre Schwelle überschritten hatte — ab dort folgt
    /// das Blatt, ohne um die Schwelle zu springen.
    @State private var zugAnfang: CGFloat?
    /// Das Blatt ging aus einem Fang auf, die Feder läuft schon.
    @State private var gefangenGeoeffnet = false
    /// Ein Tipp auf Titel oder Künstler hält gerade (``Tippziel``).
    @State private var titelGedrueckt = false
    @State private var zeileGedrueckt = false

    enum Blattansicht { case wiedergabe, liedtext, alsNaechstes }

    /// Der Raum, in dem die Stellen im Blatt gemessen werden.
    nonisolated static let raum = "wiedergabeblatt"

    /// Wie weit der Inhalt beim Schließen hinter der Oberkante zurückbleibt:
    /// in der Pille steht er ganz unter ihrer Unterkante.
    static let nachlauf: CGFloat = 64

    /// Nach oben gibt das offene Blatt höchstens so viel nach — die
    /// Gummikante wird mit dieser Strecke gerechnet, nicht mit dem Weg zur
    /// Pille (24.09.: „viel zu weit nach oben").
    static let gummistrecke: CGFloat = 80

    /// Ab diesem Teil des Wegs kommt das Schwarz über dem Blatt.
    static let schwarzAb: CGFloat = 0.7

    var body: some View {
        // **Den sicheren Bereich lesen, bevor er ignoriert wird.** Stand
        // `.ignoresSafeArea()` am `GeometryReader` selbst, meldete er oben 0 —
        // das Blatt begann bei 24 statt knapp unter der Statusleiste, und der
        // Griff lag hinter der Insel (24.09.: „zu weit oben, Griff fehlt").
        GeometryReader { g in
            let oben = max(g.safeAreaInsets.top - 4, 24)
            let breite = g.size.width
            let gesamt = g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom
            let h = gesamt - oben
            let unten = g.safeAreaInsets.bottom
            let voll = CGRect(x: 0, y: oben, width: breite, height: h)
            let mini = modell.miniRahmen ?? CGRect(x: 8, y: gesamt - unten - 115, width: breite - 16, height: 58)
            ZStack(alignment: .topLeading) {
                if let lied = modell.spieler.aktuell {
                    buehne(lied, voll: voll, mini: mini, unten: unten)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .onChange(of: mini.minY - oben, initial: true) { _, neu in reise = max(neu, 1) }
        }
        // **Die Maße ohne Tastatur.** Stand beim Öffnen noch die Tastatur der
        // Suche, meldete der sichere Bereich unten ihre Höhe — die große
        // Lage baute sich darüber, und Titel und Hülle standen woanders als
        // im Blatt danach.
        .ignoresSafeArea(.keyboard)
        // Auch beim Zugehen: solange die Feder läuft, fängt ein Griff das
        // Blatt (``fangflaeche``).
        .allowsHitTesting((modell.blattOffen || fangbar) && modell.spieler.aktuell != nil)
        .onChange(of: modell.blattOffen) { _, offen in
            if offen {
                if gefangenGeoeffnet {
                    gefangenGeoeffnet = false
                } else {
                    aufgehen()
                }
            } else if stand.anteil > 0, !zieht, fang == nil {
                zugehen(Blattphysik.blattfeder(von: rest, nach: reise, schwung: 0))
            }
        }
        .onChange(of: stand.zug) { _, zug in
            // Vom Mini-Player heraufgezogen: die Pille wächst mit dem Finger.
            guard !modell.blattOffen else { return }
            if let zug {
                buehneZeigen()
                ruht = false
                withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.9)) {
                    stand.anteil = min(max(zug / reise, 0), 1)
                }
            } else if stand.anteil > 0 {
                zugehen(Blattphysik.blattfeder(von: (1 - stand.anteil) * reise, nach: reise, schwung: 0))
            }
        }
        .onChange(of: ansicht) { alt, neu in
            // **Nie sichtbar umbauen** (24.09.: nach Als Nächstes
            // blitzte beim Tipp auf Liedtext die Schlange auf). Kommt der
            // Kopf erst herein, steht darunter noch der alte Inhalt, zu
            // null Deckkraft — getauscht wird dann ohne Blende, bevor er
            // sichtbar wird. Nur zwischen Liedtext und Als Nächstes, bei
            // offenem Kopf, blendet es über.
            if neu != .wiedergabe {
                if alt == .wiedergabe {
                    var ohne = Transaction(animation: nil)
                    ohne.disablesAnimations = true
                    withTransaction(ohne) { inhalt = neu }
                } else {
                    inhalt = neu
                }
            }
            kopfLauf += 1
            let lauf = kopfLauf
            kopfRuht = false
            withAnimation(Musikstil.blattbewegung) { kopf = neu == .wiedergabe ? 0 : 1 } completion: {
                if kopfLauf == lauf { kopfRuht = true }
            }
        }
        .onChange(of: modell.spieler.aktuell == nil) { _, leer in
            if leer, modell.blattOffen { modell.blattOffen = false }
        }
        .onChange(of: ruht) { _, jetzt in
            if jetzt { messrunde += 1 }
        }
    }

    // MARK: Auf und zu

    private func aufgehen() {
        ansicht = .wiedergabe
        kopf = 0
        let schwung = stand.schwung
        stand.schwung = nil
        let losfahren = {
            let rest = self.rest
            let lauf = stand.lauf
            ruht = false
            withAnimation(Blattphysik.blattfeder(von: rest, nach: 0, schwung: schwung ?? 0),
                          completionCriteria: .removed) {
                stand.anteil = 1
                versatz = 0
            } completion: {
                if stand.lauf == lauf { ruht = true }
            }
        }
        buehneZeigen()
        losfahren()
    }

    /// Die Bühne steht ab jetzt, die echte Pille tritt zurück — in einem
    /// Bild, ohne Blende. Die Teile der großen Lage treten gestaffelt auf.
    private func buehneZeigen() {
        stand.lauf += 1
        guard !stand.buehne else { return }
        stand.buehne = true
        auftritt = true
    }

    /// Zurück in die Pille. Erst wenn die Feder ganz ausgeschwungen ist,
    /// steht wieder die echte Pille da — es sei denn, inzwischen ging das
    /// Blatt wieder auf (`lauf`).
    private func zugehen(_ feder: Animation) {
        stand.lauf += 1
        let lauf = stand.lauf
        ruht = false
        withAnimation(feder, completionCriteria: .removed) {
            stand.anteil = 0
            versatz = 0
        } completion: {
            guard stand.lauf == lauf, stand.anteil == 0 else { return }
            stand.buehne = false
            auftritt = false
            ruht = true
        }
    }

    /// Wie weit die Oberkante vom offenen Blatt entfernt ist, in Punkten —
    /// aus Anteil und Versatz, wie sie gerade stehen.
    private var rest: CGFloat { (1 - stand.anteil) * reise + versatz }

    /// Eine Feder läuft — dann fängt ein Griff das Blatt.
    private var fangbar: Bool {
        stand.buehne && (!ruht || fang != nil) && !Musikstil.bewegungReduziert
    }

    // MARK: Fangen

    /// **Ein Griff in die laufende Feder** (24.09.: „noch nicht 100 %
    /// Apple"): das Blatt bleibt genau dort stehen, wo es gerade gezeigt
    /// wird, und hängt ab jetzt am Finger. Die Stelle kommt aus dem letzten
    /// gezeichneten Bild (``Praesenz``), nicht aus dem Zielwert — sonst
    /// spränge es ans Ende der Feder. Ihr Abschluss schaltet danach nichts
    /// mehr um (`lauf`).
    ///
    /// **Ohne Animation gesetzt, liefe die Feder weiter**: SwiftUI legt
    /// Federn übereinander, statt sie abzulösen — gemessen sprang das Blatt
    /// beim Griff um bis zu 390 Punkt und fuhr danach noch weiter. Erst
    /// ``Halt`` löst die laufende Feder ab und endet sofort.
    private func festhalten() {
        let lp = praesenz.anteil, vs = praesenz.versatz
        stand.lauf += 1
        withAnimation(Animation(Halt())) {
            stand.anteil = lp
            versatz = vs
        }
        fang = Fang(anteil: lp, versatz: vs)
        ruht = false
    }

    /// Am Finger: eins zu eins, bis das Blatt ganz offen steht, darüber die
    /// Gummikante — gerechnet ab dort, wo der Finger es gefangen hat.
    private func nachziehen(_ f: Fang, _ dy: CGFloat) {
        let offen = -(1 - f.anteil) * reise
        let grenze = min(offen, f.versatz)
        let roh = f.versatz + dy
        versatz = roh >= grenze ? roh : grenze - Blattphysik.gummi(grenze - roh, hoehe: Self.gummistrecke)
    }

    /// **Losgelassen nach dem Fang**: über 300 Punkt je Sekunde entscheidet
    /// die Richtung des Fingers, darunter die Lage. Beide Wege nehmen den
    /// Schwung mit (``Blattphysik/blattfeder(von:nach:schwung:)``).
    ///
    /// **Ein Tipp öffnet** (25.09.: ein Tipp auf die Pille, während sie
    /// zuging, öffnete erst nach etwa einer Sekunde). Der Tipp wurde als Griff
    /// gewertet, und ohne Schwung entschied die Lage — unter der Hälfte des
    /// Wegs ging das Blatt weiter zu. Gemessen: Tipp bei Anteil 0,40, danach
    /// fiel er bis 0, kein Bild stieg; öffnen konnte erst die echte Pille nach
    /// dem Ende der Feder. Jetzt kehrt das Blatt aus der gezeigten Lage um.
    private func fangLoslassen(schwung: CGFloat, tipp: Bool = false) {
        guard fang != nil else { return }
        fang = nil
        let weg = min(max(stand.anteil - versatz / max(reise, 1), 0), 1)
        let auf = tipp || (abs(schwung) > 300 ? schwung < 0 : weg > 0.5)
        if auf {
            stand.lauf += 1
            let lauf = stand.lauf
            ruht = false
            withAnimation(Blattphysik.blattfeder(von: rest, nach: 0, schwung: schwung),
                          completionCriteria: .removed) {
                stand.anteil = 1
                versatz = 0
            } completion: {
                if stand.lauf == lauf { ruht = true }
            }
            if !modell.blattOffen {
                gefangenGeoeffnet = true
                modell.blattOffen = true
            }
        } else {
            zugehen(Blattphysik.blattfeder(von: rest, nach: reise, schwung: schwung))
            if modell.blattOffen { modell.blattOffen = false }
        }
    }

    /// Die Fläche, die fängt: die Karte, Bild für Bild dort, wo sie steht.
    private var fangen: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { wert in
                if fang == nil { festhalten() }
                if let f = fang { nachziehen(f, wert.translation.height) }
            }
            .onEnded { wert in
                let t = wert.translation
                fangLoslassen(schwung: wert.velocity.height, tipp: t.width * t.width + t.height * t.height < 100)
            }
    }

    // MARK: Bühne

    /// Karte, Inhalt und die wandernden Teile, alle in Bildschirmpunkten.
    ///
    /// **Was Bild für Bild vom Stand abhängt, rechnet ein animierbarer
    /// Baustein** (``Kartenlage``, ``Huellenflug``, ``Blatttext``): Karte,
    /// Hülle und Text nehmen dieselbe Lage aus derselben Zahl
    /// (``Blattgeometrie``). Vorher mischte SwiftUI jeden Rahmen für sich —
    /// beim Nachfedern der Pille rückte ihre Oberkante 3,7 Punkte, die Hülle
    /// 3,2 und der Titel 0,8 (gemessen): der Text federte nicht mit.
    @ViewBuilder
    private func buehne(_ lied: Lied, voll: CGRect, mini: CGRect, unten: CGFloat) -> some View {
        let p = stand.anteil
        let ruhig = Musikstil.bewegungReduziert
        // Die Lage: bei „Bewegung reduzieren" steht alles gleich am Ziel.
        let lp: CGFloat = ruhig ? 1 : p
        let q: CGFloat = ruhig ? (ansicht == .wiedergabe ? 0 : 1) : kopf
        let karte = Blattlage.mix(mini, voll, lp).offsetBy(dx: 0, dy: versatz)
        let ecke = Blattlage.mix(Musikstil.eckeMini, Musikstil.eckeBlatt, lp)
        let unterlaenge: CGFloat = 400 * lp
        // Der Inhalt hängt an der Oberkante der Karte; zur Pille hin bleibt
        // er um `nachlauf` zurück und steht in ihr ganz unter der Kante.
        let inhaltOben = karte.minY + (1 - lp) * Self.nachlauf
        // Bei 0 steht die echte Pille da — die Bühne zeigt dann nichts,
        // sonst stünde jedes Teil doppelt, und ein seitlicher Wisch zöge
        // nur eins davon mit. Hart, nie überblendet (``Blattstand/buehne``).
        let sichtbar: CGFloat = ruhig ? p : (stand.buehne ? 1 : 0)
        let flug = Flugstand(lp: lp, q: q, versatz: versatz, oben: voll.minY, reise: reise)

        // „Dahinter": die Seite verschwindet hinter fast Schwarz — im selben
        // Maß, in dem das Blatt wächst; hängt es am Finger, kommt sie wieder.
        let dahinter = (ruhig ? 1 : p) * max(0, 1 - max(versatz, 0) / 400)
        Musikstil.blattgrund
            .opacity(dahinter)
            .opacity(sichtbar)
        // **Über dem Blatt reines Schwarz** (24.09.): Uhr und Insel
        // stehen auf Schwarz, die Insel verschwindet darin. Unten läuft es
        // hinter den Ecken des Blatts in den Grund aus.
        //
        // **Erst auf dem letzten Stück des Wegs** (25.09.: beim
        // Antippen stand oben schon Schwarz, bevor das Blatt da war). Es
        // kommt ab 70 % des Wegs und ist beim Schließen, am Finger wie in der
        // Feder, nach den ersten 30 % wieder weg (``Wegdeckung``).
        LinearGradient(stops: [.init(color: .black, location: 0),
                               .init(color: .black, location: voll.minY / (voll.minY + 18)),
                               .init(color: .black.opacity(0), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: voll.minY + 18)
            .modifier(Wegdeckung(stand: flug, von: Self.schwarzAb, bis: 1))
            .opacity(sichtbar)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

        Group {
            Color.clear
                .modifier(Kartenlage(stand: flug, mini: mini, voll: voll, glut: modell.spieler.glut,
                                     bild: modell.bildadresse(lied.bild, punkte: 338), liedtext: q > 0.5,
                                     praesenz: praesenz))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            vollinhalt(lied, breite: voll.width, hoehe: voll.height, unten: unten, q: q)
                .mask(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: ecke, style: .continuous)
                        .frame(width: karte.width, height: karte.height + unterlaenge)
                        .offset(x: karte.minX, y: karte.minY - inhaltOben)
                }
                // **An den Weg gekoppelt, nicht an die Zeit** (24.09.:
                // Schließen von weit oben wirkte unrund). Spur, Steuerung und
                // Aktionsreihe fahren mit dem Blatt und sind in der ersten
                // Hälfte des Wegs weg — am Finger wie in der Feder. Titel und
                // Künstler gehören dazu (``blattzeilen``); in die Pille
                // fliegen nur Karte und Hülle.
                .modifier(Wegdeckung(stand: flug, von: 0.5, bis: 0.97))
                .offset(y: inhaltOben)
                // Beim Zugehen fängt nur die Karte (``fangflaeche``).
                .allowsHitTesting(modell.blattOffen)

            // Titel, Künstler, Ausgabe, Herz, Abspielen der Pille: erst auf
            // dem letzten Stück da.
            Pillenrest(karte: karte, mini: mini, anteil: lp)
                .allowsHitTesting(false)

            wandernd(lied, mini: mini, breite: voll.width, flug: flug)
                .allowsHitTesting(false)

            if modell.blattOffen, ruht, fang == nil, !zieht, kopf == 0 || kopf == 1 {
                tippziele(lied, oben: voll.minY, q: kopf)
            }

            if fangbar {
                Color.clear
                    .modifier(Fangflaeche(stand: flug, mini: mini, voll: voll))
                    .gesture(fangen)
                    .accessibilityHidden(true)
            }
        }
        .opacity(sichtbar)
    }

    /// Die Lagen, nur in Ruhe beschrieben (`ruht`).
    private var gemessen: Binding<Blattlagen> {
        Binding(get: { lagen }, set: { neu in if ruht { lagen = neu } })
    }

    /// Das ganze Blatt in seiner offenen Lage — auch zu gezeichnet, damit
    /// die Stellen von Hülle und Titel schon gemessen sind, wenn es aufgeht.
    private func vollinhalt(_ lied: Lied, breite: CGFloat, hoehe: CGFloat, unten: CGFloat,
                            q: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Grosslage(lied: lied, breite: breite, hoehe: hoehe, unten: unten, q: q,
                      auftritt: auftritt, messrunde: messrunde, lagen: gemessen, ansicht: $ansicht)
                .contentShape(Rectangle())
                .gesture(ziehen)

            Kopflage(lied: lied, hoehe: hoehe, q: q, inhalt: inhalt, messrunde: messrunde, lagen: gemessen,
                     ziehen: ziehen)

            blattzeilen(lied, breite: breite, q: q)
                .modifier(Auftritt(da: auftritt, stufe: 0))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // Ein Tipp auf den Griff schließt, wie in Apple Music.
            Color.clear
                .frame(width: 120, height: 36)
                .contentShape(Rectangle())
                .onTapGesture { schliessen(schwung: 0) }
                .gesture(ziehen)
                .accessibilityHidden(true)
        }
        .frame(width: breite, height: hoehe)
        .coordinateSpace(.named(Self.raum))
        .environment(zugstelle)
        .accessibilityAddTraits(.isModal)
        .accessibilityHidden(!modell.blattOffen)
        .accessibilityAction(.escape) { schliessen(schwung: 0) }
    }

    /// **Die Hülle** — gemischt aus drei Lagen: der Pille, der großen
    /// Wiedergabe und dem Kopf über Liedtext und Schlange (``Huellenflug``).
    /// Nur gezeichnet.
    ///
    /// **Nur die Hülle fliegt** (25.09.). Titel und Künstler flogen
    /// mit und sprangen beim schnellen Schließen zu viel; jetzt gehören sie
    /// im Blatt zum festen Block unten (``blattzeilen``) und stehen in der
    /// Pille an ihrem Platz (``Pillenrest``).
    @ViewBuilder
    private func wandernd(_ lied: Lied, mini: CGRect, breite: CGFloat, flug: Flugstand) -> some View {
        let huelleMini = modell.miniHuelle ?? CGRect(x: mini.minX + 9, y: mini.midY - 20, width: 40, height: 40)
        Color.clear
            .modifier(Huellenflug(stand: flug, mini: huelleMini, gross: lagen.huelleGross, kopf: lagen.huelleKopf,
                                  bild: modell.bildadresse(lied.bild, punkte: 338), kennung: lied.id,
                                  stelle: modell.spieler.schlange.position, schritt: breite,
                                  zeichengroesse: Blattlage.mix(16, 60, max(stand.anteil, 0) * (1 - flug.q))))
            .accessibilityHidden(true)
    }

    /// **Titel und Künstler im Blatt** — an ihren gemessenen Stellen, in der
    /// Wiedergabe groß, über Liedtext und Schlange klein im Kopf
    /// (``Blatttext``). Sie liegen im Inhalt des Blatts: sie fahren mit
    /// Spur, Steuerung und Aktionsreihe herein und hinaus und blenden mit
    /// ihnen am Weg.
    ///
    /// **Der Text läuft nur in Ruhe** (``Lauftext``): offen, keine Feder,
    /// kein Finger, kein Wechsel zum Kopf — dann steht er in seiner
    /// Ausgangslage und läuft im neuen Rahmen neu an.
    @ViewBuilder
    private func blattzeilen(_ lied: Lied, breite: CGFloat, q: CGFloat) -> some View {
        let stelle = modell.spieler.schlange.position
        let laufen = modell.blattOffen && ruht && fang == nil && !zieht && kopfRuht && stand.buehne
        ZStack(alignment: .topLeading) {
            Color.clear
                .modifier(Blatttext(q: q, zeile: Zeilenwert(kennung: lied.id, text: lied.titel),
                                    gross: lagen.titelGross, kopf: lagen.titelKopf,
                                    schrift: Musikstil.blattTitel, sperrung: Musikstil.sperrungBlattTitel,
                                    farbe: Stil.schrift, laufen: laufen, stelle: stelle, schritt: breite))
                .opacity(titelGedrueckt ? 0.85 : 1)
            if let k = lied.kuenstlerzeile, lagen.zeileGross.height > 0 {
                Color.clear
                    .modifier(Blatttext(q: q, zeile: Zeilenwert(kennung: lied.id, text: k),
                                        gross: lagen.zeileGross, kopf: lagen.zeileKopf,
                                        schrift: Musikstil.zeile, sperrung: 0, farbe: Stil.schriftLeise,
                                        laufen: laufen, stelle: stelle, schritt: breite))
                    .opacity(zeileGedrueckt ? 0.85 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// **Tippen führt weiter** (24.09., wie Apple Music): der Titel
    /// zum Album des Lieds (bei Singles die Single), der Künstler zu seiner
    /// Seite — bei mehreren Künstler*innen erst eine Auswahl
    /// (``Kuenstlerwahl``). Das Blatt geht dabei in die Pille zu, die Seite
    /// öffnet sich im Bereich, in dem man ist (``Musikmodell/oeffnenAusBlatt(_:)``).
    ///
    /// **Eigene Ziele, im Layout an ihrem Platz** (24.09.: der Tipp
    /// ging nicht). Vorher war der gezeichnete, fliegende Text selbst der
    /// Knopf: sein Rahmen stand im Layout oben links und wurde erst im
    /// animierbaren Baustein an seine Stelle verschoben. Jetzt liegen die
    /// Ziele nur in Ruhe da, genau über den gemessenen Stellen, mindestens
    /// 44 hoch; die Ziehgeste läuft daneben mit, damit man auch am Titel
    /// das Blatt herunterziehen kann.
    @ViewBuilder
    private func tippziele(_ lied: Lied, oben: CGFloat, q: CGFloat) -> some View {
        let titel = (q < 0.5 ? lagen.titelGross : lagen.titelKopf).offsetBy(dx: 0, dy: oben)
        let zeile = (q < 0.5 ? lagen.zeileGross : lagen.zeileKopf).offsetBy(dx: 0, dy: oben)
        let namen = lied.kuenstlernamen
        let mitZeile = lied.kuenstlerzeile != nil && zeile.height > 0
        // Die Grenze zwischen beiden Zielen liegt in der Lücke dazwischen.
        let mitte = mitZeile ? (titel.maxY + zeile.minY) / 2 : titel.maxY + 10
        let titelOben = min(titel.minY - 10, mitte - 22)
        ZStack(alignment: .topLeading) {
            if titel.height > 0 {
                Button { titelTippen(lied) } label: {
                    Color.clear
                        .frame(width: max(titel.width + 16, 44), height: mitte - titelOben)
                        .contentShape(Rectangle())
                }
                .buttonStyle(Tippziel(gedrueckt: $titelGedrueckt))
                .simultaneousGesture(ziehen)
                .disabled(lied.albumID == nil)
                .accessibilityLabel(Text(verbatim: lied.titel))
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(lied.albumID == nil ? Text(verbatim: "") : Text("Zum Album"))
                .padding(.leading, max(titel.minX - 8, 0))
                .padding(.top, titelOben)
            }
            if mitZeile, let k = lied.kuenstlerzeile {
                Button { kuenstlerTippen(lied, k) } label: {
                    Color.clear
                        .frame(width: max(zeile.width + 16, 44), height: max(zeile.maxY + 10, mitte + 22) - mitte)
                        .contentShape(Rectangle())
                }
                .buttonStyle(Tippziel(gedrueckt: $zeileGedrueckt))
                .simultaneousGesture(ziehen)
                .disabled(lied.kuenstlerID == nil && namen.count < 2)
                .accessibilityLabel(Text(verbatim: k))
                .accessibilityHint(namen.count > 1 ? Text("Zeigt die Künstler*innen")
                                   : lied.kuenstlerID == nil ? Text(verbatim: "") : Text("Zum Künstler"))
                .padding(.leading, max(zeile.minX - 8, 0))
                .padding(.top, mitte)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func titelTippen(_ lied: Lied) {
        guard let id = lied.albumID else { return }
        modell.oeffnenAusBlatt(.album(Album(id: id, titel: lied.album ?? "", bild: lied.bild)))
    }

    private func kuenstlerTippen(_ lied: Lied, _ zeile: String) {
        if lied.kuenstlernamen.count > 1 {
            stand.kuenstlerwahl = lied
        } else if let id = lied.kuenstlerID {
            modell.oeffnenAusBlatt(.kuenstler(Kuenstler(id: id, name: lied.ersterKuenstler ?? zeile)))
        }
    }

    // MARK: Ziehen

    /// Senkrecht zieht das Blatt zurück in die Pille; es folgt dem Finger
    /// eins zu eins, nach oben gibt die Gummikante nur ein Stück nach. Zu ab
    /// einem Viertel des Wegs oder 700 Punkt je Sekunde.
    private var ziehen: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { gezogen($0.translation) }
            .onEnded { losgelassen(schwung: $0.velocity.height) }
    }

    private func gezogen(_ t: CGSize) {
        // Nur senkrecht; waagerecht gehört den Zeilen und der Spur.
        guard zieht || abs(t.height) > abs(t.width) else { return }
        zieht = true
        // **Ab der Schwelle, nicht ab dem Aufsetzen** — sonst spränge das
        // Blatt beim ersten Bild um die 12 Punkt, die die Geste abwartet.
        let anfang = zugAnfang ?? t.height
        if zugAnfang == nil { zugAnfang = anfang }
        let dy = t.height - anfang
        versatz = dy >= 0 ? dy : -Blattphysik.gummi(-dy, hoehe: Self.gummistrecke)
    }

    private func losgelassen(schwung: CGFloat) {
        zugAnfang = nil
        guard zieht else { return }
        zieht = false
        let weg = max(versatz, 0)
        if weg > reise * 0.25 || (schwung > 700 && weg > 0) {
            schliessen(schwung: schwung)
        } else {
            let lauf = stand.lauf
            ruht = false
            withAnimation(Blattphysik.blattfeder(von: versatz, nach: 0, schwung: schwung),
                          completionCriteria: .removed) {
                versatz = 0
            } completion: {
                if stand.lauf == lauf { ruht = true }
            }
        }
    }

    /// Zurück in die Pille, mit dem Schwung des Fingers und derselben Feder
    /// wie beim Öffnen.
    private func schliessen(schwung: CGFloat) {
        zugehen(Blattphysik.blattfeder(von: max(rest, 0), nach: reise, schwung: max(schwung, 0)))
        modell.blattOffen = false
    }
}

/// **Deckkraft aus dem Anteil, Bild für Bild.** Der `body` des Blatts sieht
/// nur den Zielwert, und eine Deckkraft daraus liefe über die ganze Feder
/// gleichmäßig — dieser Baustein bekommt jeden Zwischenwert und setzt nur
/// die Deckkraft: sichtbar ab `bis`, weg unter `von` (oder umgekehrt).
nonisolated private struct Anteilsdeckung: ViewModifier, Animatable {
    var anteil: CGFloat
    let von: CGFloat
    let bis: CGFloat
    var umgekehrt = false

    var animatableData: CGFloat {
        get { anteil }
        set { anteil = newValue }
    }

    @MainActor func body(content: Content) -> some View {
        let t = min(max((anteil - von) / max(bis - von, 0.0001), 0), 1)
        return content.opacity(Musikstil.bewegungReduziert ? 1 : umgekehrt ? 1 - t : t)
    }
}

/// **Deckkraft aus dem Weg, Bild für Bild** — wie ``Anteilsdeckung``, aber
/// am Weg der Karte (``Blattgeometrie/weg``): am Finger nach unten gezogen
/// zählt der Weg schon, bevor die Feder läuft.
nonisolated private struct Wegdeckung: ViewModifier, Animatable {
    var stand: Flugstand
    let von: CGFloat
    let bis: CGFloat

    /// Nur Anteil und Versatz — der Wechsel zum Kopf rechnet hier nichts neu.
    var animatableData: Flugstand.WegDaten {
        get { stand.wegDaten }
        set { stand.wegDaten = newValue }
    }

    @MainActor func body(content: Content) -> some View {
        content.opacity(Musikstil.bewegungReduziert ? 1 : Blattlage.rampe(stand.weg, von: von, bis: bis))
    }
}

/// **Der Stand der Bewegung, wie ihn die animierbaren Bausteine sehen**:
/// Anteil, Kopf und Versatz laufen unter der Feder mit, Oberkante und Weg
/// zur Pille stehen fest.
nonisolated struct Flugstand: Equatable {
    var lp: CGFloat
    var q: CGFloat
    var versatz: CGFloat
    let oben: CGFloat
    let reise: CGFloat

    typealias AnimatableData = AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>
    var animatableData: AnimatableData {
        get { AnimatablePair(AnimatablePair(lp, q), versatz) }
        set {
            lp = newValue.first.first
            q = newValue.first.second
            versatz = newValue.second
        }
    }

    /// **Nur Anteil und Versatz** — für Bausteine, die vom Kopf nichts
    /// wissen (Karte, Deckung am Weg). Beim Wechsel zu Liedtext oder
    /// Schlange rechnen sie so nicht je Bild neu (24.09.: der Wechsel
    /// wirkte wie 30–60 Hz).
    typealias WegDaten = AnimatablePair<CGFloat, CGFloat>
    var wegDaten: WegDaten {
        get { AnimatablePair(lp, versatz) }
        set {
            lp = newValue.first
            versatz = newValue.second
        }
    }

    /// **Der Anteil, mit dem gemischt wird — nie unter der Pille.** Federt
    /// die Karte über die Pille hinaus, fährt alles zusammen ein Stück
    /// weiter nach unten (``nachfedern``), statt sich zu verformen: vorher
    /// wurde die Karte dabei kürzer, die Hülle kleiner, der Titel blieb fast
    /// stehen.
    var form: CGFloat { max(lp, 0) }
    var nachfedern: CGFloat { -min(lp, 0) * reise }

    /// **Wie weit die Karte auf ihrem Weg ist**: 1 offen, 0 die Pille — am
    /// Finger nach unten gezogen zählt der Versatz mit.
    var weg: CGFloat { min(max(lp - max(versatz, 0) / max(reise, 1), 0), 1) }

    /// Eine Stelle zwischen der Pille (`mini`) und dem Blatt (`gross` in der
    /// Wiedergabe, `kopf` über Liedtext und Schlange, beide im Raum des
    /// Blatts gemessen).
    ///
    /// **Der Versatz kommt obendrauf, wie bei der Karte — nie in die
    /// Mischung** (25.09.: beim schnellen Schließen sprang das Cover
    /// hoch). Stand er im Ziel, rechnete die Feder Anteil mal Versatz: beide
    /// laufen unter derselben Feder gegen null, ihr Produkt nicht gleichmäßig.
    /// Gemessen nach 350 Punkt am Finger und Wurf: im ersten Bild fiel die
    /// Karte 53 Punkt, das Cover stieg 1,2 — nach 69 ms stand es 109 Punkt
    /// zu hoch auf der Karte und überholte sie bei 219 ms nach unten.
    func rahmen(mini: CGRect, gross: CGRect, kopf: CGRect) -> CGRect {
        let ziel = Blattlage.mix(gross, kopf, q).offsetBy(dx: 0, dy: oben)
        return Blattlage.mix(mini, ziel, form).offsetBy(dx: 0, dy: versatz + nachfedern)
    }
}

/// **Die Fläche der Karte** — in der Pille ihr Verlauf über dem Glas (wie
/// ``Minispieler``), im Blatt der Grund mit der verschwommenen Hülle
/// (``Blatthintergrund``).
///
/// **Über den ganzen Weg gemischt** (24.09.: beim Herunterziehen
/// sprang die Farbe ganz am Ende). Gemessen am Übergabebild: die Bühne
/// stand bis zuletzt einfarbig bei #3F1E35, die echte Pille daneben mit
/// ihrem Verlauf bei #5C2737 — der Verlauf der Bühne war nicht der der
/// Pille. Jetzt zeichnet die Karte denselben Baustein wie die Pille
/// (``Pillenflaeche``) in ihrer Größe, und Grund und Verlauf mischen sich
/// am Weg (``Flugstand/weg``): wer das Blatt am Finger herunterzieht, sieht
/// die Pillenfarbe schon kommen.
///
/// **Das Glas schaltet hart** und nur, wo es verdeckt ist: eine
/// `UIVisualEffectView` unter voller Deckkraft zeichnet mit halber
/// Deckkraft nicht richtig (Apple, `UIVisualEffectView`). Sie steht ab
/// einem Zehntel vor der Pille, darüber noch der deckende Grund, der dann
/// ausblendet. Die Linie der Pille liegt in der Karte, bündig unten, von
/// ihrer Form beschnitten.
nonisolated private struct Kartenlage: ViewModifier, Animatable {
    var stand: Flugstand
    let mini: CGRect
    let voll: CGRect
    let glut: Huellenton.Glut?
    let bild: URL?
    let liedtext: Bool
    let praesenz: Praesenz

    var animatableData: Flugstand.WegDaten {
        get { stand.wegDaten }
        set { stand.wegDaten = newValue }
    }

    @MainActor func body(content: Content) -> some View {
        let _ = praesenz.merken(stand)
        let l = stand.form
        let karte = Blattlage.mix(mini, voll, l).offsetBy(dx: 0, dy: stand.versatz + stand.nachfedern)
        let ecke = Blattlage.mix(Musikstil.eckeMini, Musikstil.eckeBlatt, l)
        let unterlaenge: CGFloat = 400 * l
        let w = Musikstil.bewegungReduziert ? 1 : stand.weg
        let form = RoundedRectangle(cornerRadius: ecke, style: .continuous)
        ZStack(alignment: .top) {
            Stil.grund
                .opacity(Blattlage.rampe(w, von: 0, bis: 0.1))
            Blatthintergrund(glut: glut, bild: bild, liedtext: liedtext)
                .frame(width: voll.width, height: voll.height)
                .opacity(w)
            Pillenflaeche(glut: glut)
                .frame(width: karte.width, height: karte.height)
                .opacity((1 - w) * Pillenflaeche.deckung)
            // Nur, solange sie zu sehen ist — sonst liefe ihr Takt unter dem
            // offenen Blatt mit.
            if w < 0.15 {
                Pillenspur()
                    .frame(width: karte.width, height: karte.height, alignment: .bottom)
                    .opacity(1 - Blattlage.rampe(w, von: 0, bis: 0.15))
            }
        }
        // **Der Grund reicht weiter nach unten, als das Blatt je fährt** —
        // die Feder schießt über, und darunter stünde sonst eine harte Kante.
        .frame(width: karte.width, height: karte.height + unterlaenge, alignment: .top)
        .clipShape(form)
        .background(alignment: .top) {
            // **Der Schatten endet an der Leiste** (24.09.: beim
            // Nachfedern lag er über ihr und verschwand am Ende schlagartig).
            // Die echte Pille steht unter der Leiste, ihr Schatten verschwindet
            // dahinter; die Karte liegt über allem — ihr Schatten wird deshalb
            // an der Oberkante der Leiste abgeschnitten, wo diese gerade steht
            // (``Leistenfahrt``). So sieht er in der Karte und in der Pille
            // gleich aus, und beim Übergabebild ändert sich nichts.
            let leiste = mini.maxY + 8 + (Musikstil.bewegungReduziert ? 0 : stand.lp * Leistenfahrt.weg)
            ZStack(alignment: .top) {
                Pillenschatten.ansicht(karte.size)
                    .mask(alignment: .top) {
                        Rectangle().frame(height: max(0, leiste - karte.minY + Pillenschatten.rand))
                    }
                    .offset(y: -Pillenschatten.rand)
                    .opacity(1 - w)
                // Das Glas der Pille — mit fester Ecke, damit keine Maske je
                // Bild neu gerechnet wird (`Unschaerfe`).
                Pillenglas()
                    .frame(width: karte.width, height: karte.height)
                    .clipShape(RoundedRectangle(cornerRadius: Musikstil.eckeMini, style: .continuous))
                    .opacity(w < 0.12 ? 1 : 0)
            }
        }
        .frame(width: karte.width, height: karte.height, alignment: .top)
        .offset(x: karte.minX, y: karte.minY)
    }
}

/// **Was von der Pille bleibt, solange sie wächst**: Titel und Künstler,
/// Ausgabe, Herz und Abspielen an ihrer Stelle — sie fahren mit der Karte
/// und sind nur auf dem letzten Stück vor der Pille da. Nur gezeichnet;
/// die Knöpfe gehören der echten Pille (``Minispieler``), Reihenfolge,
/// Maße und Schrift wie dort. Die Linie unten liegt in der Karte selbst
/// (``Kartenlage``).
///
/// **Titel und Künstler blenden weich** (25.09.): beim Schließen
/// über die letzten 30 % des Anteils ein, beim Öffnen über die ersten aus —
/// sie fliegen nicht mehr. Die Knöpfe wie bisher über 15 %.
private struct Pillenrest: View {
    let karte: CGRect
    let mini: CGRect
    let anteil: CGFloat
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        let spieler = modell.spieler
        let favorit = spieler.aktuell.map { modell.istFavorit($0.id, sonst: $0.favorit) } ?? false
        let dx = karte.minX - mini.minX, dy = karte.minY - mini.minY
        ZStack(alignment: .topLeading) {
            HStack(spacing: Minispieler.knopfabstand) {
                Pillenzeichen(zeichen: .ausgabe, groesse: Minispieler.ausgabezeichen)
                    .foregroundStyle(spieler.fern != nil ? Stil.akzent : Stil.schrift)
                    .animation(Musikstil.bewegungReduziert ? nil : .easeInOut(duration: 0.3), value: spieler.fern != nil)
                    .frame(width: 44, height: 44)
                Pillenzeichen(zeichen: favorit ? .herz : .herzUmriss, groesse: Minispieler.herzzeichen)
                    .foregroundStyle(favorit ? Stil.akzent : Stil.schrift)
                    .frame(width: 44, height: 44)
                Pillenzeichen(zeichen: spieler.spielt ? .pause : .abspielen, groesse: Minispieler.spielzeichen)
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(Stil.schrift)
            .offset(x: karte.maxX - Minispieler.rechts - Minispieler.knopfbreite,
                    y: karte.minY + (mini.height - 44) / 2)
            .modifier(Anteilsdeckung(anteil: anteil, von: 0, bis: 0.15, umgekehrt: true))

            if let lied = spieler.aktuell {
                ZStack(alignment: .topLeading) {
                    if let t = modell.miniTitel {
                        Text(verbatim: lied.titel)
                            .font(Musikstil.zeile)
                            .foregroundStyle(Stil.schrift)
                            .lineLimit(1)
                            .frame(width: max(t.width, 1), height: t.height, alignment: .leading)
                            .offset(x: t.minX + dx, y: t.minY + dy)
                    }
                    if let k = lied.kuenstlerzeile, let z = modell.miniZeile {
                        Text(verbatim: k)
                            .font(Musikstil.angabe)
                            .foregroundStyle(Musikstil.pillenzweitzeile(spieler.glut))
                            .lineLimit(1)
                            .frame(width: max(z.width, 1), height: z.height, alignment: .leading)
                            .offset(x: z.minX + dx, y: z.minY + dy)
                    }
                }
                .modifier(Anteilsdeckung(anteil: anteil, von: 0, bis: 0.3, umgekehrt: true))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Wo Hülle, Titel und Künstler in den beiden Lagen des offenen Blatts
/// stehen — gemessen, nicht gerechnet, damit sich eine Änderung am Aufbau
/// nicht von der Bewegung entfernt.
struct Blattlagen: Equatable {
    var huelleGross = CGRect.zero
    var titelGross = CGRect.zero
    var zeileGross = CGRect.zero
    var huelleKopf = CGRect.zero
    var titelKopf = CGRect.zero
    var zeileKopf = CGRect.zero
    /// Oberkante von Spur, Steuerung und Aktionsreihe.
    var untenOben: CGFloat = 0
}

/// Mischen zwischen zwei Lagen.
enum Blattlage {
    static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    static func mix(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: mix(a.minX, b.minX, t), y: mix(a.minY, b.minY, t),
               width: mix(a.width, b.width, t), height: mix(a.height, b.height, t))
    }

    /// 0 bis `von`, 1 ab `bis`, dazwischen gleichmäßig.
    static func rampe(_ t: CGFloat, von: CGFloat, bis: CGFloat) -> CGFloat {
        min(max((t - von) / max(bis - von, 0.0001), 0), 1)
    }
}

/// **Die Hülle auf dem Weg** zwischen Pille, großer Lage und Kopf — Lage,
/// Ecke und Schatten Bild für Bild aus dem ``Flugstand``.
///
/// **Zwei Schatten als fertige Bilder** (``Huellenschatten``): in der Pille
/// klein und weich, im Blatt der große aus der Übergabe (§6), dazu eine
/// feine helle Kante, damit sich die Hülle auch von einem Grund in ihrer
/// eigenen Farbe abhebt (24.09.: rote Hülle auf rotem Grund).
nonisolated private struct Huellenflug: ViewModifier, Animatable {
    var stand: Flugstand
    let mini: CGRect
    let gross: CGRect
    let kopf: CGRect
    let bild: URL?
    /// Das Lied und sein Platz in der Schlange — für den Liedwechsel.
    let kennung: String
    let stelle: Int?
    /// Wie weit sie beim Liedwechsel rückt: die Breite des Blatts.
    let schritt: CGFloat
    let zeichengroesse: CGFloat

    var animatableData: Flugstand.AnimatableData {
        get { stand.animatableData }
        set { stand.animatableData = newValue }
    }

    @MainActor func body(content: Content) -> some View {
        let r = stand.rahmen(mini: mini, gross: gross, kopf: kopf)
        let l = min(stand.form, 1)
        let imBlatt = l * (1 - stand.q)
        let ecke = Blattlage.mix(Musikstil.eckeKlein,
                                 Blattlage.mix(Musikstil.eckeHuelleGross, Musikstil.eckeKlein, stand.q), l)
        ZStack {
            Huellenschatten(art: .klein)
                .opacity(1 - Blattlage.rampe(l, von: 0, bis: 0.5))
            Huellenschatten(art: .gross)
                .opacity(imBlatt)
            // Ein neues Lied: die alte Hülle schiebt hinaus, die neue folgt
            // eine Blattbreite dahinter (``Liedwechsel``), je in ihrer
            // eigenen Form.
            Liedwechsel(wert: Huellenwert(kennung: kennung, bild: bild), stelle: stelle,
                        schritt: schritt) { w in
                Netzhuelle(adresse: w.bild, zeichengroesse: zeichengroesse)
                    .frame(width: max(r.width, 1), height: max(r.height, 1))
                    .clipShape(RoundedRectangle(cornerRadius: ecke, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ecke, style: .continuous)
                            .strokeBorder(Huellenschatten.kante, lineWidth: 1)
                            .opacity(imBlatt)
                    }
            }
        }
        .frame(width: max(r.width, 1), height: max(r.height, 1))
        .offset(x: r.minX, y: r.minY)
    }
}

/// **Eine Textzeile im Blatt** — in der Wiedergabe groß, im Kopf über
/// Liedtext und Schlange klein, dazwischen gemischt (am Kopf, `q`). Beide
/// Lagen im Raum des Blatts gemessen.
///
/// **Der Blatttext hat überall die Breite der großen Lage** (24.09.:
/// im Kopf stand der lange Titel anders gekürzt, beim Zurückwechseln
/// flackerten die letzten zwei Buchstaben). Es ist derselbe Satz, nur auf
/// die Höhe des Rahmens skaliert — er wird nirgends neu umbrochen.
///
/// **Beim Liedwechsel rückt er wie die Hülle** (``Liedwechsel``): eine
/// Blattbreite, auf dem Schirm gemessen — im Kopf entsprechend weiter.
nonisolated private struct Blatttext: ViewModifier, Animatable {
    var q: CGFloat
    let zeile: Zeilenwert
    let gross: CGRect
    let kopf: CGRect
    let schrift: Font
    let sperrung: CGFloat
    let farbe: Color
    /// In Ruhe darf ein zu langer Text laufen (``Lauftext``).
    let laufen: Bool
    /// Der Platz des Lieds in der Schlange — für den Liedwechsel.
    let stelle: Int?
    let schritt: CGFloat

    var animatableData: CGFloat {
        get { q }
        set { q = newValue }
    }

    @MainActor func body(content: Content) -> some View {
        let r = Blattlage.mix(gross, kopf, q)
        let grundhoehe = max(gross.height, 1)
        let massstab = max(r.height / grundhoehe, 0.05)
        Liedwechsel(wert: zeile, stelle: stelle, schritt: schritt / massstab, ausrichtung: .leading) { z in
            Lauftext(text: z.text, schrift: schrift, sperrung: sperrung, farbe: farbe, laufen: laufen && z == zeile)
        }
        .frame(width: max(gross.width, 1), height: grundhoehe, alignment: .leading)
        .scaleEffect(massstab, anchor: .topLeading)
        .frame(width: max(r.width, 1), height: max(r.height, 1), alignment: .topLeading)
        .offset(x: r.minX, y: r.minY)
    }
}

private struct Griff: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Misst den Rahmen im Raum des Wiedergabeblatts — in jeder neuen
    /// `runde` noch einmal (``Wiedergabeblatt``, `messrunde`).
    fileprivate func messen(_ runde: Int, _ setzen: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Wiedergabeblatt.raum)) } action: { setzen($0) }
            .id(runde)
    }
}

/// **Die Glut**: ein radialer Verlauf aus der Farbe der Hülle, oben — 62 %
/// der Höhe mit 0,42 in der Wiedergabe, 40 % mit 0,34 beim Liedtext, dort
/// von links oben (Übergabe §6; im Entwurf `radial-gradient(90% 70% at 50% 0%)`
/// bzw. `(90% 80% at 30% 0%)`).
struct Glut: View {
    let glut: Huellenton.Glut?
    let liedtext: Bool

    var body: some View {
        GeometryReader { g in
            let breite = g.size.width, hoehe = g.size.height
            let mitte = liedtext ? 0.30 : 0.5
            let rx = breite * 0.9, ry = hoehe * (liedtext ? 0.8 : 0.7)
            EllipticalGradient(stops: stufen, center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                .frame(width: rx * 2, height: ry * 2)
                .position(x: breite * mitte, y: 0)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var stufen: [Gradient.Stop] {
        guard let glut else { return [.init(color: .clear, location: 0)] }
        let haupt = farbe(glut.haupt)
        if liedtext {
            return [.init(color: haupt.opacity(0.34), location: 0),
                    .init(color: Stil.grund.opacity(0), location: 1)]
        }
        return [.init(color: haupt.opacity(0.42), location: 0),
                .init(color: farbe(glut.neben).opacity(0.28), location: 0.45),
                .init(color: Stil.grund.opacity(0), location: 1)]
    }

    private func farbe(_ f: Farbwert) -> Color {
        Color(red: f.rot, green: f.gruen, blue: f.blau)
    }
}

/// **Wie weit das Blatt offen ist**: 0 die Pille, 1 das Blatt — dazu der Zug
/// vom Mini-Player herauf und der Schwung beim Loslassen. Die Leiste fährt
/// damit nach unten weg, und die echte Pille tritt zurück, solange die
/// wachsende an ihrer Stelle steht. Liegt in der Hauptansicht, nicht im
/// Modell: nur Pille, Leiste und Blatt lesen es.
@MainActor
@Observable
final class Blattstand {
    var anteil: CGFloat = 0
    /// Wie weit der Finger das Blatt vom Mini-Player heraufgezogen hat;
    /// `nil`, solange niemand zieht.
    var zug: CGFloat?
    /// Der Schwung beim Loslassen, für die Feder, die das Blatt öffnet.
    var schwung: CGFloat?
    /// **Ob die Bühne des Blatts steht** — ab dem ersten Bild des Öffnens,
    /// bis die Feder des Schließens ganz ausgeschwungen ist. So lange tritt
    /// die echte Pille zurück. Hart geschaltet, nie überblendet.
    var buehne = false
    /// Zählt jedes Auf und Zu; eine Schließfeder, die überholt wurde,
    /// schaltet danach nichts mehr um.
    var lauf = 0
    /// Das Lied, dessen Künstler*innen zur Wahl stehen (``Kuenstlerwahl``).
    var kuenstlerwahl: Lied?
}

/// **Was das letzte Bild wirklich zeigte** — Anteil und Versatz, wie sie
/// ``Kartenlage`` Bild für Bild bekommt. Der `body` des Blatts sieht nur
/// Zielwerte; wer mitten in die Feder greift, braucht die gezeigte Stelle.
/// Kein `@Observable`: geschrieben wird in jedem Bild, gelesen nur beim Griff.
@MainActor
final class Praesenz {
    private(set) var anteil: CGFloat = 0
    private(set) var versatz: CGFloat = 0

    func merken(_ stand: Flugstand) {
        anteil = stand.lp
        versatz = stand.versatz
    }
}

/// **Eine Animation, die eine laufende Feder ablöst und sofort endet** —
/// damit steht ein Wert dort, wo er gezeigt wird (``Wiedergabeblatt``,
/// Fangen). Ein Wechsel ohne Animation reicht dafür nicht: die Feder liefe
/// obendrauf weiter.
struct Halt: CustomAnimation {
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        nil
    }

    func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval,
                                          context: inout AnimationContext<V>) -> Bool {
        true
    }
}

/// Wo der Finger das Blatt in der Feder gefangen hat.
struct Fang: Equatable {
    let anteil: CGFloat
    let versatz: CGFloat
}

/// **Die Fläche, die in der Feder fängt**: genau die Karte, Bild für Bild
/// dort, wo sie gezeichnet wird — im Layout, nicht nur verschoben, damit
/// der Griff trifft, was man sieht.
nonisolated private struct Fangflaeche: ViewModifier, Animatable {
    var stand: Flugstand
    let mini: CGRect
    let voll: CGRect

    var animatableData: Flugstand.WegDaten {
        get { stand.wegDaten }
        set { stand.wegDaten = newValue }
    }

    @MainActor func body(content: Content) -> some View {
        let karte = Blattlage.mix(mini, voll, stand.form).offsetBy(dx: 0, dy: stand.versatz + stand.nachfedern)
        return content
            .frame(width: max(karte.width, 1), height: max(karte.height + 400 * stand.form, 1))
            .contentShape(Rectangle())
            .padding(.leading, max(karte.minX, 0))
            .padding(.top, karte.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Meldet, ob ein Tippziel gerade gedrückt ist — der gezeichnete Text
/// darüber wird dann leiser (``Druckknopf``: 85 %).
private struct Tippziel: ButtonStyle {
    @Binding var gedrueckt: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, neu in
                withAnimation(Musikstil.druckkurve(neu)) { gedrueckt = neu }
            }
    }
}


// MARK: - Grund des Blatts

/// **Der Grund des offenen Blatts wie in Apple Music**: die Hülle groß und
/// stark verschwommen, satt und abgedunkelt (24.09.) — die Glut geht
/// darin auf. Nach unten, wo Zeiten und Steuerung stehen, läuft sie in den
/// Grund aus; über Liedtext und Schlange liegt sie dunkler.
///
/// **Das Bild wird einmal je Hülle gerechnet** (``Blattbilder``), klein und
/// verschwommen, nie in der Bewegung. Wechselt das Lied, blendet das neue
/// über das alte. Ohne Hülle bleibt die Glut.
private struct Blatthintergrund: View {
    let glut: Huellenton.Glut?
    let bild: URL?
    let liedtext: Bool
    @State private var gezeigt: Grundbild

    /// Das verschwommene Bild, das gerade steht — gleich, solange Adresse
    /// und Dasein gleich sind. Wechselt es, deckt das neue über dem alten
    /// auf (``Deckwechsel``); bis das neue geladen ist, bleibt das alte.
    struct Grundbild: Equatable {
        let adresse: URL?
        let bild: Image?

        static func == (a: Self, b: Self) -> Bool { a.adresse == b.adresse && (a.bild == nil) == (b.bild == nil) }
    }

    init(glut: Huellenton.Glut?, bild: URL?, liedtext: Bool) {
        self.glut = glut
        self.bild = bild
        self.liedtext = liedtext
        _gezeigt = State(initialValue: Grundbild(adresse: bild, bild: bild.flatMap { Blattbilder.geteilt.fertig($0) }))
    }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .top) {
                Deckwechsel(wert: gezeigt) { grund in
                    if let verschwommen = grund.bild {
                        verschwommen
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: g.size.width, height: g.size.height)
                            .clipped()
                    } else {
                        Glut(glut: glut, liedtext: liedtext)
                            .frame(height: g.size.height * (liedtext ? 0.40 : 0.62))
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                // Unten in den Grund: dort stehen Zeiten in `schriftSehrLeise`
                // (4,5 : 1 nur auf fast Schwarz). Über dem Liedtext dunkler —
                // eine Schicht darüber blendet mit dem Kopf ein, statt dass
                // der Verlauf im ersten Bild des Wechsels umspringt.
                LinearGradient(stops: [.init(color: .black.opacity(0), location: 0),
                                       .init(color: .black.opacity(0.05), location: 0.5),
                                       .init(color: Stil.grund.opacity(0.9), location: 0.72),
                                       .init(color: Stil.grund, location: 0.86)],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0),
                                       .init(color: .black.opacity(0.42), location: 0.5),
                                       .init(color: .black.opacity(0), location: 0.72)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(liedtext ? 1 : 0)
                    .animation(Musikstil.blattbewegung, value: liedtext)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: bild) {
            guard let bild else {
                gezeigt = Grundbild(adresse: nil, bild: nil)
                return
            }
            if let fertig = Blattbilder.geteilt.fertig(bild) {
                gezeigt = Grundbild(adresse: bild, bild: fertig)
                return
            }
            let neu = await Blattbilder.geteilt.laden(bild)
            guard !Task.isCancelled else { return }
            gezeigt = Grundbild(adresse: bild, bild: neu)
        }
    }
}

/// **Die verschwommenen Hüllen**, je Hülle einmal gerechnet und gemerkt.
///
/// Klein gerechnet (96 × 96), verschwommen, satter gemacht und abgedunkelt
/// (``Blattgrund``): kein Punkt heller als Leuchtdichte 0,09 — Weiß hat
/// darauf wenigstens 7,5 : 1, `schriftLeise` 4,5 : 1 — **und deutlich
/// dunkler als die Hülle selbst** (24.09.: rote Hülle auf demselben
/// Rot). Groß gezogen bleibt es weich, weil es schon verschwommen ist.
@MainActor
final class Blattbilder {
    static let geteilt = Blattbilder()
    private var gemerkt: [String: Image] = [:]
    private var reihe: [String] = []
    private var laufend: [String: Task<Image?, Never>] = [:]

    nonisolated static let kante = 96
    nonisolated static let hoechsteLeuchtdichte = Blattgrund.hoechsteLeuchtdichte

    func fertig(_ url: URL) -> Image? { gemerkt[Bildlager.schluessel(url)] }

    func laden(_ url: URL) async -> Image? {
        let schluessel = Bildlager.schluessel(url)
        if let da = gemerkt[schluessel] { return da }
        if let lauf = laufend[schluessel] { return await lauf.value }
        let lauf = Task<Image?, Never> {
            guard let roh = await Bildlager.geteilt.rohbildLaden(url) else { return nil }
            let kiste = Bildkiste(bild: roh)
            let neu = await Task.detached(priority: .utility) { Self.verwischen(kiste) }.value
            return neu.map { Image(decorative: $0.bild, scale: 1) }
        }
        laufend[schluessel] = lauf
        let bild = await lauf.value
        laufend[schluessel] = nil
        if let bild {
            gemerkt[schluessel] = bild
            reihe.append(schluessel)
            if reihe.count > 12 { gemerkt.removeValue(forKey: reihe.removeFirst()) }
        }
        return bild
    }

    nonisolated static func verwischen(_ kiste: Bildkiste) -> Bildkiste? {
        let n = kante
        let raum = CGColorSpace(name: CGColorSpace.sRGB)!
        // Erst klein: aus 1200 werden 96 Punkte, das Verwischen ist dann billig.
        guard let klein = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                    space: raum, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        klein.interpolationQuality = .high
        klein.draw(kiste.bild, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let kleinBild = klein.makeImage() else { return nil }

        let eingang = CIImage(cgImage: kleinBild).clampedToExtent()
        let unscharf = eingang.applyingGaussianBlur(sigma: 7)
        let satt = unscharf.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.4])
            .cropped(to: CGRect(x: 0, y: 0, width: n, height: n))
        let kontext = CIContext(options: [.workingColorSpace: raum, .outputColorSpace: raum])
        var punkte = [UInt8](repeating: 0, count: n * n * 4)
        kontext.render(satt, toBitmap: &punkte, rowBytes: n * 4,
                       bounds: CGRect(x: 0, y: 0, width: n, height: n), format: .RGBA8, colorSpace: raum)

        // **Deutlich unter der Hülle** (``Blattgrund``): abdunkeln auf eine
        // Grenze, die sich nach der Hülle richtet, leicht entsättigen, bei
        // dunklen Hüllen etwas anheben — linear gerechnet, in MusikKit geprüft.
        var hell = [UInt8](repeating: 0, count: n * n * 4)
        if let roh = CGContext(data: &hell, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                               space: raum, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            roh.draw(kleinBild, in: CGRect(x: 0, y: 0, width: n, height: n))
        }
        Blattgrund.anpassen(&punkte, huelle: Blattgrund.mittlereLeuchtdichte(hell))
        guard let anbieter = CGDataProvider(data: Data(punkte) as CFData),
              let fertig = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                                   space: raum, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                   provider: anbieter, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return Bildkiste(bild: fertig)
    }
}

// MARK: - Schatten als Bild

/// **Der Schatten unter der Hülle — ein fertiges Bild**, auf die Hülle
/// gezogen und mit ihr skaliert. Ein `.shadow` mit wanderndem Radius würde
/// je Bild neu gerechnet; das Bild wird nur skaliert.
///
/// **Zwei Größen** (24.09.: in der Pille sah der Schatten aus wie
/// „eine fette Ebene unter dem Cover in fester Farbe"). Vorher war es ein
/// Bild für beide, in der Pille auf 60 % gedämpft: 3,2 Punkt nach unten
/// versetzt, Schwarz 45 % — ein dunkler Sockel unter der kleinen Hülle. Im
/// Blatt lag das Bild gar nicht an der Hülle: ohne Rahmen füllte es die
/// ganze Bühne (gemessen 440 × 1298), der Schatten stand außerhalb des
/// Schirms, die Hülle ohne jede Tiefe.
///
/// - `klein`: für 40 Punkt — 2 nach unten, weich 6, Schwarz 35 %.
/// - `gross`: nach Übergabe §6 — 0 / 24 / 60 / −22, Schwarz 50 %, auf 338.
///   Dezenter als die Übergabe (24.09.: „etwas zu stark"); vorher
///   30 nach unten und 75 %.
///
/// Beide gerechnet auf ein Quadrat von 100 mit dem Überstand
/// ``ueberstand``; der Versatz liegt im Bild.
struct Huellenschatten: View {
    enum Art { case klein, gross }
    let art: Art

    /// Wie viel größer das Bild ist als die Hülle, deren Schatten es trägt.
    static let ueberstand: CGFloat = 1.8
    /// Die feine Kante der großen Hülle.
    static let kante = Color.white.opacity(0.07)

    var body: some View {
        Image(uiImage: art == .klein ? Self.klein : Self.gross)
            .resizable()
            .scaleEffect(Self.ueberstand)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 40 Punkt: y 2, Weichzeichner 6 (σ 3), 35 %.
    static let klein = bild(ecke: 20, y: 5, sigma: 7.5, spreizung: 0, deckung: 0.35)
    /// 338 Punkt: y 24, Weichzeichner 60 (σ 30), Spreizung −22, 50 %.
    static let gross = bild(ecke: 16 / 338 * 100, y: 24 / 338 * 100, sigma: 30 / 338 * 100,
                            spreizung: -22 / 338 * 100, deckung: 0.5)

    /// Der Schatten eines Quadrats von 100 in einem Bild von 100 ×
    /// ``ueberstand``. Gezeichnet wird die Form weit links außerhalb und nur
    /// ihr Schatten ins Bild geschoben — so steht die Form selbst nicht im
    /// Bild, und der Versatz nach unten hängt nicht davon ab, wie ein
    /// gespiegelter Kontext Schattenversätze deutet. Versatz und
    /// Weichzeichner gelten in Punkten des Bilds (UIKit rechnet die
    /// Auflösung selbst ein).
    static func bild(ecke: CGFloat, y: CGFloat, sigma: CGFloat, spreizung: CGFloat, deckung: CGFloat) -> UIImage {
        let skala: CGFloat = 3
        let kante = 100 * ueberstand
        let format = UIGraphicsImageRendererFormat()
        format.scale = skala
        return UIGraphicsImageRenderer(size: CGSize(width: kante, height: kante), format: format).image { k in
            let c = k.cgContext
            let rand = (kante - 100) / 2
            let quadrat = CGRect(x: rand, y: rand + y, width: 100, height: 100).insetBy(dx: -spreizung, dy: -spreizung)
            let weit: CGFloat = 1000
            let form = UIBezierPath(roundedRect: quadrat.offsetBy(dx: -weit, dy: 0),
                                    cornerRadius: max(ecke - spreizung, 0))
            c.setShadow(offset: CGSize(width: weit, height: 0), blur: 2 * sigma,
                        color: UIColor.black.withAlphaComponent(deckung).cgColor)
            UIColor.black.setFill()
            form.fill()
        }
    }
}

/// **Der Schatten der Pille — ebenfalls ein fertiges Bild**, gedehnt auf
/// jede Größe (Ränder fest, Mitte gestreckt), innen ausgespart: die Pille
/// ist leicht durchscheinend, und darunter darf kein Schwarz liegen.
enum Pillenschatten {
    static let rand: CGFloat = 30

    /// 10 nach unten, weich 20, Schwarz 80 %, innen ausgespart — so, wie er
    /// bisher stand. Die Form wird außerhalb gezeichnet und nur ihr Schatten
    /// hereingeschoben; so ist der Versatz eindeutig nach unten.
    static let bild: UIImage = {
        let skala: CGFloat = 3
        let format = UIGraphicsImageRendererFormat()
        format.scale = skala
        let groesse = CGSize(width: 2 * rand + 60, height: 2 * rand + 60)
        let bild = UIGraphicsImageRenderer(size: groesse, format: format).image { k in
            let c = k.cgContext
            let flaeche = CGRect(x: rand, y: rand, width: 60, height: 60)
            let weit: CGFloat = 1000
            let form = UIBezierPath(roundedRect: flaeche.offsetBy(dx: -weit, dy: 10), cornerRadius: Musikstil.eckeMini)
            c.setShadow(offset: CGSize(width: weit, height: 0), blur: 20,
                        color: UIColor.black.withAlphaComponent(0.8).cgColor)
            UIColor.black.setFill()
            form.fill()
            // Unter der Pille kein Schwarz: sie ist durchscheinend.
            c.setShadow(offset: .zero, blur: 0, color: nil)
            c.setBlendMode(.clear)
            UIBezierPath(roundedRect: flaeche, cornerRadius: Musikstil.eckeMini).fill()
        }
        let kappe = rand + 14
        return bild.resizableImage(withCapInsets: UIEdgeInsets(top: kappe, left: kappe, bottom: kappe, right: kappe),
                                   resizingMode: .stretch)
    }()

    /// Hinter eine Fläche der Größe `groesse` gelegt.
    static func ansicht(_ groesse: CGSize) -> some View {
        Image(uiImage: bild)
            .resizable(capInsets: EdgeInsets(top: rand + 14, leading: rand + 14, bottom: rand + 14, trailing: rand + 14),
                       resizingMode: .stretch)
            .frame(width: groesse.width + 2 * rand, height: groesse.height + 2 * rand)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// **Das Glas unter der Pille**: gleichmäßig unscharf, darüber Schwarz
/// (``Huellenton/glasabdunklung``) — daher kommt der Kontrast für die
/// weiße Schrift, nicht aus der Deckkraft des Verlaufs. In Pille und Karte
/// derselbe Baustein.
struct Pillenglas: View {
    var body: some View {
        ZStack {
            Unschaerfe()
            Color.black.opacity(Huellenton.glasabdunklung)
        }
        .allowsHitTesting(false)
    }
}

/// **Die Linie unten in der Pille**, 3 hoch, bündig unten: weiß auf weiß
/// 30 %, je Bild aus der Stellenuhr (``Spieler/anzeigestelle()``). In der
/// Pille und in der Karte dieselbe.
struct Pillenspur: View {
    /// Die Pille unter dem offenen Blatt steht still.
    var sichtbar = true
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        let spieler = modell.spieler
        Laufanzeige(spieler: spieler, sichtbar: sichtbar) { stelle in
            Fortschrittsspur(anteil: spieler.dauer.map { $0 > 0 ? stelle / $0 : 0 } ?? 0, hoehe: 3)
        }
        .frame(height: 3)
    }
}

// MARK: - Künstler*innen zur Wahl

/// **Bei mehreren Künstler*innen erst die Wahl** (24.09., wie Apple
/// Music): ein kleines Blatt wie die anderen — kein Glas —, je Zeile das
/// runde Bild und der Name. Ein Tipp schließt beide Blätter und öffnet die
/// Seite im Bereich, in dem man ist.
///
/// Das Lied kennt nur den ersten Künstler mit Kennung; die anderen werden
/// über die Suche nach ihrem Namen gefunden (genau dieser Name). Wer so
/// nicht zu finden ist, steht ohne Bild und nicht antippbar da.
struct Kuenstlerwahlebene: View {
    @Environment(Musikmodell.self) private var modell
    @Environment(Blattstand.self) private var stand
    /// Beim Schließen ist die Wahl schon leer, die Karte fährt aber noch
    /// hinaus — so lange steht hier, was sie zeigte.
    @State private var zuletzt: Lied?
    @State private var offen = false

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .musikblatt(offen: Binding(get: { offen },
                                       set: { if !$0 { offen = false; stand.kuenstlerwahl = nil } })) {
                if let lied = zuletzt {
                    Kuenstlerwahl(lied: lied) { kuenstler in
                        offen = false
                        stand.kuenstlerwahl = nil
                        modell.oeffnenAusBlatt(.kuenstler(kuenstler))
                    } abbrechen: {
                        offen = false
                        stand.kuenstlerwahl = nil
                    }
                    .id(lied.id)
                }
            }
            .onChange(of: stand.kuenstlerwahl?.id) { _, neu in
                guard neu != nil, let lied = stand.kuenstlerwahl else {
                    offen = false
                    return
                }
                zuletzt = lied
                // Wie beim Handlungsblatt: erst der Inhalt, einen Takt
                // später das Blatt — sonst fährt der Inhalt nicht mit.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(30))
                    offen = stand.kuenstlerwahl != nil
                }
            }
    }
}

private struct Kuenstlerwahl: View {
    let lied: Lied
    let waehlen: (Kuenstler) -> Void
    let abbrechen: () -> Void
    @Environment(Musikmodell.self) private var modell
    @State private var gefunden: [String: Kuenstler] = [:]
    @State private var gesucht = false

    var body: some View {
        let namen = lied.kuenstlernamen
        VStack(alignment: .leading, spacing: 0) {
            Text("Künstler*innen")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.136)
                .foregroundStyle(Stil.schrift)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Musikstil.rand)
                .padding(.top, 5)
                .padding(.bottom, 14)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(namen.enumerated()), id: \.offset) { i, name in
                if i > 0 { Blattlinie() }
                let kuenstler = gefunden[name]
                Button {
                    if let kuenstler { waehlen(kuenstler) }
                } label: {
                    HStack(spacing: 14) {
                        Group {
                            if let bild = kuenstler?.bild {
                                Netzhuelle(adresse: modell.bildadresse(bild, punkte: 44), zeichengroesse: 17)
                            } else if gesucht {
                                ZStack {
                                    Stil.flaeche
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(Stil.schriftSehrLeise)
                                }
                            } else {
                                Ladefeld(ecke: 22)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        Text(verbatim: name)
                            .font(.system(size: 17))
                            .foregroundStyle(kuenstler == nil && gesucht ? Stil.schriftLeise : Stil.schrift)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Musikstil.rand)
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(Zeilendruck.randbreit)
                .disabled(kuenstler == nil)
            }

            Blattlinie()
            Button(action: abbrechen) {
                Text("Abbrechen")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Stil.schriftLeise)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(Zeilendruck.randbreit)
        }
        .task(id: lied.id) { await suchen(namen) }
    }

    /// Je Name die Suche, genau dieser Name gewinnt. Der erste Künstler
    /// hat seine Kennung schon im Lied.
    private func suchen(_ namen: [String]) async {
        guard let quelle = modell.quelle else {
            gesucht = true
            return
        }
        await withTaskGroup(of: (String, Kuenstler?).self) { gruppe in
            for name in namen {
                gruppe.addTask {
                    let treffer = try? await quelle.suche(name).kuenstler
                    let genau = treffer?.first {
                        $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                    }
                    return (name, genau)
                }
            }
            for await (name, kuenstler) in gruppe {
                if let kuenstler {
                    gefunden[name] = kuenstler
                } else if name == lied.ersterKuenstler, let id = lied.kuenstlerID {
                    gefunden[name] = Kuenstler(id: id, name: name)
                }
            }
        }
        gesucht = true
    }
}

// MARK: - Die zwei Lagen

/// **Die große Lage**: Hülle, Titelzeile, darunter fest Spur, Steuerung und
/// Aktionsreihe — von unten gebaut (24.09.: „alles weiter nach unten,
/// wie bei Spotify"). Hülle, Titel und Künstler stehen hier nur als
/// Platzhalter: gezeichnet werden sie wandernd (``Wiedergabeblatt``), hier
/// wird ihre Stelle gemessen.
private struct Grosslage: View {
    let lied: Lied
    let breite: CGFloat
    let hoehe: CGFloat
    let unten: CGFloat
    let q: CGFloat
    let auftritt: Bool
    let messrunde: Int
    @Binding var lagen: Blattlagen
    @Binding var ansicht: Wiedergabeblatt.Blattansicht
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        // Was außer der Hülle Platz braucht: Griff, die kleinsten Lücken,
        // Titel, Spur, Steuerung, Aktionen und der Rand unten.
        let fest: CGFloat = 13 + 12 + 20 + 50 + 26 + 27 + 22 + Steuerung.hoehe + 24 + 44 + Wiedergabemass.unten(unten)
        let kante = max(160, min(breite - 52, hoehe - fest))

        VStack(spacing: 0) {
            Griff()
            Spacer(minLength: 12)

            Color.clear
                .frame(width: kante, height: kante)
                .messen(messrunde) { lagen.huelleGross = $0 }

            Spacer(minLength: 20)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: lied.titel)
                        .font(Musikstil.blattTitel)
                        .tracking(Musikstil.sperrungBlattTitel)
                        .lineLimit(1)
                        .hidden()
                        .messen(messrunde) { lagen.titelGross = $0 }
                    if let k = lied.kuenstlerzeile {
                        Text(verbatim: k)
                            .font(Musikstil.zeile)
                            .lineLimit(1)
                            .hidden()
                            .messen(messrunde) { lagen.zeileGross = $0 }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

                HStack(spacing: 4) {
                    Favoritknopf(lied: lied)
                    Blattmenue(lied: lied)
                }
                // Die Zeichen, nicht die Ziele, stehen an der Kante der Spur.
                .padding(.trailing, -(44 - Blattknopf.zeichen) / 2)
                .modifier(Auftritt(da: auftritt, stufe: 0))
                .opacity(1 - q)
                .allowsHitTesting(q < 0.5)
                .accessibilityHidden(q > 0.5)
            }
            .frame(minHeight: 50)
            .padding(.horizontal, 26)

            // **Steht in beiden Lagen an derselben Stelle.**
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Zeitspur()
                    Zeitzeile(plakette: true)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 26)
                .padding(.top, 26)
                .modifier(Auftritt(da: auftritt, stufe: 1))

                Steuerung()
                    .padding(.horizontal, 26)
                    .padding(.top, 22)
                    .modifier(Auftritt(da: auftritt, stufe: 2))

                Aktionsreihe(ansicht: $ansicht)
                    .modifier(Auftritt(da: auftritt, stufe: 3))
                    .padding(.horizontal, 12)
                    .padding(.top, 24)
                    .padding(.bottom, Wiedergabemass.unten(unten))
            }
            // Hängt nicht am Lied — ohne neue Runde, sonst würden Spur und
            // Steuerung nach jeder Bewegung neu gebaut.
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Wiedergabeblatt.raum)).minY } action: {
                lagen.untenOben = $0
            }
        }
        .onAppear { modell.spieler.ausgabeAktualisieren() }
    }
}

/// **Gestaffelt von leicht unten** (24.09.: beim Öffnen kamen die
/// Teile gar nicht herein). Titelzeile, Spur, Steuerung und Aktionsreihe
/// fahren mit dem Blatt herauf und setzen sich je 35 ms nacheinander aus
/// 18 Punkt darunter. Beim Schließen nichts — sie fahren mit dem Blatt
/// hinaus; zurückgesetzt wird, wenn die Bühne weg ist. Bewegung reduzieren:
/// ohne.
private struct Auftritt: ViewModifier {
    let da: Bool
    let stufe: Int

    func body(content: Content) -> some View {
        content
            .offset(y: da || Musikstil.bewegungReduziert ? 0 : 18)
            .animation(da ? .spring(response: 0.5, dampingFraction: 0.86).delay(0.04 + 0.035 * Double(stufe)) : nil,
                       value: da)
    }
}

/// Maße, die beide Lagen teilen.
enum Wiedergabemass {
    /// Unter der Aktionsreihe: der Home-Indikator und ein gewöhnlicher Rand.
    static func unten(_ sicher: CGFloat) -> CGFloat { max(sicher, 20) + 14 }
}

/// **Die Kopflage über Liedtext und Schlange**: Hülle 48 links oben, Titel
/// 15, Künstler 12, rechts „Mehr" — darunter der Text oder die Liste, bis
/// an die Spur. Am Kopf zieht man das Blatt zu; darunter scrollt der Inhalt.
private struct Kopflage<Zug: Gesture>: View {
    let lied: Lied
    let hoehe: CGFloat
    let q: CGFloat
    let inhalt: Wiedergabeblatt.Blattansicht
    let messrunde: Int
    @Binding var lagen: Blattlagen
    let ziehen: Zug

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Nur für den Platz: den Griff zeichnet die große Lage, die
                // darunter immer steht — zweimal übereinander wäre er doppelt hell.
                Griff().hidden()
                HStack(spacing: 12) {
                    Color.clear
                        .frame(width: 48, height: 48)
                        .messen(messrunde) { lagen.huelleKopf = $0 }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: lied.titel)
                            .font(Musikstil.zeile)
                            .lineLimit(1)
                            .hidden()
                            .messen(messrunde) { lagen.titelKopf = $0 }
                        if let k = lied.kuenstlerzeile {
                            Text(verbatim: k)
                                .font(Musikstil.angabe)
                                .lineLimit(1)
                                .hidden()
                                .messen(messrunde) { lagen.zeileKopf = $0 }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                    Blattmenue(lied: lied)
                        .opacity(q)
                        .accessibilityHidden(q < 0.5)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 6)
            }
            .contentShape(Rectangle())
            .gesture(ziehen)
            .allowsHitTesting(q > 0.5)

            // Von leicht unten herein, zurück genau so.
            Nebeninhalt(ansicht: inhalt, sichtbar: q > 0)
                .frame(maxHeight: .infinity)
                .opacity(q)
                .offset(y: (1 - q) * 24)
                .allowsHitTesting(q > 0.5)
                .accessibilityHidden(q < 0.5)

            Color.clear
                .frame(height: max(0, hoehe - lagen.untenOben))
                .allowsHitTesting(false)
        }
    }
}

/// Der Liedtext oder die Schlange — oben und unten laufen sie weich aus,
/// unten in die Spur hinein.
///
/// **Beide stehen immer fertig im Baum** (24.09.: der Wechsel fühlte
/// sich manchmal wie 30–60 Hz an). Vorher wurde die Schlange oder der
/// Liedtext im ersten Bild des Wechsels gebaut — Liste, Zeilen, Sprung an
/// die aktuelle Zeile —, während der Kopf schon lief. Jetzt wechselt nur
/// die Deckkraft; was verborgen ist, hält seinen Takt an (Pegel, Zeile).
private struct Nebeninhalt: View {
    let ansicht: Wiedergabeblatt.Blattansicht
    /// Der Kopf ist wenigstens ein Stück herein.
    let sichtbar: Bool
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        let liedtext = ansicht == .liedtext
        ZStack {
            if let lied = modell.spieler.aktuell {
                Liedtextansicht(lied: lied, gemerkt: modell.gemerkterLiedtext(lied),
                                stelle: modell.spieler.stelle(), aktiv: sichtbar && liedtext)
                    .opacity(liedtext ? 1 : 0)
                    .allowsHitTesting(liedtext)
                    .accessibilityHidden(!liedtext)
            }
            Warteschlangenansicht(aktiv: sichtbar && !liedtext)
                .opacity(liedtext ? 0 : 1)
                .allowsHitTesting(!liedtext)
                .accessibilityHidden(liedtext)
        }
        .animation(Musikstil.einblenden, value: ansicht)
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 36)
            }
        }
    }
}

// MARK: - Teile

/// **Herz und „Mehr" neben dem Titel: Zeichen ohne Fläche** (24.09.:
/// zu viele Knöpfe auf einem Haufen). Vorher zwei Symbolknöpfe 48 × 48 auf
/// `flaeche` — zwei Kästen neben dem Titel, dazu fünf Zeichen darunter.
/// Apple Music stellt dort nur Zeichen hin; das Ziel bleibt 44.
enum Blattknopf {
    static let zeichen: CGFloat = 22
}

/// Der Favorit, aktiv in Akzent.
private struct Favoritknopf: View {
    let lied: Lied
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        let an = modell.istFavorit(lied.id, sonst: lied.favorit)
        Button {
            modell.favoritSetzen(.lied(lied.id), id: lied.id, an: !an, lied: lied)
        } label: {
            Symbolbild(zeichen: an ? .herz : .herzUmriss, groesse: Blattknopf.zeichen)
                .foregroundStyle(an ? Stil.akzent : Stil.schrift)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(Druckknopf())
        .accessibilityLabel(Text("Favorit"))
        .accessibilityValue(an ? Text("an") : Text("aus"))
    }
}

/// „Mehr" im Blatt: wohin es von hier aus geht.
private struct Blattmenue: View {
    let lied: Lied
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        Button {
            modell.handlungen = Handlungen.lied(lied, ausBlatt: true, modell)
        } label: {
            Symbolbild(zeichen: .mehr, groesse: Blattknopf.zeichen)
                .foregroundStyle(Stil.schrift)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(Druckknopf())
        .accessibilityLabel(Text("Mehr"))
    }
}

/// **Die Spur**: 4 hoch, runde Enden, weiß 30 %, gespielt weiß, der
/// Griffpunkt immer sichtbar (24.09.) — zum Ziehen. Beim Anfassen ein
/// leichter Ruck, beim Loslassen ein mittlerer (BRAND.md §6).
private struct Zeitspur: View {
    @Environment(Musikmodell.self) private var modell
    @Environment(Zugstelle.self) private var zugstelle
    @Environment(Blattstand.self) private var stand

    /// Der Griffpunkt beim Ziehen; in Ruhe steht er bei 10.
    static let punkt: CGFloat = 16

    var body: some View {
        let spieler = modell.spieler
        let dauer = spieler.dauer ?? 0
        let amZiehen = zugstelle.anteil != nil
        // **Beim Ziehen wie `Zeitregler` im Player**: die Spur wird von 4 auf
        // 6 dicker, und der Punkt wächst von 10 auf 16. Sonst läuft sie je
        // Bild weich (``Laufanzeige``), nicht im Takt der halben Sekunde.
        GeometryReader { g in
            Laufanzeige(spieler: spieler, sichtbar: stand.buehne) { stelle in
                let anteil = zugstelle.anteil ?? (dauer > 0 ? stelle / dauer : 0)
                ZStack(alignment: .leading) {
                    Fortschrittsspur(anteil: anteil, hoehe: amZiehen ? 6 : 4, rund: true)
                    Circle().fill(Stil.schrift).frame(width: Self.punkt, height: Self.punkt)
                        .scaleEffect(amZiehen ? 1 : 10 / Self.punkt)
                        .offset(x: g.size.width * min(max(anteil, 0), 1) - Self.punkt / 2)
                }
            }
                .animation(Musikstil.umschalten, value: amZiehen)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { wert in
                            guard dauer > 0 else { return }
                            if zugstelle.anteil == nil { Musikstil.ruck(.leicht) }
                            zugstelle.anteil = min(max(wert.location.x / max(g.size.width, 1), 0), 1)
                        }
                        .onEnded { _ in
                            if let a = zugstelle.anteil, dauer > 0 {
                                spieler.springe(auf: a * dauer)
                                Musikstil.ruck(.mittel)
                            }
                            zugstelle.anteil = nil
                        }
                )
        }
        .frame(height: 24)
        .padding(.vertical, -10)
        .accessibilityElement()
        .accessibilityLabel(Text("Stelle"))
        // Gesprochen „3 Minuten, 45 Sekunden von 4 Minuten" statt „3:45 / 4:00"
        // — VoiceOver liest Doppelpunkte als Doppelpunkte.
        .accessibilityValue(Text("\(Zeitformat.gesprochen(spieler.position)) von \(Zeitformat.gesprochen(dauer))"))
        .accessibilityAdjustableAction { richtung in
            switch richtung {
            case .increment: spieler.springe(auf: spieler.position + 10)
            case .decrement: spieler.springe(auf: spieler.position - 10)
            @unknown default: break
            }
        }
    }
}

/// Wohin gerade gezogen wird — die Zeiten darunter zeigen es mit.
@MainActor
@Observable
final class Zugstelle {
    var anteil: Double?
}

/// Links die gelaufene Zeit, rechts der Rest mit Minuszeichen, in der
/// Wiedergabe mittig die Plakette (22 hoch, 12).
private struct Zeitzeile: View {
    let plakette: Bool
    @Environment(Musikmodell.self) private var modell
    @Environment(Zugstelle.self) private var zugstelle
    @Environment(Blattstand.self) private var stand

    var body: some View {
        let spieler = modell.spieler
        let dauer = spieler.dauer ?? 0
        Laufanzeige(spieler: spieler, takt: 0.25, sichtbar: stand.buehne) { lauf in
            zeile(spieler, dauer: dauer, stelle: zugstelle.anteil.map { $0 * dauer } ?? lauf)
        }
        .font(Musikstil.angabe)
        .monospacedDigit()
        .foregroundStyle(Stil.schriftSehrLeise)
        .accessibilityHidden(true)
    }

    private func zeile(_ spieler: Spieler, dauer: TimeInterval, stelle: TimeInterval) -> some View {
        HStack {
            Text(verbatim: Zeitformat.dauer(stelle))
                .frame(maxWidth: .infinity, alignment: .leading)
            // **Kein „Läuft auf …" mehr** (25.09.): das Ausgabezeichen
            // in Akzent und der Gerätename in der Aktionsreihe sagen es schon.
            if plakette, modell.einstellungen.technischeDaten,
               let weg = spieler.weg, let angabe = Abspielregel.angabe(weg) {
                Plakette(text: weg.art == .direkt ? String(localized: "Direct Play · \(angabe)")
                                                  : String(localized: "Transkodiert · \(angabe)"),
                         akzent: weg.art == .direkt, hoehe: 22, grad: 12)
                    .layoutPriority(1)
            }
            Text(verbatim: dauer > 0 ? Zeitformat.rest(max(0, dauer - stelle)) : "")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // Die Zeile ist gleich hoch, ob die Plakette steht oder nicht (etwa
        // wenn es auf einem anderen Gerät läuft) — nichts darunter springt.
        .frame(minHeight: plakette && modell.einstellungen.technischeDaten ? 22 : nil)
    }
}


/// **Zufall · Zurück · Abspielen · Weiter · Wiederholen** — nach Apple
/// Music, nicht nach Spotify (24.09.: der runde weiße Knopf mit Zufall
/// und Wiederholen daneben war Spotify eins zu eins).
///
/// Die drei in der Mitte sind **reine weiße Zeichen ohne Fläche**, Abspielen
/// deutlich größer: 30 · **54** · 30. Zufall und Wiederholen stehen kleiner
/// außen (19), aus in `schriftLeise`, an in `akzent` (E2). Gedrückt wie
/// überall (``Druckknopf``: 0,97 und 85 %).
///
/// **Aufgeräumt** (24.09.: „zu viele auf einem Haufen"): vorher
/// 34 · 46 · 34 mit 21 außen, alle weiß — fünf fast gleich laute Zeichen.
/// Jetzt trägt Abspielen die Reihe, die Nachbarn treten zurück, und die
/// Umschalter sagen nur noch, wenn sie an sind.
private struct Steuerung: View {
    @Environment(Musikmodell.self) private var modell

    /// Die Höhe der Reihe — die große Lage rechnet damit die Hülle aus.
    static let hoehe: CGFloat = 64

    static let seite: CGFloat = 30
    static let mitte: CGFloat = 54
    static let umschalter: CGFloat = 19

    /// **Das Dreieck optisch mittig.** Im Pfad steht sein Umriss 1,6 von 24
    /// rechts der Mitte, sein Schwerpunkt 0,6 links davon. Das Auge nimmt
    /// die Mitte dazwischen — gut 1,1 Einheiten rechts der Umrissmitte. Der
    /// Pfad steht also 0,5 Einheiten zu weit rechts; so viel zurück. Pause
    /// ist symmetrisch und bleibt, wo es ist. Vorher saß das Dreieck im
    /// runden Knopf zwei Punkte weiter rechts und stand sichtbar schief.
    static func dreieckVersatz(_ groesse: CGFloat) -> CGFloat { -0.5 / 24 * groesse }

    var body: some View {
        let spieler = modell.spieler
        let schlange = spieler.schlange
        HStack(spacing: 0) {
            Button { spieler.mischen(!schlange.gemischt) } label: {
                Symbolbild(zeichen: .zufall, groesse: Self.umschalter)
                    .foregroundStyle(schlange.gemischt ? Stil.akzent : Stil.schriftLeise)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(Druckknopf())
            .accessibilityLabel(Text("Zufall"))
            .accessibilityValue(schlange.gemischt ? Text("an") : Text("aus"))

            Spacer(minLength: 0)

            Button { spieler.zurueck() } label: {
                Symbolbild(zeichen: .zurueck, groesse: Self.seite)
                    .frame(width: 60, height: Self.hoehe)
                    .contentShape(Rectangle())
            }
            .buttonStyle(Druckknopf())
            .accessibilityLabel(Text("Voriges Lied"))

            Spacer(minLength: 0)

            Button { spieler.umschalten() } label: {
                ZStack {
                    if spieler.puffert && spieler.spielt {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Stil.schrift)
                    } else {
                        Symbolbild(zeichen: spieler.spielt ? .pause : .abspielen, groesse: Self.mitte)
                            .offset(x: spieler.spielt ? 0 : Self.dreieckVersatz(Self.mitte))
                            .animation(Musikstil.umschalten, value: spieler.spielt)
                    }
                }
                .frame(width: 84, height: Self.hoehe)
                .contentShape(Rectangle())
            }
            .buttonStyle(Druckknopf())
            .accessibilityLabel(spieler.spielt ? Text("Pause") : Text("Abspielen"))

            Spacer(minLength: 0)

            Button { spieler.weiter() } label: {
                Symbolbild(zeichen: .weiter, groesse: Self.seite)
                    .foregroundStyle(schlange.naechster == nil ? Stil.schriftSehrLeise : Stil.schrift)
                    .frame(width: 60, height: Self.hoehe)
                    .contentShape(Rectangle())
            }
            .buttonStyle(Druckknopf())
            .disabled(schlange.naechster == nil)
            .accessibilityLabel(Text("Nächstes Lied"))

            Spacer(minLength: 0)

            Button { spieler.wiederholungWeiterschalten() } label: {
                Symbolbild(zeichen: schlange.wiederholung == .eines ? .wiederholenEines : .wiederholen,
                           groesse: Self.umschalter)
                    .foregroundStyle(schlange.wiederholung == .aus ? Stil.schriftLeise : Stil.akzent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(Druckknopf())
            .accessibilityLabel(Text("Wiederholen"))
            .accessibilityValue(wiederholung(schlange.wiederholung))
        }
        .frame(height: Self.hoehe)
        // Die Umschalter stehen mit ihrem Zeichen, nicht mit ihrem Ziel, an
        // der Kante der Spur.
        .padding(.horizontal, -(44 - Self.umschalter) / 2)
        .foregroundStyle(Stil.schrift)
    }

    private func wiederholung(_ w: Warteschlange.Wiederholung) -> Text {
        switch w {
        case .aus: Text("aus")
        case .alles: Text("Alle Lieder")
        case .eines: Text("Dieses Lied")
        }
    }
}

/// **Liedtext · Ausgabe · Als Nächstes** — drei gleiche Felder, die Ausgabe
/// in der Mitte (24.09.). Liedtext und Als Nächstes wechseln nur den
/// oberen Teil des Blatts; ein zweiter Tipp führt zurück.
private struct Aktionsreihe: View {
    @Binding var ansicht: Wiedergabeblatt.Blattansicht
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        let spieler = modell.spieler
        HStack(spacing: 0) {
            Aktion(zeichen: .liedtext, titel: Text("Liedtext"), gewaehlt: ansicht == .liedtext) {
                ansicht = ansicht == .liedtext ? .wiedergabe : .liedtext
            }
            Ausgabeaktion(name: spieler.fern?.name ?? spieler.ausgabename, fern: spieler.fern != nil)
            Aktion(zeichen: .alsNaechstes, titel: Text("Als Nächstes"), gewaehlt: ansicht == .alsNaechstes) {
                ansicht = ansicht == .alsNaechstes ? .wiedergabe : .alsNaechstes
            }
        }
    }
}

/// **Ausgabe**: der Name des Geräts, auf dem es läuft — ein Tipp öffnet
/// „Abspielen auf" (``Geraeteebene``) mit diesem iPhone, den anderen
/// Geräten und ganz unten Apples AirPlay-Auswahl. Läuft es auf einem anderen
/// Gerät, steht das Zeichen in `akzent`.
private struct Ausgabeaktion: View {
    let name: String
    let fern: Bool
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        Button { modell.fern.blattOffen = true } label: {
            Aktionsinhalt(zeichen: .ausgabe, titel: Text(verbatim: name), aktiv: fern)
        }
        .buttonStyle(Druckknopf())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Ausgabe: \(name)"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Liedtext

/// **Der Liedtext**: Zeilen 28 Bold, 18 Abstand, 26 Innenabstand — aktuelle
/// weiß, kommende `#989898`, gesungene `#5C5C5C`. Die aktuelle Zeile steht im
/// oberen Drittel; ein Tipp auf eine Zeile springt dorthin. Scrollt man
/// selbst, folgt die Ansicht für ein paar Sekunden nicht.
private struct Liedtextansicht: View {
    let lied: Lied
    /// Zu sehen — sonst sieht sie nur selten nach der Zeile und springt
    /// ohne Bewegung dorthin.
    let aktiv: Bool
    @Environment(Musikmodell.self) private var modell
    @State private var text: Liedtext?
    @State private var geladen = false
    /// Der Server hat nicht geantwortet — das ist nicht „kein Liedtext".
    /// Vorher schluckte ein `try?` den Fehler, und danach stand immer „Zu
    /// diesem Lied gibt es keinen Liedtext." (wie `Stoerhinweis` gegen
    /// `Leerzustand` im Player).
    @State private var stoerung: Stoerung?
    /// Zählt „Erneut versuchen" — ein neuer Wert lädt neu.
    @State private var versuch = 0
    @State private var selbstGescrollt: Date?
    /// Die aktuelle Zeile — nur neu gesetzt, wenn sie wechselt, damit die
    /// Liste nicht zehnmal in der Sekunde neu gezeichnet wird.
    @State private var aktuelle: Int?

    /// **Was schon geholt ist, steht im ersten Bild.** Vorher kam der
    /// gemerkte Text erst über `.task` — ein Bild lang standen die
    /// Ladefelder da (gemessen: achtmal gezeichnet), und die aktuelle Zeile
    /// scrollte danach sichtbar an ihren Platz.
    init(lied: Lied, gemerkt: Liedtext??, stelle: TimeInterval, aktiv: Bool) {
        self.lied = lied
        self.aktiv = aktiv
        if let gemerkt {
            _text = State(initialValue: gemerkt)
            _geladen = State(initialValue: true)
            _aktuelle = State(initialValue: gemerkt.flatMap { $0.getaktet ? $0.aktuelleZeile(zu: stelle) : nil })
        }
    }

    var body: some View {
        Group {
            if let text, !text.istLeer {
                if text.getaktet {
                    getaktet(text)
                        .task(id: Takt(text: text, aktiv: aktiv)) {
                            while !Task.isCancelled {
                                let neu = text.aktuelleZeile(zu: modell.spieler.stelle())
                                if neu != aktuelle { aktuelle = neu }
                                try? await Task.sleep(for: .milliseconds(aktiv ? 100 : 500))
                            }
                        }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(text.zeilen.enumerated()), id: \.offset) { _, zeile in
                                Text(verbatim: zeile.istPause ? " " : zeile.text)
                                    .font(Musikstil.seitentitel)
                                    .lineSpacing(Musikstil.liedtextZeilenabstand)
                                    .tracking(Musikstil.sperrungSeitentitel)
                                    .foregroundStyle(Stil.schrift)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 26)
                        .padding(.top, 26)
                        .padding(.bottom, 48)
                    }
                    .scrollIndicators(.hidden)
                }
            } else if let stoerung {
                VStack {
                    Spacer(minLength: 0)
                    Stoerhinweis(stoerung: stoerung) { versuch += 1 }
                    Spacer(minLength: 0)
                    Color.clear.frame(height: 220)
                }
                .frame(maxWidth: .infinity)
            } else if geladen {
                VStack {
                    Spacer(minLength: 0)
                    Text("Zu diesem Lied gibt es keinen Liedtext.")
                        .font(.system(size: 15))
                        .foregroundStyle(Stil.schriftLeise)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                    Spacer(minLength: 0)
                    Color.clear.frame(height: 220)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(0 ..< 4, id: \.self) { i in
                        Ladefeld(ecke: 6).frame(width: [260, 200, 280, 180][i], height: 28)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.top, 30)
            }
        }
        // **Einmal je Lied geholt**: der Text liegt im Modell
        // (``Musikmodell/liedtext(_:)``), ein zweites Öffnen fragt den
        // Server nicht noch einmal.
        .task(id: Anlauf(lied: lied.id, versuch: versuch)) {
            if let gemerkt = modell.gemerkterLiedtext(lied) {
                text = gemerkt
                stoerung = nil
                geladen = true
                return
            }
            geladen = false
            text = nil
            stoerung = nil
            do {
                let neu = try await modell.liedtext(lied)
                guard !Task.isCancelled else { return }
                text = neu
                geladen = true
            } catch {
                guard !Task.isCancelled else { return }
                stoerung = Stoerung(error)
            }
        }
    }

    private struct Anlauf: Equatable {
        let lied: String
        let versuch: Int
    }

    private struct Takt: Equatable {
        let text: Liedtext
        let aktiv: Bool
    }

    private func getaktet(_ text: Liedtext) -> some View {
        ScrollViewReader { leser in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(text.zeilen.enumerated()), id: \.offset) { i, zeile in
                        Button {
                            if let ziel = text.sprungziel(i) {
                                modell.spieler.springe(auf: ziel)
                                selbstGescrollt = nil
                            }
                        } label: {
                            Text(verbatim: zeile.istPause ? "…" : zeile.text)
                                .font(Musikstil.seitentitel)
                                .lineSpacing(Musikstil.liedtextZeilenabstand)
                                .tracking(Musikstil.sperrungSeitentitel)
                                .foregroundStyle(farbe(i, aktuelle))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(Druckknopf())
                        .id(i)
                    }
                }
                // Die Hervorhebung wandert weich von Zeile zu Zeile.
                .animation(Musikstil.bewegungReduziert || !aktiv ? nil : .easeOut(duration: 0.3), value: aktuelle)
                .padding(.horizontal, 26)
                .padding(.top, 26)
                .padding(.bottom, 64)
            }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, neu in
                if neu == .interacting { selbstGescrollt = Date() }
            }
            .onChange(of: aktuelle) { _, neu in
                guard let neu else { return }
                if let selbst = selbstGescrollt, Date().timeIntervalSince(selbst) < 4 { return }
                withAnimation(Musikstil.bewegungReduziert || !aktiv ? nil : .smooth(duration: 0.45)) {
                    leser.scrollTo(neu, anchor: UnitPoint(x: 0, y: 0.28))
                }
            }
            .onAppear {
                if let aktuelle { leser.scrollTo(aktuelle, anchor: UnitPoint(x: 0, y: 0.28)) }
            }
        }
    }

    private func farbe(_ i: Int, _ aktuelle: Int?) -> Color {
        guard let aktuelle else { return Stil.schriftSehrLeise }
        if i == aktuelle { return Stil.schrift }
        return i < aktuelle ? Musikstil.gesungen : Stil.schriftSehrLeise
    }
}

// MARK: - Als Nächstes

/// **Die Schlange** im Stil der Liedliste: das laufende Lied oben mit
/// Pegel, darunter was kommt. Tippen springt dorthin; lange drücken bietet
/// Vorziehen und Herausnehmen.
private struct Warteschlangenansicht: View {
    /// Zu sehen — sonst steht der Pegel der laufenden Zeile still.
    let aktiv: Bool
    @Environment(Musikmodell.self) private var modell

    var body: some View {
        let spieler = modell.spieler
        let kommende = spieler.schlange.kommende
        ScrollView {
            // Lazy: eine Schlange mit 500 Liedern baute sonst alle Zeilen
            // auf einmal, auch die, die niemand sieht.
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Reihentitel(text: "Als Nächstes")
                    Kapsel(text: "Zufall", an: spieler.schlange.gemischt, glas: true) {
                        spieler.mischen(!spieler.schlange.gemischt)
                    }
                }
                .padding(.bottom, 10)

                if let laufend = spieler.schlange.aktuell {
                    Liedzeile(nummer: nil, titel: laufend.lied.titel, dauer: laufend.lied.dauer,
                              laeuft: true, spielt: spieler.spielt && aktiv)
                }
                ForEach(Array(kommende.enumerated()), id: \.element.id) { i, eintrag in
                    Button { if modell.frei { spieler.springe(zuEintrag: eintrag.id) } } label: {
                        Liedzeile(nummer: i + 1, titel: eintrag.lied.titel, dauer: eintrag.lied.dauer)
                    }
                    // Gedrückt wie die laufende Zeile: Weiß, Ecke der Pille.
                    .buttonStyle(Zeilendruck())
                    .langerDruck { schlangenhandlungen(eintrag, stelle: i) }
                }
                if kommende.isEmpty {
                    Text("Danach kommt nichts mehr.")
                        .font(.system(size: 15))
                        .foregroundStyle(Stil.schriftSehrLeise)
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
    }

    private func schlangenhandlungen(_ eintrag: Warteschlange.Eintrag, stelle i: Int) -> Handlungsliste {
        let spieler = modell.spieler
        var liste: [Handlung] = []
        if i > 0 {
            liste.append(Handlung(text: String(localized: "Als Nächstes spielen"),
                                  symbol: "text.line.first.and.arrowtriangle.forward") {
                spieler.verschieben(eintrag.id, nach: 0)
            })
        }
        liste.append(Handlung(text: String(localized: "Zu Playlist hinzufügen"), symbol: "text.badge.plus") {
            modell.zuPlaylist([eintrag.lied])
        })
        liste.append(Handlung(text: String(localized: "Aus der Schlange nehmen"), symbol: "minus.circle",
                              warnend: true) { spieler.entfernen(eintrag.id) })
        return Handlungsliste(titel: eintrag.lied.titel, handlungen: liste)
    }
}
