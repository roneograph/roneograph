// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScannerKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ScannerKit", targets: ["ScannerKit"]),
        .executable(name: "page-cleanup", targets: ["PageCleanupTool"]),
    ],
    targets: [
        .target(name: "ScannerKit"),
        .executableTarget(name: "PageCleanupTool", dependencies: ["ScannerKit"]),
        .testTarget(name: "ScannerKitTests", dependencies: ["ScannerKit"]),
    ]
)
