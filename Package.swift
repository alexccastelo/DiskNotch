// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskNotch",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "StorageCore", targets: ["StorageCore"]),
        .executable(name: "DiskNotch", targets: ["DiskNotch"]),
        .executable(name: "DiskNotchWidget", targets: ["DiskNotchWidget"]),
        .executable(name: "disknotch-probe", targets: ["disknotch-probe"]),
    ],
    targets: [
        .target(name: "StorageCore"),
        .target(name: "DiskNotchUI", dependencies: ["StorageCore"]),
        .executableTarget(name: "DiskNotch", dependencies: ["StorageCore", "DiskNotchUI"]),
        // Extensão de widgets. O build-app.sh empacota o executável como
        // DiskNotch.app/Contents/PlugIns/DiskNotchWidget.appex.
        .executableTarget(
            name: "DiskNotchWidget",
            dependencies: ["StorageCore", "DiskNotchUI"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            // Como o Xcode faz: a entrada é _NSExtensionMain, que registra o tipo da
            // extensão antes de chamar o @main do WidgetBundle. Sem isso, a extensão
            // cai ao iniciar e o widget não aparece na galeria.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-application_extension",
                                           "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .executableTarget(name: "disknotch-probe", dependencies: ["StorageCore"]),
    ]
)
