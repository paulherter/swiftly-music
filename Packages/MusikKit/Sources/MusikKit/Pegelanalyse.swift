import Foundation

/// **Drei Bänder aus der laufenden Musik** — tief, mittel, hoch — für die
/// drei Balken des Pegels (Übergabe §7).
///
/// Gerechnet wird im Tonfaden von AVFoundation (`MTAudioProcessingTap`),
/// einem Echtzeitfaden: dort darf nichts Speicher anfordern, nichts auf eine
/// Sperre warten, nichts auf den Hauptlauf springen. Deshalb ist das hier
/// ein Werttyp mit festem Zustand, der nur über Zeiger liest, und das
/// Ergebnis geht als eine einzige 64-Bit-Zahl hinaus (``packen(_:)``), die
/// die Oberfläche ohne Sperre liest.
///
/// **Wie**: keine FFT — für drei Balken zu teuer und zu genau. Tiefpässe
/// erster Ordnung, je zwei hintereinander, teilen das Signal (bis 250 Hz,
/// bis 2,5 kHz, der Rest), je Block wird der Effektivwert jedes Bandes genommen. Jedes Band
/// misst sich an seiner eigenen Spitze, die sofort steigt und in drei
/// Sekunden auf die Hälfte fällt — so bewegen sich leise Lieder so deutlich
/// wie laute, und ein Bass, der alles überragt, drückt Mitten und Höhen
/// nicht platt (bis zu einem Drittel seiner Spitze, darunter ist es nur
/// Übersprechen). Zum Schluss geglättet: nach oben in 60 ms, nach unten in
/// 200 ms, wie ein Zeigerinstrument (vorher 40 / 180 ms).
public struct Pegelanalyse: Sendable {

    /// Drei Werte von 0 bis 1.
    public struct Baender: Sendable, Equatable {
        public var tief: Float
        public var mittel: Float
        public var hoch: Float

        public init(tief: Float, mittel: Float, hoch: Float) {
            self.tief = tief
            self.mittel = mittel
            self.hoch = hoch
        }

        public static let still = Baender(tief: 0, mittel: 0, hoch: 0)
    }

    /// Grenzen der Bänder in Hz.
    static let grenzeTief: Double = 250
    static let grenzeHoch: Double = 2_500
    /// Darunter gilt ein Band als still (etwa −66 dBFS).
    static let schwelle: Float = 0.0005
    static let halbwertSpitze: Float = 3
    static let mindestbezug: Float = 0.35
    /// **Für die Höhen viel weniger**: in sie spricht der Bass kaum über
    /// (zwei Hochpässe bei 2,5 kHz lassen von 60 Hz ein Zweitausendstel
    /// durch). Mit einem Drittel stand der hohe Balken neben lautem Bass fast
    /// immer ganz unten (24.09.).
    static let mindestbezugHoch: Float = 0.1
    /// Zeigerinstrument: hoch in 60 ms, herunter in 200 ms (24.09.:
    /// vorher 40 / 180 ms, „too much").
    static let anstieg: Float = 0.06
    static let abfall: Float = 0.20

