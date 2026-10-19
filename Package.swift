// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AndroidWebcam",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AndroidWebcam", targets: ["AndroidWebcam"])],
    targets: [.executableTarget(
        name: "AndroidWebcam",
        linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("AVFoundation"),
            .linkedFramework("CoreMedia"), .linkedFramework("CoreMediaIO"),
            .linkedFramework("CoreVideo"), .linkedFramework("VideoToolbox")
        ]
    )]
)
