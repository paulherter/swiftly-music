import Foundation

/// **Was Jellyfin zu einem Lied sagt**, wenn man ihm das Geräteprofil zeigt
/// (`POST /Items/{id}/PlaybackInfo`, Finamps `getPlaybackInfo`).
///
/// Die eigene Regel (``Abspielregel``) kennt nur das Gerät. Der Server kennt
/// dazu, was der Verwalter erlaubt: ob ein Konto überhaupt direkt spielen
/// darf, und eine Obergrenze für Verbindungen von außen. Beides steckt in der
/// Antwort — `SupportsDirectPlay`/`SupportsDirectStream` und die Rate in der
/// `TranscodingUrl`.
public struct Serverentscheid: Hashable, Sendable {
    /// Der Server lässt die Datei, wie sie ist.
    public var direkt: Bool
    /// Höchstrate in kbit/s, die der Server fürs Umwandeln vorgibt.
    public var hoechstrate: Int?

    public init(direkt: Bool, hoechstrate: Int?) {
        self.direkt = direkt
        self.hoechstrate = hoechstrate
    }

    /// Aus der Antwort von `PlaybackInfo`; `nil`, wenn sie nichts sagt.
    public static func lesen(_ daten: Data) -> Serverentscheid? {
        guard let wurzel = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let quellen = wurzel["MediaSources"] as? [[String: Any]], let q = quellen.first else { return nil }
        let direkt = (q["SupportsDirectPlay"] as? Bool ?? true) || (q["SupportsDirectStream"] as? Bool ?? false)
        var rate: Int?
        if let url = q["TranscodingUrl"] as? String,
           let teile = URLComponents(string: url.hasPrefix("/") ? "https://x" + url : url) {
            for w in teile.queryItems ?? [] where ["audiobitrate", "maxstreamingbitrate"].contains(w.name.lowercased()) {
                if let wert = w.value.flatMap(Int.init), wert > 0 {
                    rate = min(rate ?? .max, wert / 1000)
                }
            }
        }
        return Serverentscheid(direkt: direkt, hoechstrate: rate)
    }

    /// **Die Umwandlung, wenn eigene Regel und Server zusammenkommen** —
    /// `nil` heißt direkt. Die strengere Grenze gilt; verbietet der Server das
    /// Direktspielen, wird umgewandelt, auch was das Gerät könnte.
    public static func umwandlung(fuer format: Tonformat?, hoechstens: Int?,
                                  server: Serverentscheid?) -> Umwandlung? {
        let grenze = [hoechstens, server?.hoechstrate].compactMap { $0 }.min()
        if let u = Abspielregel.umwandlung(fuer: format, hoechstens: grenze) { return u }
        guard let server, !server.direkt else { return nil }
        let voll = Abspielregel.umwandlung(fuer: .jellyfin)
        return Umwandlung(codec: voll.codec, bitrate: min(voll.bitrate, grenze ?? voll.bitrate))
    }
}

/// Das Geräteprofil, das Jellyfin gezeigt wird — dieselben Behälter und
/// Codecs wie ``Abspielregel``, umgewandelt wird in MP3.
enum Geraeteprofil {
    static func rumpf(hoechstens: Int?) -> Data {
        let rate = (hoechstens ?? 100_000) * 1000
        let profil: [String: Any] = [
            "MaxStreamingBitrate": rate,
            "MaxStaticBitrate": rate,
            "MusicStreamingTranscodingBitrate": min(rate, 320_000),
            "DirectPlayProfiles": [[
                "Type": "Audio",
                "Container": Abspielregel.behaelter.sorted().joined(separator: ","),
                "AudioCodec": (Abspielregel.codecs.sorted() + ["pcm_s16le", "pcm_s24le", "pcm_f32le"]).joined(separator: ","),
            ]],
            "TranscodingProfiles": [[
                "Type": "Audio", "Container": "mp3", "AudioCodec": "mp3",
                "Protocol": "http", "Context": "Streaming", "MaxAudioChannels": "2",
            ]],
            "CodecProfiles": [] as [Any],
            "SubtitleProfiles": [] as [Any],
        ]
        return (try? JSONSerialization.data(withJSONObject: ["DeviceProfile": profil])) ?? Data()
    }
}

/// Was schon ausgehandelt ist, je Lied — hinter einem Schloss.
final class Entscheidungen: @unchecked Sendable {
    private let schloss = NSLock()
    private var werte: [String: Serverentscheid] = [:]

    subscript(_ id: String) -> Serverentscheid? {
        get { schloss.withLock { werte[id] } }
        set { schloss.withLock { werte[id] = newValue } }
    }
}
