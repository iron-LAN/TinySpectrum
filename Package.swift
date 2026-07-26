// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TinySpectrum",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TinySpectrum", targets: ["TinySpectrum"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "TinySpectrum",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(name: "TinySpectrumTests", dependencies: ["TinySpectrum"])
    ]
)
