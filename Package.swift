// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Lull",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lull", targets: ["Lull"])
    ],
    targets: [
        .target(name: "LullCore", path: "Sources/LullCore"),
        .executableTarget(name: "Lull", dependencies: ["LullCore"], path: "Sources/Lull"),
        .testTarget(name: "LullCoreTests", dependencies: ["LullCore"], path: "Tests/LullCoreTests")
    ]
)
