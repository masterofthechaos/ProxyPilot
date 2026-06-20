// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProxyPilotCLI",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "proxypilot", targets: ["proxypilot"]),
        .executable(name: "proxypilot-agent", targets: ["proxypilot-agent"]),
    ],
    dependencies: [
        .package(path: "../ProxyPilotCore"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0"),
    ],
    targets: [
        .executableTarget(
            name: "proxypilot",
            dependencies: [
                "ProxyPilotCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources"
        ),
        .executableTarget(
            name: "proxypilot-agent",
            dependencies: ["ProxyPilotCore"],
            path: "AgentSources"
        ),
        .testTarget(
            name: "ProxyPilotCLITests",
            dependencies: [
                "proxypilot",
                "ProxyPilotCore",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "UnitTests"
        ),
    ]
)
