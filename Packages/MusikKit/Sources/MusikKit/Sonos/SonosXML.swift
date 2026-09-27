import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// **Ein XML-Baum, so klein wie nötig** — für die Antworten eines
/// Sonos-Lautsprechers: SOAP-Hüllen, `device_description.xml`,
/// `ZoneGroupState` und DIDL-Lite.
///
/// Namensräume zählen nicht: `s:Envelope`, `u:PlayResponse` und `dc:title`
/// heißen hier `Envelope`, `PlayResponse` und `title`. Sonos mischt die
/// Vorsilben je nach Firmware, gemeint ist immer dasselbe.
public struct SonosKnoten: Sendable, Equatable {
    public let name: String
    public let attribute: [String: String]
    public internal(set) var kinder: [SonosKnoten]
    public internal(set) var text: String

    /// Das erste direkte Kind mit diesem Namen.
    public func kind(_ name: String) -> SonosKnoten? {
        kinder.first { $0.name == name }
    }

    /// Alle direkten Kinder mit diesem Namen.
    public func kinder(_ name: String) -> [SonosKnoten] {
        kinder.filter { $0.name == name }
    }

    /// Der erste Knoten mit diesem Namen, irgendwo darunter (oder er selbst).
    public func finde(_ name: String) -> SonosKnoten? {
        if self.name == name { return self }
        for k in kinder {
            if let treffer = k.finde(name) { return treffer }
        }
        return nil
    }

    /// Der Text des ersten Knotens mit diesem Namen darunter, ohne Rand.
    public func wert(_ name: String) -> String? {
        finde(name).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Liest ein Dokument. `nil`, wenn es kein wohlgeformtes XML ist.
    public static func lesen(_ daten: Data) -> SonosKnoten? {
        let leser = Leser()
        let parser = XMLParser(data: daten)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = leser
        guard parser.parse(), let wurzel = leser.wurzel else { return nil }
        return wurzel
    }

    public static func lesen(_ text: String) -> SonosKnoten? {
        lesen(Data(text.utf8))
    }

    static func ohneVorsilbe(_ name: String) -> String {
        guard let doppelpunkt = name.lastIndex(of: ":") else { return name }
        return String(name[name.index(after: doppelpunkt)...])
    }

    /// Baut den Baum beim Lesen auf — ein Stapel offener Knoten.
    private final class Leser: NSObject, XMLParserDelegate {
        var stapel: [SonosKnoten] = []
        var wurzel: SonosKnoten?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            var attr: [String: String] = [:]
            for (k, v) in attributes { attr[SonosKnoten.ohneVorsilbe(k)] = v }
            stapel.append(SonosKnoten(name: SonosKnoten.ohneVorsilbe(name), attribute: attr, kinder: [], text: ""))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stapel.isEmpty else { return }
            stapel[stapel.count - 1].text += string
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            guard !stapel.isEmpty, let s = String(data: block, encoding: .utf8) else { return }
            stapel[stapel.count - 1].text += s
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            guard let fertig = stapel.popLast() else { return }
            if stapel.isEmpty {
                wurzel = fertig
            } else {
                stapel[stapel.count - 1].kinder.append(fertig)
            }
        }
    }
}

public enum SonosText {
    /// **Für Text und Attribute in XML.** Die fünf Zeichen, die XML kennt —
    /// eine Adresse mit `&` darin wäre sonst kein XML mehr.
    public static func maskieren(_ s: String) -> String {
        var aus = ""
        aus.reserveCapacity(s.count)
        for z in s {
            switch z {
            case "&": aus += "&amp;"
            case "<": aus += "&lt;"
            case ">": aus += "&gt;"
            case "\"": aus += "&quot;"
            case "'": aus += "&apos;"
            default: aus.append(z)
            }
        }
        return aus
    }
}
