// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PolybarMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "polybar-mac", targets: ["PolybarMac"])],
    targets: [.executableTarget(name: "PolybarMac", resources: [.copy("Resources")])]
)
