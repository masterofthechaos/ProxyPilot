import Foundation
import ProxyPilotCore

actor LifecycleGate {
    private var busy = false

    func withLock<T>(_ operation: () async throws -> T) async rethrows -> T {
        while busy {
            try? await Task.sleep(for: .milliseconds(25))
        }
        busy = true
        defer { busy = false }
        return try await operation()
    }
}

enum MCPStatusPortResolver {
    static func probePort(currentPort: UInt16?, requestedPort: UInt16) -> UInt16 {
        currentPort ?? requestedPort
    }
}

struct MCPStopPlan {
    let text: String
    let nextActions: [NextAction]
}

enum MCPStopResponsePlanner {
    static func plan(configInstalled: Bool) -> MCPStopPlan {
        guard configInstalled else {
            return MCPStopPlan(
                text: "ProxyPilot stopped. Xcode config is not installed.",
                nextActions: []
            )
        }

        return MCPStopPlan(
            text: "ProxyPilot stopped. Xcode config is still installed — remove it only after the user explicitly confirms they want direct Anthropic routing restored.",
            nextActions: [MCPXcodeConfigConsent.removeNextAction()]
        )
    }
}

enum MCPXcodeConfigConsent {
    static let environmentVariable = "PROXYPILOT_MCP_ALLOW_XCODE_CONFIG"
    static let argumentName = "allow_xcode_config_write"

    static var environmentAllowsWrites: Bool {
        guard let raw = ProcessInfo.processInfo.environment[environmentVariable]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return ["1", "true", "yes", "allow"].contains(raw)
    }

    static func installNextAction(port: UInt16) -> NextAction {
        if environmentAllowsWrites {
            return NextAction(
                id: "install_xcode_config",
                kind: .mcpTool,
                tool: "xcode_config_install",
                arguments: [
                    "port": .int(Int(port)),
                    argumentName: .bool(true),
                ],
                message: "Only run after the user explicitly confirms this persistent Xcode Agent routing change.",
                destructive: true
            )
        }

        return NextAction(
            id: "authorize_xcode_config_install",
            kind: .user,
            command: "\(environmentVariable)=1 proxypilot serve --mcp",
            message: "Ask the user to authorize Xcode Agent config writes before installing routing config. They can either run `proxypilot config install` themselves or restart MCP with PROXYPILOT_MCP_ALLOW_XCODE_CONFIG=1, then approve a call with allow_xcode_config_write: true.",
            destructive: true
        )
    }

    static func removeNextAction() -> NextAction {
        if environmentAllowsWrites {
            return NextAction(
                id: "remove_xcode_config",
                kind: .mcpTool,
                tool: "xcode_config_remove",
                arguments: [argumentName: .bool(true)],
                message: "Only run after the user explicitly confirms this persistent Xcode Agent routing change.",
                destructive: true
            )
        }

        return NextAction(
            id: "authorize_xcode_config_remove",
            kind: .user,
            command: "\(environmentVariable)=1 proxypilot serve --mcp",
            message: "Ask the user to authorize Xcode Agent config writes before removing routing config. They can either run `proxypilot config remove` themselves or restart MCP with PROXYPILOT_MCP_ALLOW_XCODE_CONFIG=1, then approve a call with allow_xcode_config_write: true.",
            destructive: true
        )
    }
}

struct SessionStatsToolPayload: Encodable {
    let requests: Int
    let totalTokens: Int
    let promptTokens: Int
    let completionTokens: Int
    let averageLatencyMs: Int?
    let uptimeSeconds: Int
    let models: [String: Int]
    let promptCacheHitTokens: Int
    let promptCacheMissTokens: Int
    let promptCacheWriteTokens: Int
    let cacheHitRate: Double?
    let cacheAccountingAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case requests
        case totalTokens = "total_tokens"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case averageLatencyMs = "average_latency_ms"
        case uptimeSeconds = "uptime_seconds"
        case models
        case promptCacheHitTokens = "prompt_cache_hit_tokens"
        case promptCacheMissTokens = "prompt_cache_miss_tokens"
        case promptCacheWriteTokens = "prompt_cache_write_tokens"
        case cacheHitRate = "cache_hit_rate"
        case cacheAccountingAvailable = "cache_accounting_available"
    }
}
