// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DNA", platforms: [.macOS(.v13)], products: [.executable(name: "DNA", targets: ["DNA"])], targets: [.executableTarget(name: "DNA")])
