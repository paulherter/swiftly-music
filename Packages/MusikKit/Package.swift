// swift-tools-version: 6.0
import PackageDescription

// **Alles an Swiftly Music, was sich ohne Oberfläche prüfen lässt.**
//
// Gemeinsame Modelle für Jellyfin und Subsonic, die Quelle als Protokoll mit
// einer Umsetzung je Server, Liedtext, Warteschlange, die Regel für Direkt
// oder Umwandeln, die Zählregel fürs Scrobbeln und die Ablage fürs Laden.
// Die App hängt nur noch Ansichten und AVFoundation daran.
let package = Package(
    name: "MusikKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "MusikKit", targets: ["MusikKit"])
    ],
    dependencies: [
        .package(path: "../JellyfinKit"),
        .package(path: "../SubsonicKit"),
    ],
    targets: [
        .target(name: "MusikKit", dependencies: [
            .product(name: "JellyfinKit", package: "JellyfinKit"),
            .product(name: "SubsonicKit", package: "SubsonicKit"),
        ]),
        .testTarget(name: "MusikKitTests", dependencies: ["MusikKit"],
                    resources: [.copy("Fixtures")])
    ]
)
