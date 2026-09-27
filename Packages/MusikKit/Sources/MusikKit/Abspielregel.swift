import Foundation

/// **Direkt oder umwandeln — und was die Plakette dazu sagt.**
///
/// Swiftlys Zusage gilt auch hier: die Datei läuft, wie sie ist, wann immer
/// das Gerät sie spielen kann. Umgewandelt wird nur, was AVFoundation nicht
/// kennt (Ogg Vorbis, Opus, WMA, APE, DSD …), und dann steht es auf der
/// Plakette — leise, nicht im Akzent.
public enum Abspielregel {

    /// Behälter, die AVFoundation auf dem iPhone öffnet.
    static let behaelter: Set<String> = [
        "mp3", "mpeg", "mpga",
        "m4a", "m4b", "mp4", "aac", "adts",
        "flac",
        "wav", "wave",
        "aif", "aiff", "aifc",
        "caf",
        "alac",
    ]

    /// Codecs, die AVFoundation dekodiert. Opus ginge in CAF seit iOS 17 —
    /// von Servern kommt Opus aber in Ogg oder WebM, und das öffnet
    /// AVFoundation nicht; darum hier bewusst nicht.
    static let codecs: Set<String> = [
        "mp3", "mp2", "mpeg", "aac", "he-aac", "heaac", "aac_latm", "alac", "flac",
        "ac3", "eac3",
    ]

    /// **Kann das Gerät die Datei so spielen, wie sie ist?**
    ///
    /// Ohne Angaben: ja — dann versucht es der Player direkt, und nur ein
    /// Fehler würde etwas anderes sagen. Eine Umwandlung auf Verdacht wäre
    /// der schlechtere Irrtum.
    public static func kannDirekt(_ format: Tonformat?) -> Bool {
        guard let format else { return true }
        if let b = format.behaelter?.lowercased(), !b.isEmpty, !behaelter.contains(b) {
            return false
        }
        if let c = format.codec?.lowercased(), !c.isEmpty, !codecOK(c) {
            return false
        }
        if format.behaelter == nil, format.codec == nil, let mime = format.mime?.lowercased() {
            return mimeOK(mime)
        }
        return true
    }

    static func codecOK(_ codec: String) -> Bool {
        if codecs.contains(codec) { return true }
        // PCM in allen Schreibweisen: pcm_s16le, pcm_s24be, pcm_f32le …
        if codec.hasPrefix("pcm") { return true }
        return false
    }

    static func mimeOK(_ mime: String) -> Bool {
        ["audio/mpeg", "audio/mp3", "audio/mp4", "audio/x-m4a", "audio/aac", "audio/flac",
         "audio/x-flac", "audio/wav", "audio/x-wav", "audio/aiff", "audio/x-aiff"].contains(mime)
    }

    /// **Wohin umgewandelt wird: MP3 mit 320 kbit/s, fortlaufend.**
    ///
    /// Bei beiden Servern dasselbe, und bewusst kein HLS: eine einzige
    /// Adresse, die das Zugangsmerkmal trägt (`ApiKey` bzw. `t`/`s`), und
    /// keine Folgeadressen, von denen ungewiss ist, ob der Server es an sie
    /// weiterreicht. MP3 in voller Rate ist für jede verlustbehaftete Quelle
    /// (Vorbis, Opus, WMA) mehr als genug, und AVFoundation spielt es
    /// fortlaufend wie ein Radio.
    public static func umwandlung(fuer art: Serverart) -> Umwandlung {
        Umwandlung(codec: "mp3", bitrate: 320)
    }

