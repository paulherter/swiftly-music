import Foundation
#if canImport(Network)
import Network

/// **Sonos im Netz finden** — über Bonjour (`_sonos._tcp`), nicht über
/// SSDP. SSDP ist Multicast und bräuchte Apples Sonderfreigabe dafür;
/// Bonjour geht mit `NSBonjourServices` und der gewöhnlichen Frage nach dem
/// lokalen Netz.
///
/// Jeder Fund wird einmal aufgelöst (eine TCP-Verbindung bis „bereit",
/// dann zu) — heraus kommt die Adresse, unter der die Schnittstelle auf
/// Port 1400 antwortet. Ein einziger Lautsprecher reicht eigentlich: jeder
/// kennt alle Gruppen im Haushalt (``SonosClient/gruppen()``).
public enum SonosSuche {

    /// Die Basisadressen (`http://ip:1400`), wie sie gefunden werden. Endet
    /// die Folge oder bricht die Aufgabe ab, hört die Suche auf.
    public static func basen() -> AsyncStream<URL> {
        AsyncStream { fortsetzung in
            let schlange = DispatchQueue(label: "de.paulherter.swiftly.music.sonos-suche")
            let zustand = Suchzustand()
            let browser = NWBrowser(for: .bonjour(type: "_sonos._tcp", domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { ergebnisse, _ in
                for e in ergebnisse where !zustand.gesehen.contains(e.endpoint) {
                    zustand.gesehen.insert(e.endpoint)
                    aufloesen(e.endpoint, schlange: schlange, zustand: zustand) { fortsetzung.yield($0) }
                }
            }
            browser.stateUpdateHandler = { lage in
                switch lage {
                case .failed, .cancelled: fortsetzung.finish()
                default: break
                }
            }
            fortsetzung.onTermination = { _ in
                schlange.async {
                    browser.cancel()
                    zustand.verbindungen.forEach { $0.cancel() }
                    zustand.verbindungen = []
                }
            }
            browser.start(queue: schlange)
        }
    }

    /// Nur auf `schlange` angefasst.
    private final class Suchzustand: @unchecked Sendable {
        var gesehen = Set<NWEndpoint>()
        var verbindungen: [NWConnection] = []
    }

    private static func aufloesen(_ ziel: NWEndpoint, schlange: DispatchQueue, zustand: Suchzustand,
                                  gefunden: @escaping @Sendable (URL) -> Void) {
        let p = NWParameters.tcp
        // IPv4: die Schnittstelle auf 1400 nennt ihre Mitglieder ohnehin so,
        // und eine IPv6-Adresse mit Zone passt schlecht in eine URL.
        if let ip = p.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let v = NWConnection(to: ziel, using: p)
        zustand.verbindungen.append(v)
        v.stateUpdateHandler = { lage in
            switch lage {
            case .ready:
                if case let .hostPort(host, _) = v.currentPath?.remoteEndpoint, let basis = basis(host) {
                    gefunden(basis)
                }
                v.cancel()
            case .waiting, .failed:
                v.cancel()
            case .cancelled:
                zustand.verbindungen.removeAll { $0 === v }
            default:
                break
            }
        }
        v.start(queue: schlange)
        schlange.asyncAfter(deadline: .now() + 6) { v.cancel() }
    }

    static func basis(_ host: NWEndpoint.Host) -> URL? {
        switch host {
        case let .ipv4(a):
            let text = "\(a)".split(separator: "%").first.map(String.init) ?? "\(a)"
            return URL(string: "http://\(text):1400")
        case let .name(name, _):
            return URL(string: "http://\(name):1400")
        case .ipv6:
            return nil
        @unknown default:
            return nil
        }
    }
}
#endif
