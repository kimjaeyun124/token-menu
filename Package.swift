// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexUsageMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexUsageMonitor", targets: ["CodexUsageMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "CodexUsageMonitor",
            path: "Sources/CodexUsageMonitor"
        ),
        .testTarget(
            name: "CodexUsageMonitorTests",
            dependencies: ["CodexUsageMonitor"],
            path: "Tests/CodexUsageMonitorTests"
        )
    ]
)