    /// **Direkt oder umwandeln, mit einer Höchstrate** — `nil` heißt direkt.
    ///
    /// Ohne Grenze gilt die Zusage von oben: umgewandelt wird nur, was das
    /// Gerät nicht spielt. Mit Grenze (eine Einstellung je Netz, wie bei Tempo
    /// und Finamp) wird auch umgewandelt, was darüber liegt — verlustfreie
    /// Dateien immer, verlustbehaftete, wenn ihre Rate höher ist oder
    /// unbekannt. Unter der Grenze bleibt die Datei, wie sie ist.
    public static func umwandlung(fuer format: Tonformat?, hoechstens grenze: Int?) -> Umwandlung? {
        let voll = umwandlung(fuer: .jellyfin)
        guard kannDirekt(format) else {
            return Umwandlung(codec: voll.codec, bitrate: min(voll.bitrate, grenze ?? voll.bitrate))
        }
        guard let grenze, grenze > 0 else { return nil }
        if let format, !istVerlustfrei(format), let rate = format.bitrate, rate <= grenze { return nil }
        return Umwandlung(codec: voll.codec, bitrate: min(voll.bitrate, grenze))
    }

    /// **Das Item braucht den genauen Zeitzugriff**
    /// (`AVURLAssetPreferPreciseDurationAndTimingKey`).
    ///
    /// Gemessen am 25.09. (Ton im Tap mitgeschnitten, Frequenz ↔ Sekunde):
    /// in einer FLAC-Datei springt AVFoundation ohne diesen Schlüssel über
    /// eine **geschätzte Bitrate** — `seek(to: 58)` meldet 58,0 s, zu hören
    /// war 67,5 s; 90 → 116,6 s. Eine SEEKTABLE ändert nichts, eine Datei auf
    /// dem Gerät auch nicht; AAC in M4A landet genau (58,02 s). Mit dem
    /// Schlüssel landet FLAC bei 58,02 s.
    ///
    /// Der Preis: über das Netz lädt AVFoundation dafür die **ganze Datei**,
    /// bevor das Item bereit ist (11,5 MB bei 1,5 MB/s: 8,5 s). Darum nur,
    /// wo es zählt:
    /// - eine geladene Datei auf dem Gerät — dort kostet es fast nichts
    ///   (+0,07 s bei 11,5 MB), und jedes Spulen sitzt;
    /// - ein Lied, das **mitten drin anfängt** (von Sonos zurück, nach dem
    ///   Neustart, ein Hörbuch) — lieber kurz warten als an der falschen
    ///   Stelle weiterhören.
    ///
    /// Umgewandelte Lieder kommen als MP3 mit fester Rate; dort stimmt die
    /// Schätzung.
    public static func genauerZugriff(_ weg: Abspielweg, startMitten: Bool) -> Bool {
        guard weg.art == .direkt, istFlacDatei(weg) else { return false }
        return weg.adresse.isFileURL || startMitten
    }

    /// Eine FLAC-Datei, nicht FLAC in MP4 — die hat einen Zeitindex.
    static func istFlacDatei(_ weg: Abspielweg) -> Bool {
        if weg.adresse.pathExtension.lowercased() == "flac" { return true }
        if let b = weg.format?.behaelter?.lowercased(), !b.isEmpty { return b == "flac" }
        if let m = weg.mime?.lowercased() { return m == "audio/flac" || m == "audio/x-flac" }
        return false
    }

    /// Der Medientyp zu einer Endung, falls der Server keinen nennt.
    public static func mime(fuer behaelter: String?) -> String? {
        switch behaelter?.lowercased() {
        case "mp3", "mpeg", "mpga": "audio/mpeg"
        case "m4a", "m4b", "mp4", "alac": "audio/mp4"
        case "aac", "adts": "audio/aac"
        case "flac": "audio/flac"
        case "wav", "wave": "audio/wav"
        case "aif", "aiff", "aifc": "audio/aiff"
        case "caf": "audio/x-caf"
        default: nil
        }
    }

    // MARK: - Plakette

    /// **Die Formatangabe auf der Plakette:** „FLAC 24/96" bei verlustfreien
    /// Dateien (Bittiefe und Abtastrate), „MP3 320" bei verlustbehafteten
    /// (Bitrate). Fehlt die Zahl, steht nur der Name.
    public static func formatangabe(_ format: Tonformat?, locale: Locale = .current) -> String? {
        guard let format else { return nil }
        guard let name = formatname(format) else { return nil }
        if istVerlustfrei(format) {
            if let tiefe = format.bitTiefe, let rate = format.abtastrate {
                return "\(name) \(tiefe)/\(kilohertz(rate, locale: locale))"
            }
            return name
        }
        if let bitrate = format.bitrate, bitrate > 0 {
            return "\(name) \(bitrate)"
        }
        return name
    }

