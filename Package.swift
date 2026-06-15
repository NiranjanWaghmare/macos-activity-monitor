// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ActivityMonitor",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "ActivityMonitor",
            path: "Sources/ActivityMonitor",
            swiftSettings: [
                // System-level C interop + Carbon callbacks read much cleaner
                // under the Swift 5 concurrency model. Keep this relaxed.
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "ActivityMonitorTests",
            dependencies: ["ActivityMonitor"],
            path: "Tests/ActivityMonitorTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
