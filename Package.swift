// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskNotch",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "StorageCore", targets: ["StorageCore"]),
        .executable(name: "DiskNotch", targets: ["DiskNotch"]),
        .executable(name: "disknotch-probe", targets: ["disknotch-probe"]),
    ],
    targets: [
        .target(name: "StorageCore"),
        .executableTarget(name: "DiskNotch", dependencies: ["StorageCore"]),
        .executableTarget(name: "disknotch-probe", dependencies: ["StorageCore"]),
    ]
)
