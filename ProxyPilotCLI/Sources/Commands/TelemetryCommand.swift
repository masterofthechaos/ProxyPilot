import ArgumentParser
import Foundation
import ProxyPilotCore

struct TelemetryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "telemetry", abstract: "Report attributed usage for one client session.")
    @Option(name: .long) var client: String
    @Option(name: .long) var sessionId: String
    @Flag(name: .long) var json = false
    func run() throws {
        guard let attribution = RequestAttribution.validated(client: client, sessionID: sessionId) else { throw ValidationError("Only client=repogps with a valid UUID session-id is supported") }
        let telemetry = AttributedSessionTelemetry.aggregate(events: try SessionReportStore.readEvents(), matching: attribution)
        var payload: [String: Any] = ["client": attribution.client, "session_id": attribution.sessionID, "requests": telemetry.requests, "prompt_tokens": telemetry.promptTokens, "completion_tokens": telemetry.completionTokens, "total_tokens": telemetry.totalTokens, "models": telemetry.models, "cache_accounting_available": telemetry.cacheAccountingAvailable]
        if let averageLatencyMs = telemetry.averageLatencyMs { payload["average_latency_ms"] = averageLatencyMs }
        if telemetry.cacheAccountingAvailable {
            payload["prompt_cache_hit_tokens"] = telemetry.promptCacheHitTokens
            payload["prompt_cache_miss_tokens"] = telemetry.promptCacheMissTokens
            payload["prompt_cache_write_tokens"] = telemetry.promptCacheWriteTokens
            if let rate = telemetry.cacheHitRate { payload["cache_hit_rate"] = rate }
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]); print(String(decoding: data, as: UTF8.self))
    }
}
