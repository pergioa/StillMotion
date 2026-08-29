// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StillMotion",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StillMotion", targets: ["StillMotion"]),
        .executable(name: "StillMotionLogicChecks", targets: ["StillMotionLogicChecks"])
    ],
    targets: [
        .target(
            name: "StillMotionCore",
            path: "StillMotionCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "StillMotion",
            dependencies: ["StillMotionCore"],
            path: "StillMotion",
            exclude: ["Assets.xcassets", "Info.plist", "StillMotion.entitlements"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "StillMotionLogicChecks",
            dependencies: ["StillMotionCore"],
            path: "StillMotionTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
