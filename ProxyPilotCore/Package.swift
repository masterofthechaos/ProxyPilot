// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProxyPilotCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ProxyPilotCore", targets: ["ProxyPilotCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.77.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "ProxyPilotCore",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                // CryptoKit replacement on non-Apple platforms (SHA256 for
                // prompt-cache session keys). Apple platforms keep CryptoKit.
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ]
        ),
        .testTarget(
            name: "ProxyPilotCoreTests",
            dependencies: [
                "ProxyPilotCore",
                .product(name: "NIOEmbedded", package: "swift-nio"),
            ]
        ),
    ]
)
