// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Raboj",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Raboj", targets: ["Raboj"]),
        .library(name: "RabojCore", targets: ["RabojCore"]),
    ],
    targets: [
        // Pure logic: providers, accounts, log parsing, aggregation, API clients. No UI.
        .target(name: "RabojCore"),
        // The menu bar app (AppKit + SwiftUI). Swift 5 language mode keeps AppKit glue simple.
        .executableTarget(
            name: "Raboj",
            dependencies: ["RabojCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RabojCoreTests",
            dependencies: ["RabojCore"]
        ),
    ]
)