    /// Die Angabe für das Ziel einer Umwandlung, etwa „AAC 256".
    public static func formatangabe(_ umwandlung: Umwandlung) -> String {
        "\(umwandlung.codec.uppercased()) \(umwandlung.bitrate)"
    }

    /// Was auf der Plakette eines Liedes steht.
    public static func angabe(_ weg: Abspielweg, locale: Locale = .current) -> String? {
        switch weg.art {
        case .direkt: formatangabe(weg.format, locale: locale)
        case .umgewandelt: weg.umwandlung.map(formatangabe)
        }
    }

    public static func istVerlustfrei(_ format: Tonformat) -> Bool {
        let c = format.codec?.lowercased() ?? ""
        let b = format.behaelter?.lowercased() ?? ""
        if ["flac", "alac", "ape", "wavpack", "wv", "tta", "dsd", "dsf", "dff"].contains(c) { return true }
        if c.hasPrefix("pcm") { return true }
        if c.isEmpty, ["flac", "wav", "wave", "aif", "aiff", "aifc", "ape", "wv", "dsf", "dff"].contains(b) {
            return true
        }
        return false
    }

    /// Wie das Format heißt — nach dem Codec, sonst nach dem Behälter.
    public static func formatname(_ format: Tonformat) -> String? {
        let c = format.codec?.lowercased() ?? ""
        let b = format.behaelter?.lowercased() ?? ""
        if c.hasPrefix("pcm") || (c.isEmpty && ["wav", "wave"].contains(b)) {
            return ["aif", "aiff", "aifc"].contains(b) ? "AIFF" : "WAV"
        }
        switch c {
        case "": break
        case "vorbis": return "Vorbis"
        case "opus": return "Opus"
        case "wmav1", "wmav2", "wmapro", "wmalossless": return "WMA"
        case "he-aac", "heaac", "aac_latm": return "AAC"
        case "mp2": return "MP2"
        case "dsd", "dsd_lsbf", "dsd_msbf": return "DSD"
        default: return c.uppercased()
        }
        switch b {
        case "": return nil
        case "m4a", "m4b", "mp4": return "AAC"
        case "ogg", "oga": return "Vorbis"
        case "aif", "aiff", "aifc": return "AIFF"
        case "dsf", "dff": return "DSD"
        case "wma": return "WMA"
        default: return b.uppercased()
        }
    }

    /// 96000 → „96", 44100 → „44,1" (bzw. „44.1").
    static func kilohertz(_ hertz: Int, locale: Locale) -> String {
        let khz = Double(hertz) / 1000
        return khz.formatted(.number.locale(locale).precision(.fractionLength(0 ... 1)).grouping(.never))
    }

    // MARK: - Ein ganzes Album

    /// Was über einem Album steht.
    public enum Albumangabe: Hashable, Sendable {
        /// Alles läuft direkt; die Angabe, wenn alle Lieder dasselbe Format haben.
        case direkt(String?)
        /// Alles wird umgewandelt, in dieses Ziel.
        case umgewandelt(String)
        /// Manches direkt, manches nicht.
        case gemischt
    }

    public static func albumangabe(_ lieder: [Lied], serverart: Serverart,
                                   locale: Locale = .current) -> Albumangabe? {
        guard !lieder.isEmpty else { return nil }
        let direkt = lieder.filter { kannDirekt($0.format) }
        if direkt.count == lieder.count {
            let angaben = Set(lieder.map { formatangabe($0.format, locale: locale) ?? "" })
            if angaben.count == 1, let eine = angaben.first, !eine.isEmpty { return .direkt(eine) }
            return .direkt(nil)
        }
        if direkt.isEmpty { return .umgewandelt(formatangabe(umwandlung(fuer: serverart))) }
        return .gemischt
    }
}
