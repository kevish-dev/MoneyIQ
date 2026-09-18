// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MoneyIQCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MoneyIQCore", targets: ["MoneyIQCore"])
    ],
    targets: [
        .target(name: "MoneyIQCore"),
        .testTarget(name: "MoneyIQCoreTests", dependencies: ["MoneyIQCore"])
    ]
)
