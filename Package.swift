// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TinySpectrum",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TinySpectrum", targets: ["TinySpectrum"])],
    targets: [.executableTarget(name: "TinySpectrum")]
)
