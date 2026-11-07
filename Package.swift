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
        // Pure logic: providers, accounts, log parsing, aggregation. No UI, no I/O side effects beyond reading.
        .target(name: "RabojCore"),
        // The menu bar app.
        .executableTarget(
            name: "Raboj",
            dependencies: ["RabojCore"]
        ),
        .testTarget(
            name: "RabojCoreTests",
            dependencies: ["RabojCore"]
        ),
    ]
)
