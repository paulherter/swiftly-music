import MusikKit
import SwiftUI

/// **Der Mini-Player direkt über der Leiste** (Übergabe §5).
///
/// 58 hoch, Ecke 14 (``Musikstil/eckeMini``), Schatten. Hülle 40 mit
/// kleinem, weichem Schatten (``Huellenschatten``), Titel 15 Semibold,
/// Künstler 12; rechts Ausgabe, Herz und Abspielen in 44er-Zielen ohne
/// Fläche. Fortschritt 3 hoch bündig unten, weiß, je Bild (``Pillenspur``).
///
/// **Die drei Zeichen optisch gleich groß, eng und gleichmäßig** (25.09.: Abspielen wirkte groß, Herz und „Abspielen auf" zu klein, der
/// Abstand zu groß, „random"). Das Dreieck ist gefüllt, die beiden anderen
/// nur Strich — bei gleicher Größe wirkte es schwerer. Gemessen in Tinte
/// und Kasten: Abspielen 22 (12,1 × 15,0, 106 pt²), Ausgabe 20 → 22
/// (14,5 × 15,9, 108 pt²), Herz 21 → 24 (17,0 × 16,2 — ein Umriss braucht
/// den größeren Kasten für dasselbe Gewicht). Die Mitten stehen 40 auseinander
/// statt 56; die 44er-Ziele liegen dafür 4 Punkt übereinander.
///
/// **Ausgabe statt Weiter** (24.09., wie Spotify): „Abspielen auf"
/// öffnet das Geräteblatt direkt, ohne das Wiedergabeblatt; Weiter liegt
/// im Blatt und im seitlichen Wisch. Abspielen steht außen, unter dem
/// Daumen. **Läuft es auf einem anderen Gerät** (Connect oder Sonos), steht
/// das Zeichen in Akzent, der Wechsel blendet weich. Eine eigene Zeile
/// „Läuft auf …" gibt es nicht mehr (25.09.): das Zeichen und der
/// Gerätename darunter im Blatt sagen es schon.
///
/// **Die Mitten der drei Zeichen auf einer Linie** (25.09.: das Herz
/// stand tiefer als „Abspielen auf"). Gemessen in Tinte, Mitte des Kastens
/// über der Mitte des Ziels: Ausgabe +0,25, Herz +0,81, Abspielen und
/// Pause −0,06 Punkt. Jedes Zeichen rückt um seine Abweichung
/// (``Pillenzeichen``). Das gefüllte Herz war 2 Punkt kleiner als der
/// Umriss (15,0 × 14,2 statt 17,0 × 16,2) — es trägt jetzt denselben Strich.
///
/// **Ein neues Lied rückt nach wie ein Karussell** (``Liedwechsel``, 25.09.: beim Wechsel wurde es kurz dunkel): Hülle, Titel und Künstler
/// schieben als ein Block hinaus, der neue folgt in derselben Bewegung —
/// ohne Blende. Sie laufen am rechten Ende des Blocks unter den Knöpfen
/// aus (``schritt``). Nach einem Wisch beginnt das Karussell dort, wo der
/// Finger die Zeile losließ, mit seinem Tempo (``Anstoss``).
///
/// **Die Fläche ist ein Verlauf aus der Hülle** (24.09.: einfarbig
/// wirkte es „wack", dann: noch zu einfarbig): wie die Glut im Blatt geht
/// er von der Hülle aus, vom Hauptton zum deutlich tieferen Nebenton
/// (``Pillenflaeche``). **Er deckt nur zur Hälfte** (24.09.: „man
/// merkt kaum, dass da überhaupt irgendwas ist") — darunter liegt das Glas
/// (``Pillenglas``): Unschärfe und eine Abdunklung, kein Liquid Glass. Was
/// hinter der Pille liegt, scheint als Unschärfe durch. Jeder Punkt ist für
/// Weiß und die zweite Zeile auf 4,5 : 1 gerechnet, auch wenn hinter dem Glas
/// Weiß stünde (``Huellenton/ueberGlas(_:)``). Wechselt das Lied, blendet
/// er mit der Glut über. Ohne Hülle bleibt `flaeche`.
///
/// **Wischen:**
/// - Tippen auf Hülle oder Titel und Wischen nach oben öffnen das Blatt.
/// - Seitlich wechselt das Lied: über der Schwelle fährt die Zeile mit dem
///   Schwung des Fingers hinaus und die des neuen Liedes von der anderen
///   Seite herein; darunter federt sie zurück.
/// - Nach unten wischt die Pille ganz weg: die Wiedergabe endet, die
///   Schlange bleibt fürs Weiterhören abgelegt, „Rückgängig" steht kurz da
///   (``Musikmodell/pilleWegwischen()``).
struct Minispieler: View {
    @Environment(Musikmodell.self) private var modell
    @Environment(Blattstand.self) private var stand
    @State private var zug: CGFloat = 0
    /// Nach unten gezogen, zum Wegwischen.
    @State private var senkung: CGFloat = 0
    /// Die Richtung, in die ein Wisch zuerst ging — sie gilt bis zum Ende.
    @State private var senkrecht: Bool?
    /// Stelle und Schwung des Wischs, der gerade das Lied wechselt.
    @State private var anstoss: Anstoss?
    @State private var breite: CGFloat = 360

