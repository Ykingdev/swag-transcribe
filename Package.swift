// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SwagTranscribe",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwagTranscribe",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .testTarget(name: "SwagTranscribeTests", dependencies: ["SwagTranscribe"]),
    ],
    swiftLanguageModes: [.v5]
)
