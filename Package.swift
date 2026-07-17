// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexUsageMonitor",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "CodexUsageMonitor", targets: ["CodexUsageMonitor"])],
    targets: [
        .executableTarget(
            name: "CodexUsageMonitor",
            path: "CodexUsageMonitor",
            exclude: ["Resources/Info.plist"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CodexUsageMonitorTests",
            dependencies: ["CodexUsageMonitor"],
            path: "Tests/CodexUsageMonitorTests",
            resources: [.process("Fixtures")]
        )
    ]
)
