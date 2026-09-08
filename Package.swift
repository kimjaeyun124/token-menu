// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexUsageMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexUsageMonitor", targets: ["CodexUsageMonitor"]),
        .executable(name: "CodexUsageLauncher", targets: ["CodexUsageLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "CodexUsageMonitor",
            path: "Sources/CodexUsageMonitor",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "CodexUsageLauncher",
            path: "Sources/CodexUsageLauncher"
        ),
        .testTarget(
            name: "CodexUsageMonitorTests",
            dependencies: ["CodexUsageMonitor"],
            path: "Tests/CodexUsageMonitorTests"
        )
    ]
)
