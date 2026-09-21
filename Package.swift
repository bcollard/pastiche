// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pastiche",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pastiche",
            path: "Sources/Pastiche",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PasticheTests",
            dependencies: ["Pastiche"],
            path: "Tests/PasticheTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
