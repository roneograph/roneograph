// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScannerKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ScannerKit", targets: ["ScannerKit"]),
        .library(name: "ScannerModels", targets: ["ScannerModels"]),
        .executable(name: "page-cleanup", targets: ["PageCleanupTool"]),
    ],
    targets: [
        .target(name: "ScannerKit", resources: [.copy("Resources/UVDoc.mlmodelc"), .copy("Resources/UVDoc-LICENSE")]),
        .target(name: "ScannerModels", dependencies: ["ScannerKit"]),
        .target(name: "ScannerKitTesting", dependencies: ["ScannerKit"]),
        .executableTarget(name: "PageCleanupTool", dependencies: ["ScannerKit"]),
        .testTarget(name: "ScannerKitTests", dependencies: ["ScannerKit", "ScannerKitTesting"]),
        .testTarget(name: "ScannerModelsTests", dependencies: ["ScannerModels", "ScannerKit", "ScannerKitTesting"]),
    ]
)
