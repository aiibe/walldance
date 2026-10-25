// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Walldance",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Walldance", targets: ["Walldance"])],
    targets: [
        .target(name: "WalldanceCore"),
        .executableTarget(
            name: "Walldance",
            dependencies: ["WalldanceCore"],
            resources: [.copy("Resources/AppIcon.icns")]
        ),
        .testTarget(name: "WalldanceCoreTests", dependencies: ["WalldanceCore"])
    ]
)