    private let abtastrate: Float
    private let beiwertTief: Float
    private let beiwertHoch: Float
    /// Acht Tiefpässe erster Ordnung, je zwei hintereinander (12 dB je
    /// Oktave): einer allein ließ einen 60-Hz-Ton zu einem Viertel in die
    /// Mitten durch.
    private var z = (Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0))
    private var summeTief: Float = 0
    private var summeMittel: Float = 0
    private var summeHoch: Float = 0
    private var gezaehlt = 0
    private var spitze = Baender(tief: 0.01, mittel: 0.01, hoch: 0.01)
    public private(set) var geglaettet = Baender.still

    public init(abtastrate: Double) {
        let rate = max(abtastrate, 8_000)
        self.abtastrate = Float(rate)
        beiwertTief = Float(1 - exp(-2 * Double.pi * Self.grenzeTief / rate))
        beiwertHoch = Float(1 - exp(-2 * Double.pi * Self.grenzeHoch / rate))
    }

    /// **Proben aufnehmen**: `anzahl` Werte ab `a`, mit `schritt` Abstand
    /// (2 bei verschränktem Stereo). `b` ist der zweite Kanal, wenn es ihn
    /// getrennt gibt; beide werden zu Mono gemittelt. Fordert nichts an.
    public mutating func aufnehmen(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>?,
                                   anzahl: Int, schritt: Int = 1) {
        guard anzahl > 0 else { return }
        var z = self.z
        var st = summeTief, sm = summeMittel, sh = summeHoch
        let kt = beiwertTief, kh = beiwertHoch
        var i = 0
        let ende = anzahl * schritt
        while i < ende {
            var x = a[i]
            if let b { x = (x + b[i]) * 0.5 }
            // Tief: zweimal unter 250 Hz.
            z.0 += kt * (x - z.0)
            z.1 += kt * (z.0 - z.1)
            let tief = z.1
            // Mitte: zweimal über 250 Hz, dann zweimal unter 2,5 kHz.
            z.2 += kt * (x - z.2)
            let ueber1 = x - z.2
            z.3 += kt * (ueber1 - z.3)
            let ueber2 = ueber1 - z.3
            z.4 += kh * (ueber2 - z.4)
            z.5 += kh * (z.4 - z.5)
            let mitte = z.5
            // Hoch: zweimal über 2,5 kHz.
            z.6 += kh * (x - z.6)
            let hoch1 = x - z.6
            z.7 += kh * (hoch1 - z.7)
            let oben = hoch1 - z.7
            st += tief * tief
            sm += mitte * mitte
            sh += oben * oben
            i += schritt
        }
        // Denormale Reste nach langer Stille auf null — sie kosten Rechenzeit.
        if abs(z.0) + abs(z.2) + abs(z.4) + abs(z.6) < 1e-20 { z = (0, 0, 0, 0, 0, 0, 0, 0) }
        self.z = z
        summeTief = st
        summeMittel = sm
        summeHoch = sh
        gezaehlt += anzahl
    }

    /// **Den Block abschließen**: Effektivwerte, an der Spitze gemessen,
    /// geglättet. Einmal je Rückruf des Taps.
    @discardableResult
    public mutating func abschliessen() -> Baender {
        guard gezaehlt > 0 else { return geglaettet }
        let n = Float(gezaehlt)
        let dauer = n / abtastrate
        let roh = Baender(tief: (summeTief / n).squareRoot(),
                          mittel: (summeMittel / n).squareRoot(),
                          hoch: (summeHoch / n).squareRoot())
        summeTief = 0
        summeMittel = 0
        summeHoch = 0
        gezaehlt = 0

        let fall = Float(exp(-Double(dauer) * log(2) / Double(Self.halbwertSpitze)))
        spitze.tief = max(roh.tief, spitze.tief * fall, 0.002)
        spitze.mittel = max(roh.mittel, spitze.mittel * fall, 0.002)
        spitze.hoch = max(roh.hoch, spitze.hoch * fall, 0.002)

        // Ein Band misst sich an der eigenen Spitze, aber nie an weniger als
        // einem Drittel der lautesten — sonst stünde das Übersprechen eines
        // reinen Basstons in den Höhen als voller Balken da.
        let lauteste = max(spitze.tief, spitze.mittel, spitze.hoch)
        let boden = lauteste * Self.mindestbezug
        let bodenHoch = lauteste * Self.mindestbezugHoch
        geglaettet.tief = Self.glaetten(geglaettet.tief, Self.anteil(roh.tief, max(spitze.tief, boden)), dauer)
        geglaettet.mittel = Self.glaetten(geglaettet.mittel, Self.anteil(roh.mittel, max(spitze.mittel, boden)), dauer)
        geglaettet.hoch = Self.glaetten(geglaettet.hoch, Self.anteil(roh.hoch, max(spitze.hoch, bodenHoch)), dauer)
        return geglaettet
    }

    static func anteil(_ wert: Float, _ spitze: Float) -> Float {
        wert < schwelle ? 0 : min(wert / spitze, 1)
    }

    static func glaetten(_ alt: Float, _ neu: Float, _ dauer: Float) -> Float {
        let tau = neu > alt ? anstieg : abfall
        let k = 1 - Float(exp(-Double(dauer / tau)))
        return alt + (neu - alt) * k
    }

    // MARK: Über den Faden

    /// **Drei Bänder in einer Zahl**, je 16 Bit — so gehen sie mit einem
    /// einzigen atomaren Schreiben vom Tonfaden zur Oberfläche, ohne Sperre.
    /// Das oberste Bit sagt, dass überhaupt ein Wert darin steht.
    public static func packen(_ b: Baender) -> UInt64 {
        func teil(_ x: Float) -> UInt64 { UInt64((min(max(x, 0), 1) * 65_535).rounded()) }
        return 1 << 63 | teil(b.tief) << 32 | teil(b.mittel) << 16 | teil(b.hoch)
    }

    /// `nil`, wenn noch nie ein Wert geschrieben wurde.
    public static func entpacken(_ wert: UInt64) -> Baender? {
        guard wert & (1 << 63) != 0 else { return nil }
        func teil(_ x: UInt64) -> Float { Float(x & 0xFFFF) / 65_535 }
        return Baender(tief: teil(wert >> 32), mittel: teil(wert >> 16), hoch: teil(wert))
    }
}

