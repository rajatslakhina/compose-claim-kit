// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ComposeClaimKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "ComposeClaimKit", targets: ["ComposeClaimKit"]),
        .executable(name: "ComposeClaimDemo", targets: ["ComposeClaimDemo"])
    ],
    targets: [
        .target(name: "ComposeClaimKit"),
        .executableTarget(
            name: "ComposeClaimDemo",
            dependencies: ["ComposeClaimKit"]
        ),
        .testTarget(
            name: "ComposeClaimKitTests",
            dependencies: ["ComposeClaimKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
