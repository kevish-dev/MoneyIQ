// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MoneyIQCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "MoneyIQCore", targets: ["MoneyIQCore"])
    ],
    targets: [
        .target(name: "MoneyIQCore"),
        .testTarget(name: "MoneyIQCoreTests", dependencies: ["MoneyIQCore"])
    ]
)
