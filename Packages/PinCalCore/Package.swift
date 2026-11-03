// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PinCalCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PinCalCore", targets: ["PinCalCore"]),
    ],
    targets: [
        .target(name: "PinCalCore"),
        .testTarget(name: "PinCalCoreTests", dependencies: ["PinCalCore"]),
    ]
)
