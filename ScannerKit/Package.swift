// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScannerKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ScannerKit", targets: ["ScannerKit"]),
    ],
    targets: [
        .target(name: "ScannerKit"),
        .testTarget(name: "ScannerKitTests", dependencies: ["ScannerKit"]),
    ]
)