    /// Abstand zwischen Hülle und Zeile einerseits und den Knöpfen.
    static let zeilenabstand: CGFloat = 12
    /// Zwischen den Zielen: sie liegen übereinander, die Mitten stehen
    /// 40 auseinander.
    static let knopfabstand: CGFloat = -4
    /// Die drei Ziele rechts, mit ihren Abständen.
    static let knopfbreite: CGFloat = 3 * 44 + 2 * knopfabstand
    /// Der Rand rechts neben dem letzten Ziel.
    static let rechts: CGFloat = 6
    /// Die Zeichen, optisch gleich groß: die Umrisse größer als das Dreieck.
    static let ausgabezeichen: CGFloat = 22
    static let herzzeichen: CGFloat = 24
    static let spielzeichen: CGFloat = 22

    /// **Wie weit die Kastenmitte eines Zeichens unter der Mitte seines
    /// Ziels liegt** — gemessen in Tinte (Kasten im 44er-Feld), bei den
    /// Größen oben. Das gefüllte Herz liegt wie der Umriss.
    static func mittenabweichung(_ zeichen: Zeichen) -> CGFloat {
        switch zeichen {
        case .ausgabe: 0.25
        case .herz, .herzUmriss: 0.81
        case .abspielen, .pause: -0.06
        default: 0
        }
    }

    /// Wie weit Hülle und Zeilen beim Liedwechsel rücken: die Breite des
    /// Blocks links der Knöpfe und etwas Luft — so läuft er ganz unter der
    /// Kante aus, bevor der neue ihn erreicht.
    private var schritt: CGFloat {
        max(breite - 9 - Self.rechts - Self.knopfbreite - Self.zeilenabstand, 40) + 16
    }

