// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shy",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Shy",
            path: "Sources/Shy",
            // The pages' JavaScript, copied into the app by build.sh (Scripts.swift).
            exclude: ["Scripts"],
            // Same reasoning as the canvas app next door: the whole interface is
            // main-thread by nature, and Swift 6's strict isolation buys nothing
            // here but ceremony.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Claude's way into Shy's pages (Agent.swift), shipped beside the
        // app's binary.
        .executableTarget(
            name: "shy-mcp",
            path: "Sources/ShyMCP",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ShyTests",
            dependencies: ["Shy"],
            path: "Tests/ShyTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
