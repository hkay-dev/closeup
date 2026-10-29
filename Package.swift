// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Closeup",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Closeup", targets: ["Closeup"])],
    targets: [.executableTarget(
        name: "Closeup",
        linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("AVFoundation"), .linkedFramework("AVKit"),
            .linkedFramework("CoreMedia"), .linkedFramework("CoreMediaIO"),
            .linkedFramework("CoreVideo"), .linkedFramework("VideoToolbox")
        ]
    )]
)