    var body: some View {
        let spieler = modell.spieler
        if let lied = spieler.aktuell {
            let stelle = spieler.schlange.position
            HStack(spacing: Self.zeilenabstand) {
                HStack(spacing: 12) {
                    Liedwechsel(wert: Huellenwert(kennung: lied.id, bild: modell.bildadresse(lied.bild, punkte: 40)),
                                stelle: stelle, schritt: schritt, anstoss: anstoss) { w in
                        Netzhuelle(adresse: w.bild, zeichengroesse: 16)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: Musikstil.eckeKlein, style: .continuous))
                            .background { Huellenschatten(art: .klein) }
                    }
                        .frame(width: 40, height: 40)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { modell.miniHuelle = $0 }
                    VStack(alignment: .leading, spacing: 0) {
                        Liedwechsel(wert: Zeilenwert(kennung: lied.id, text: lied.titel), stelle: stelle,
                                    schritt: schritt, ausrichtung: .leading, anstoss: anstoss) { z in
                            Text(verbatim: z.text)
                                .font(Musikstil.zeile)
                                .foregroundStyle(Stil.schrift)
                                .lineLimit(1)
                        }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { modell.miniTitel = $0 }
                        if let kuenstler = lied.kuenstlerzeile {
                            Liedwechsel(wert: Zeilenwert(kennung: lied.id, text: kuenstler), stelle: stelle,
                                        schritt: schritt, ausrichtung: .leading, anstoss: anstoss) { z in
                                Text(verbatim: z.text)
                                    .font(Musikstil.angabe)
                                    .foregroundStyle(Musikstil.pillenzweitzeile(spieler.glut))
                                    .lineLimit(1)
                            }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { modell.miniZeile = $0 }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .offset(x: zug)
                // Rechts endet der Block vor den Knöpfen; links, oben und
                // unten schneidet erst die Pille (der Schatten der Hülle bleibt).
                .mask {
                    Rectangle()
                        .padding(.leading, -9)
                        .padding(.vertical, -12)
                }
                .contentShape(Rectangle())
                .onTapGesture { oeffnen() }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Öffnet die Wiedergabe"))
                .accessibilityAction { oeffnen() }
                .accessibilityAction(named: Text("Wiedergabe beenden")) { modell.pilleWegwischen() }
                .accessibilityAction(named: Text("Nächstes Lied")) { spieler.weiter() }

                HStack(spacing: Self.knopfabstand) {
                    // „Abspielen auf": das Geräteblatt, ohne das Wiedergabeblatt.
                    let ausgabe = spieler.fern?.name ?? spieler.ausgabename
                    Button { modell.fern.blattOffen = true } label: {
                        Pillenzeichen(zeichen: .ausgabe, groesse: Self.ausgabezeichen)
                            .foregroundStyle(spieler.fern != nil ? Stil.akzent : Stil.schrift)
                            .animation(Musikstil.bewegungReduziert ? nil : .easeInOut(duration: 0.3),
                                       value: spieler.fern != nil)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(Druckknopf())
                    .accessibilityLabel(Text("Abspielen auf"))
                    .accessibilityValue(Text(verbatim: ausgabe))

                    // Das Herz legt das Lied in die Lieblingssongs — sofort, auch in
                    // der Bibliothek.
                    let favorit = modell.istFavorit(lied.id, sonst: lied.favorit)
                    Button {
                        modell.favoritSetzen(.lied(lied.id), id: lied.id, an: !favorit, lied: lied)
                    } label: {
                        Pillenzeichen(zeichen: favorit ? .herz : .herzUmriss, groesse: Self.herzzeichen)
                            .foregroundStyle(favorit ? Stil.akzent : Stil.schrift)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(Druckknopf())
                    .accessibilityLabel(Text("Favorit"))
                    .accessibilityValue(favorit ? Text("an") : Text("aus"))

                    Button { spieler.umschalten() } label: {
                        Pillenzeichen(zeichen: spieler.spielt ? .pause : .abspielen, groesse: Self.spielzeichen)
                            .animation(Musikstil.umschalten, value: spieler.spielt)
                            .foregroundStyle(Stil.schrift)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(Druckknopf())
                    .accessibilityLabel(spieler.spielt ? Text("Pause") : Text("Abspielen"))
                }
            }
            .padding(.leading, 9)
            .padding(.trailing, Self.rechts)
            .frame(height: 58)
            .background {
                ZStack {
                    Pillenglas()
                    Pillenflaeche(glut: spieler.glut)
                        .opacity(Pillenflaeche.deckung)
                }
            }
            .overlay(alignment: .bottom) {
                Pillenspur(sichtbar: !stand.buehne)
            }
            .clipShape(RoundedRectangle(cornerRadius: Musikstil.eckeMini, style: .continuous))
            // Der Schatten als fertiges Bild — dasselbe trägt die Karte des
            // Blatts, solange sie noch die Pille ist.
            .background { Pillenschatten.ansicht(CGSize(width: breite, height: 58)) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                modell.miniRahmen = $0
                breite = $0.width
            }
            // Nach unten gezogen folgt die Pille dem Finger und wird blasser.
            .offset(y: senkung)
            .opacity(1 - min(senkung / 90, 0.6))
            .gesture(wischen)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                senkung = 0
                zug = 0
            }
        }
    }

    private func oeffnen() {
        modell.blattOffen = true
    }

    /// Seitlich wechselt das Lied; nach oben zieht es das Blatt mit dem Finger
    /// herauf (`Musikstand.zug`), nach unten wischt es die Pille weg.
    private var wischen: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { wert in
                let w = wert.translation
                if senkrecht == nil { senkrecht = abs(w.height) > abs(w.width) }
                if senkrecht == true {
                    if w.height < 0 {
                        senkung = 0
                        stand.zug = -w.height
                    } else {
                        stand.zug = nil
                        senkung = w.height
                    }
                } else {
                    zug = w.width
                }
            }
            .onEnded { wert in
                defer { senkrecht = nil }
                let w = wert.translation
                let tempo = wert.velocity
                if senkrecht == true {
                    if w.height < 0 {
                        // Ein Stück gezogen oder nach oben geworfen: auf.
                        if (w.height < -80 && tempo.height < 300) || tempo.height < -400 {
                            stand.schwung = tempo.height
                            modell.blattOffen = true
                        }
                        stand.zug = nil
                    } else if w.height > 44 || tempo.height > 500 {
                        wegwischen(schwung: tempo.height)
                    } else {
                        withAnimation(Musikstil.blattbewegung) { senkung = 0 }
                    }
                } else {
                    seitlich(w.width, tempo: tempo.width)
                }
            }
    }

    /// **Liedwechsel am Finger** (25.09.: nach dem Loslassen stotterte
    /// es). Vorher fuhr die alte Zeile in einer festen Kurve hinaus, dann
    /// sprang die neue auf 60 % der Breite und federte zurück — zwei
    /// Bewegungen mit einer Naht. Jetzt übernimmt das Karussell
    /// (``Liedwechsel``) die Zeile an der Stelle des Fingers mit seinem
    /// Tempo: die alte schiebt hinaus, die neue folgt in derselben Feder.
    /// Unter der Schwelle federt sie mit dem Schwung zurück.
    ///
    /// Läuft es auf einem anderen Gerät, kommt das neue Lied erst mit dessen
    /// Antwort; bis dahin federt die Zeile zurück, dann rückt das Karussell.
    private func seitlich(_ weg: CGFloat, tempo: CGFloat) {
        let spieler = modell.spieler
        let vor = (weg < -60 || tempo < -500) && spieler.schlange.naechster != nil
        let zurueck = !vor && (weg > 60 || tempo > 500)
        guard vor || zurueck, let alt = spieler.aktuell else {
            zurueckfedern(tempo: tempo)
            return
        }
        if Musikstil.bewegungReduziert {
            vor ? spieler.weiter() : spieler.zurueck()
            withAnimation(Musikstil.blendeReduziert) { zug = 0 }
            return
        }
        var ohne = Transaction(animation: nil)
        ohne.disablesAnimations = true
        withTransaction(ohne) {
            anstoss = Anstoss(versatz: zug, tempo: tempo, richtung: vor ? 1 : -1)
            vor ? spieler.weiter() : spieler.zurueck()
            if spieler.aktuell?.id != alt.id { zug = 0 }
        }
        // Erst nach dem Wechsel vergessen — im selben Zug sähe ihn das
        // Karussell nicht mehr.
        Task { @MainActor in anstoss = nil }
        if zug != 0 { zurueckfedern(tempo: tempo) }
    }

    private func zurueckfedern(tempo: CGFloat) {
        let schwung = abs(zug) > 1 ? -tempo / zug : 0
        withAnimation(Musikstil.liedwechsel(schwung: schwung)) { zug = 0 }
    }

    /// Nach unten hinaus, dann ist die Pille weg.
    private func wegwischen(schwung: CGFloat) {
        if Musikstil.bewegungReduziert {
            senkung = 0
            modell.pilleWegwischen()
            return
        }
        let dauer = min(max(Double(100 / max(schwung, 1)), 0.1), 0.2)
        withAnimation(.easeIn(duration: dauer)) {
            senkung = 100
        } completion: {
            // `senkung` bleibt, bis die Pille wiederkommt — sonst spränge sie
            // im Ausblenden zurück an ihren Platz.
            modell.pilleWegwischen()
        }
    }
}

extension Musikmodell {
    /// **Die Pille ganz wegwischen**: hier endet die Wiedergabe, die Anzeige
    /// wird leer, die Pille geht. Die Schlange bleibt samt Stelle abgelegt
    /// (``Spieler/wegraeumen()``) — nach dem nächsten Start steht sie wieder
    /// bereit. Läuft es auf einem anderen Gerät, löst sich nur dieses iPhone
    /// davon; drüben spielt es weiter. „Rückgängig" holt alles zurück.
    func pilleWegwischen() {
        guard spieler.aktuell != nil else { return }
        blattOffen = false
        let spielte = spieler.spielt
        let zurueckFern = fern.lokalLoesen()
        let stand = spieler.wegraeumen()
        rueckgaengigAnbieten(String(localized: "Wiedergabe beendet.")) { [weak self] in
            guard let self, spieler.aktuell == nil else { return }
            if let zurueckFern {
                // Nur die Verbindung kommt zurück; abgelegt war nichts.
                zurueckFern()
            } else if let stand {
                spieler.wiederherstellen(stand)
                if spielte { spieler.abspielen() }
            }
        }
    }
}

/// Ein Zeichen der Pille, mit der Mitte seines Kastens auf der Mitte des
/// Ziels (``Minispieler/mittenabweichung(_:)``) — in der Pille und in der
/// wachsenden Karte des Blatts dasselbe.
struct Pillenzeichen: View {
    let zeichen: Zeichen
    let groesse: CGFloat

    var body: some View {
        Symbolbild(zeichen: zeichen, groesse: groesse)
            .offset(y: -Minispieler.mittenabweichung(zeichen))
    }
}

/// **Der Verlauf des Mini-Players** — von der Hülle aus, wie die Glut im
/// Blatt: an ihrer Mitte der Hauptton, zum rechten Rand der tiefere Nebenton
/// (``Huellenton/pillenverlauf(_:)``). Wechselt das Lied, blendet der neue
/// über dem alten auf, der alte bleibt darunter voll stehen — nie scheint
/// dazwischen das Glas dunkler durch (``Deckwechsel``).
struct Pillenflaeche: View {
    let glut: Huellenton.Glut?

    /// Wie weit der Verlauf deckt; darunter die Unschärfe.
    static let deckung = Huellenton.pillendeckung

    var body: some View {
        GeometryReader { g in
            Deckwechsel(wert: glut) { glut in
                Rectangle()
                    .fill(Musikstil.pillenverlauf(glut, rahmen: CGRect(origin: .zero, size: g.size),
                                                  in: g.size))
            }
        }
        .allowsHitTesting(false)
    }
}
