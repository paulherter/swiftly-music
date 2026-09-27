// swift-tools-version: 6.0
import PackageDescription

// **Die Subsonic-Schnittstelle für Swiftly Music** — Navidrome, Gonic,
// Airsonic und alles, was OpenSubsonic spricht.
//
// Nur Foundation, damit das Paket später auch dorthin kann, wo JellyfinKit
// schon läuft (Android, Linux). Die Prüfsumme für die Token-Anmeldung nimmt
// CryptoKit, wo es das gibt, und sonst eine eigene Umsetzung.
let package = Package(
    name: "SubsonicKit",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "SubsonicKit", targets: ["SubsonicKit"])
    ],
    targets: [
        .target(name: "SubsonicKit"),
        .testTarget(name: "SubsonicKitTests", dependencies: ["SubsonicKit"],
                    resources: [.copy("Fixtures")])
    ]
)
