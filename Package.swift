// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sillage",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Sillage", targets: ["SillageApp"])
    ],
    targets: [
        // Cœur sans interface : modèle, calculs de la journée, stockage.
        .target(name: "SillageCore"),
        // Application SwiftUI.
        .executableTarget(name: "SillageApp", dependencies: ["SillageCore"]),
        .testTarget(name: "SillageCoreTests", dependencies: ["SillageCore"]),
    ]
)
