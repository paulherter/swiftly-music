import Foundation
import UIKit

/// **Laden, das weiterläuft, wenn die App nicht mehr vorn ist.**
///
/// Vorher lud die Ablage über `URLSession.shared` mit einer Hintergrundfrist:
/// nach rund dreißig Sekunden außerhalb der App brach das Lied ab. Eine
/// Hintergrunds-`URLSession` übergibt den Abruf dem System; er läuft weiter,
/// auch wenn iOS die App anhält oder beendet, und die App wird geweckt, wenn
/// er fertig ist (das Vorgehen von Amperfys `DownloadManager`).
///
/// **Zugeordnet wird über eine Kennung, nicht über die Aufgabe.** Nach einem
/// Neustart gibt es die wartende Stelle im Code nicht mehr — die fertige Datei
/// kommt trotzdem an. Sie wird unter ihrer Kennung abgelegt, bis die Ablage
/// dasselbe Lied wieder anfragt, und dann ohne neuen Abruf übergeben.
///
/// **``vorn``** ist derselbe Lader mit einer gewöhnlichen Sitzung — für die
/// genaue Fassung eines laufenden Liedes (``Genaulager``). Sie gehört nicht
/// dem System: sie lädt, solange die App läuft (im Hintergrund, solange
/// Musik spielt), sofort und ohne dass iOS sie als aufschiebbar behandelt.
final class Hintergrundlader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let geteilt = Hintergrundlader(sitzungskennung: kennung)
    static let vorn = Hintergrundlader(sitzungskennung: nil)
    static let kennung = "de.paulherter.swiftly.music.laden"

    /// `nil`: eine gewöhnliche Sitzung statt der Hintergrunds-Sitzung.
    private let sitzungskennung: String?

    private init(sitzungskennung: String?) {
        self.sitzungskennung = sitzungskennung
        super.init()
    }

    private let schloss = NSLock()
    private var warten: [String: CheckedContinuation<(URL, URLResponse), any Error>] = [:]
    private var fertig: [String: (URL, URLResponse)] = [:]
    private var melder: [String: @Sendable (Double) -> Void] = [:]
    private var systemAbschluss: Systemabschluss?

    private lazy var sitzung: URLSession = {
        guard let sitzungskennung else {
            return URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        }
        let k = URLSessionConfiguration.background(withIdentifier: sitzungskennung)
        k.sessionSendsLaunchEvents = true
        k.isDiscretionary = false
        return URLSession(configuration: k, delegate: self, delegateQueue: nil)
    }()

    /// Früh anlegen — erst dann liefert das System, was während der
    /// Abwesenheit fertig geworden ist.
    func starten() { _ = sitzung }

    /// Den Abschluss des Systems merken; gerufen, wenn alle Meldungen da sind.
    func abschlussMerken(_ abschluss: @escaping () -> Void) {
        schloss.withLock { systemAbschluss = Systemabschluss(tun: abschluss) }
        starten()
    }

    private var zwischenordner: URL {
        let basis = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let ordner = basis.appendingPathComponent("Laden", isDirectory: true)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return ordner
    }

    /// **Eine Datei laden** — die vorläufige Datei gehört danach dem Aufrufer.
    func laden(_ anfrage: URLRequest, kennung: String,
               fortschritt: @escaping @Sendable (Double) -> Void) async throws -> (URL, URLResponse) {
        let laufende = await sitzung.allTasks.filter {
            $0.taskDescription == kennung && ($0.state == .running || $0.state == .suspended)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { fortsetzung in
                let schon: (URL, URLResponse)? = schloss.withLock {
                    if let da = fertig.removeValue(forKey: kennung) { return da }
                    warten[kennung] = fortsetzung
                    melder[kennung] = fortschritt
                    return nil
                }
                if let schon {
                    fortsetzung.resume(returning: schon)
                    return
                }
                if laufende.isEmpty {
                    let aufgabe = sitzung.downloadTask(with: anfrage)
                    aufgabe.taskDescription = kennung
                    aufgabe.resume()
                } else {
                    laufende.forEach { $0.resume() }
                }
            }
        } onCancel: {
            Task { [sitzung] in
                for aufgabe in await sitzung.allTasks where aufgabe.taskDescription == kennung { aufgabe.cancel() }
            }
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let kennung = downloadTask.taskDescription, let antwort = downloadTask.response else { return }
        // Die Datei gehört dem System nur bis zum Ende dieses Aufrufs.
        let ziel = zwischenordner.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: ziel)
        } catch {
            return
        }
        let wartend = schloss.withLock { () -> CheckedContinuation<(URL, URLResponse), any Error>? in
            melder[kennung] = nil
            if let w = warten.removeValue(forKey: kennung) { return w }
            // Niemand wartet (die App war beendet): aufheben, bis jemand fragt.
            if let alt = fertig[kennung] { try? FileManager.default.removeItem(at: alt.0) }
            fertig[kennung] = (ziel, antwort)
            return nil
        }
        wartend?.resume(returning: (ziel, antwort))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let kennung = task.taskDescription else { return }
        let wartend = schloss.withLock { () -> CheckedContinuation<(URL, URLResponse), any Error>? in
            melder[kennung] = nil
            return warten.removeValue(forKey: kennung)
        }
        wartend?.resume(throwing: error)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let kennung = downloadTask.taskDescription else { return }
        let melden = schloss.withLock { melder[kennung] }
        melden?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let abschluss = schloss.withLock { () -> Systemabschluss? in
            defer { systemAbschluss = nil }
            return systemAbschluss
        }
        guard let abschluss else { return }
        // Das System verlangt den Aufruf auf dem Hauptfaden.
        DispatchQueue.main.async { abschluss.tun() }
    }
}

/// Der Abschluss, den iOS beim Wecken übergibt — genau einmal zu rufen.
private struct Systemabschluss: @unchecked Sendable {
    let tun: () -> Void
}

/// Nimmt die Meldungen des Systems für die Hintergrunds-Sitzung entgegen.
final class Musikanwendung: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Hintergrundlader.geteilt.starten()
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == Hintergrundlader.kennung else {
            completionHandler()
            return
        }
        Hintergrundlader.geteilt.abschlussMerken(completionHandler)
    }
}
