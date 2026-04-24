// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TempSweep",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TempSweepCore", targets: ["TempSweepCore"]),
        .executable(name: "TempSweepApp", targets: ["TempSweepApp"])
    ],
    targets: [
        .target(name: "TempSweepCore"),
        .executableTarget(
            name: "TempSweepApp",
            dependencies: ["TempSweepCore"],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "TempSweepCoreTests",
            dependencies: ["TempSweepCore"]
        )
    ]
)
