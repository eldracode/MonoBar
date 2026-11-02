// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonoBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "monobar", targets: ["MonoBar"])],
    targets: [.executableTarget(name: "MonoBar", resources: [.copy("Resources")])]
)
