// swift-tools-version: 5.9
// ABREngine: ABR 算法核心，可独立于 app 被 XCTest 验证。
// 见 specs/abr-player-demo/plan.md §2.1。

import PackageDescription

let package = Package(
    name: "ABREngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ABREngine", targets: ["ABREngine"]),
    ],
    targets: [
        .target(
            name: "ABREngine",
            path: "Sources/ABREngine"
        ),
        .testTarget(
            name: "ABREngineTests",
            dependencies: ["ABREngine"],
            path: "Tests/ABREngineTests"
        ),
    ]
)
