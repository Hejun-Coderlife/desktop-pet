// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pip",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Pip", targets: ["Pip"])
    ],
    targets: [
        .executableTarget(
            name: "Pip",
            path: "Sources/Pip"
        )
    ]
)
