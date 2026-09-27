import Foundation

/// **Über welche Leitung das Gerät gerade im Netz ist.** `mobil` heißt:
/// eine Leitung, die das System als teuer führt — Mobilfunk oder ein
/// persönlicher Hotspot.
public enum Verbindung: String, Sendable, Codable, Hashable {
    case wlan, mobil, keine
}

/// **Ob geladen werden darf.** Mit „Nur über WLAN laden" wartet es auf
/// Mobilfunk, ohne Netz sowieso (Finamps `requireWifiForDownloads`).
public enum Ladeerlaubnis {
    public static func darf(_ verbindung: Verbindung, nurWLAN: Bool) -> Bool {
        switch verbindung {
        case .wlan: true
        case .mobil: !nurWLAN
        case .keine: false
        }
    }
}
