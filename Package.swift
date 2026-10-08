// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LLMmonitor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LLMmonitor", targets: ["LLMmonitor"])],
    targets: [
        .executableTarget(name: "LLMmonitor"),
        .testTarget(name: "LLMmonitorTests", dependencies: ["LLMmonitor"])
    ]
)
