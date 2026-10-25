// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Walldance",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Walldance", targets: ["Walldance"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "WalldanceCore"),
        .executableTarget(
            name: "Walldance",
            dependencies: ["WalldanceCore", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Resources/AppIcon.icns")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "WalldanceCoreTests", dependencies: ["WalldanceCore"])
    ]
)
