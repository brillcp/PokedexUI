// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BattleKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "BattleKit", targets: ["BattleKit"]),
    ],
    targets: [
        .target(name: "BattleKit", path: "Sources/BattleKit"),
        .testTarget(name: "BattleKitTests", dependencies: ["BattleKit"], path: "Tests/BattleKitTests"),
    ]
)