/// **Was die drei Balken zeigen** — aus den Bändern der ``Pegelanalyse``,
/// damit sie sich sichtbar abwechseln (24.09.: der mittlere war fast
/// immer der höchste, der rechte fast immer ganz klein — „sieht immer aus
/// wie ein Mittelfinger").
///
/// - **Jedes Band nutzt seinen ganzen Bereich**: je Band ein laufendes
///   Minimum und Maximum, die sofort folgen, wenn der Wert sie überschreitet,
///   und sonst in ``halbwert`` Sekunden zur Hälfte auf ihn zurückgehen. Der
///   Balken zeigt, wo der Wert zwischen beiden steht. Leise Höhen neben
///   lautem Bass bewegen sich so so weit wie der Bass.
/// - **Nie Rauschen als voller Ausschlag**: liegen Minimum und Maximum
///   näher als ``mindestspanne`` beieinander, wird mit dieser Spanne
///   gerechnet.
/// - **Leicht versetzt**: das mittlere Band läuft zwei Schritte, das hohe
///   vier Schritte nach (bei 30 Hz 66 und 133 ms) — so steht nie lange
///   dieselbe Form.
///
/// Rechnet im Takt der Oberfläche, nicht im Tonfaden; ein Werttyp ohne
/// Anforderungen je Schritt.
public struct Pegelanzeige: Sendable {
    static let halbwert: Double = 1.2
    static let mindestspanne: Float = 0.08
    static let nachlauf = (mittel: 2, hoch: 4)
    /// **Ruhiger** (24.09.: „übertreibt ein bisschen, soll chilliger
    /// werden"): was die Balken zeigen, steigt in 80 ms und fällt in 100 ms
    /// — ein Schlag hebt den Balken, statt ihn hochzureißen.
    static let anzeigeAnstieg: Double = 0.08
    static let anzeigeAbfall: Double = 0.10
    /// Der Ausschlag der Balken: nie ganz unten, nie ganz oben — 30 bis 85 %
    /// ihrer Höhe (vorher 18 bis 100 %).
    public static let balkenUnten: Float = 0.30
    public static let balkenOben: Float = 0.85

    private var unten = Pegelanalyse.Baender.still
    private var oben = Pegelanalyse.Baender.still
    private var glatt = Pegelanalyse.Baender.still

    /// Die Höhe eines Balkens (Anteil am Feld) für einen Wert von 0 bis 1.
    public static func balken(_ wert: Float) -> Float {
        balkenUnten + (balkenOben - balkenUnten) * min(max(wert, 0), 1)
    }
    /// Die letzten Werte, für den Nachlauf — ein fester Ring.
    private var ring = [Pegelanalyse.Baender](repeating: .still, count: 8)
    private var stelle = 0

    public init() {}

    /// Ein Schritt: die Bänder dieses Augenblicks, `dauer` Sekunden nach dem
    /// letzten. Zurück kommen drei Werte von 0 bis 1.
    public mutating func schritt(_ b: Pegelanalyse.Baender, dauer: Double) -> Pegelanalyse.Baender {
        stelle = (stelle + 1) % ring.count
        ring[stelle] = b
        let jetzt = b
        let mitte = ring[(stelle - Self.nachlauf.mittel + ring.count) % ring.count]
        let hoch = ring[(stelle - Self.nachlauf.hoch + ring.count) % ring.count]
        let k = Float(1 - exp(-max(dauer, 0) * log(2) / Self.halbwert))
        let roh = Pegelanalyse.Baender(tief: Self.lage(jetzt.tief, &unten.tief, &oben.tief, k),
                                       mittel: Self.lage(mitte.mittel, &unten.mittel, &oben.mittel, k),
                                       hoch: Self.lage(hoch.hoch, &unten.hoch, &oben.hoch, k))
        let auf = Float(1 - exp(-max(dauer, 0) / Self.anzeigeAnstieg))
        let ab = Float(1 - exp(-max(dauer, 0) / Self.anzeigeAbfall))
        func weich(_ alt: Float, _ neu: Float) -> Float { alt + (neu - alt) * (neu > alt ? auf : ab) }
        glatt = Pegelanalyse.Baender(tief: weich(glatt.tief, roh.tief), mittel: weich(glatt.mittel, roh.mittel),
                                     hoch: weich(glatt.hoch, roh.hoch))
        return glatt
    }

    static func lage(_ x: Float, _ unten: inout Float, _ oben: inout Float, _ k: Float) -> Float {
        if x > oben { oben = x } else { oben += (x - oben) * k }
        if x < unten { unten = x } else { unten += (x - unten) * k }
        let spanne = max(oben - unten, mindestspanne)
        return min(max((x - unten) / spanne, 0), 1)
    }
}
