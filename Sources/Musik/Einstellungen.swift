import Foundation
import MusikKit
import SwiftUI

/// **Die wenigen Einstellungen von Swiftly Music** — auf dem Gerät, für alle
/// Konten. Sie stehen schlicht auf der Kontoseite, im Stil der Einstellungen
/// von Swiftly Player: Karten mit Zeilen, rechts ein Schalter oder der Wert.
@MainActor
@Observable
final class Musikeinstellungen {
    private let ablage: UserDefaults

    init(ablage: UserDefaults = .standard) {
        self.ablage = ablage
        lautheitAngleichen = ablage.object(forKey: Schluessel.lautheit) as? Bool ?? true
        bitrateWLAN = ablage.object(forKey: Schluessel.wlan) as? Int ?? 0
        bitrateMobil = ablage.object(forKey: Schluessel.mobil) as? Int ?? 0
        nurWLANLaden = ablage.object(forKey: Schluessel.nurWLAN) as? Bool ?? false
        radio = ablage.object(forKey: Schluessel.radio) as? Bool ?? true
        technischeDaten = ablage.object(forKey: Schluessel.technik) as? Bool ?? false
    }

    private enum Schluessel {
        static let lautheit = "musik.lautheit"
        static let wlan = "musik.bitrate.wlan"
        static let mobil = "musik.bitrate.mobil"
        static let nurWLAN = "musik.laden.nurWLAN"
        static let radio = "musik.radio"
        static let technik = "musik.technischeDaten"
    }

    /// ReplayGain bzw. `NormalizationGain` anwenden (``Lautheitsregel``).
    var lautheitAngleichen: Bool { didSet { ablage.set(lautheitAngleichen, forKey: Schluessel.lautheit) } }
    /// Höchste Rate beim Streamen in kbit/s; 0 heißt „Original".
    var bitrateWLAN: Int { didSet { ablage.set(bitrateWLAN, forKey: Schluessel.wlan) } }
    var bitrateMobil: Int { didSet { ablage.set(bitrateMobil, forKey: Schluessel.mobil) } }
    /// Geladen wird nur im WLAN (``Ladeerlaubnis``).
    var nurWLANLaden: Bool { didSet { ablage.set(nurWLANLaden, forKey: Schluessel.nurWLAN) } }
    /// Ist die Schlange zu Ende, geht es mit Ähnlichem weiter (``Radioregel``).
    var radio: Bool { didSet { ablage.set(radio, forKey: Schluessel.radio) } }
    /// **Die Plakette im Blatt** („Direct Play · FLAC 24/96") — der Schalter
    /// „Technische Daten im Player" wie im Player. **Aus, bis ihn jemand
    /// einschaltet** (24.09.) — wie im Player. Wer ihn schon einmal
    /// gesetzt hat, behält seinen Wert: die Vorgabe greift nur, solange
    /// nichts abgelegt ist.
    var technischeDaten: Bool { didSet { ablage.set(technischeDaten, forKey: Schluessel.technik) } }

    /// Die Grenze fürs Streamen über diese Verbindung, `nil` für Original.
    func hoechstens(bei verbindung: Verbindung) -> Int? {
        let wert = verbindung == .mobil ? bitrateMobil : bitrateWLAN
        return wert > 0 ? wert : nil
    }

    /// Die wählbaren Raten.
    static let raten = [0, 320, 256, 192, 128]

    static func name(rate: Int) -> String {
        rate == 0 ? String(localized: "Original") : String(localized: "\(rate) kbit/s")
    }
}

/// **Der Schalter** — eigener Bau wie `Schalter` im Player, kein
/// Systemschalter (der erscheint unter iOS 26 als Glas).
struct Schalter: View {
    @Binding var an: Bool
    @Environment(\.isEnabled) private var bedienbar

    var body: some View {
        Button { an.toggle() } label: {
            ZStack(alignment: an ? .trailing : .leading) {
                Capsule()
                    .fill(an ? (bedienbar ? Stil.akzent : Stil.flaeche) : Stil.rand)
                    .frame(width: 46, height: 28)
                Circle()
                    .fill(bedienbar ? (an ? Stil.grund : Color.white) : Stil.schriftSehrLeise)
                    .frame(width: 22, height: 22)
                    .padding(.horizontal, 3)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Musikstil.umschalten, value: an)
        .accessibilityRepresentation {
            Toggle(isOn: $an) { Text("Ein") }
        }
    }
}
