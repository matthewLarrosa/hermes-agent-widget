// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "HermesCore", platforms: [.macOS(.v15), .iOS(.v18)], products: [.library(name: "HermesCore", targets: ["HermesCore"])], targets: [.target(name: "HermesCore"), .testTarget(name: "HermesCoreTests", dependencies: ["HermesCore"])])
