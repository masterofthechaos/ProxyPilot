import Foundation
import ProxyPilotCore
import Testing
@testable import proxypilot

struct MCPToolPayloadTests {
    @Test func sessionStatsPayloadEncodesStructuredFieldsForAgents() throws {
        let firstRequest = Date(timeIntervalSince1970: 1_756_200_000)
        let lastRequest = Date(timeIntervalSince1970: 1_756_200_600)
        let payload = SessionStatsToolPayload(
            requests: 2,
            totalTokens: 30,
            promptTokens: 10,
            completionTokens: 20,
            averageLatencyMs: 123,
            uptimeSeconds: 9,
            models: ["glm-5.1": 2],
            promptCacheHitTokens: 4,
            promptCacheMissTokens: 6,
            promptCacheWriteTokens: 3,
            cacheHitRate: 0.4,
            cacheAccountingAvailable: true,
            scope: .attributedSession,
            attributed: true,
            sessionID: "082bd58f-1c3d-4a2b-9f10-6d5e4c3b2a19",
            source: "repogps",
            firstRequestAt: firstRequest,
            lastRequestAt: lastRequest
        )

        let json = try AgentJSON.encode(payload)
        let data = Data(json.utf8)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["requests"] as? Int == 2)
        #expect(object["total_tokens"] as? Int == 30)
        #expect(object["prompt_tokens"] as? Int == 10)
        #expect(object["completion_tokens"] as? Int == 20)
        #expect(object["average_latency_ms"] as? Int == 123)
        #expect(object["uptime_seconds"] as? Int == 9)
        #expect((object["models"] as? [String: Int])?["glm-5.1"] == 2)
        #expect(object["prompt_cache_hit_tokens"] as? Int == 4)
        #expect(object["prompt_cache_miss_tokens"] as? Int == 6)
        #expect(object["prompt_cache_write_tokens"] as? Int == 3)
        #expect(object["cache_hit_rate"] as? Double == 0.4)
        #expect(object["cache_accounting_available"] as? Bool == true)

        // The attribution fields are the point of the payload: without them an agent cannot
        // tell "this session sent nothing" from "this process is not the one serving traffic".
        #expect(object["scope"] as? String == "attributed_session")
        #expect(object["attributed"] as? Bool == true)
        #expect(object["session_id"] as? String == "082bd58f-1c3d-4a2b-9f10-6d5e4c3b2a19")
        #expect(object["source"] as? String == "repogps")

        let iso = ISO8601DateFormatter()
        #expect(object["first_request_at"] as? String == iso.string(from: firstRequest))
        #expect(object["last_request_at"] as? String == iso.string(from: lastRequest))
    }

    @Test func sessionStatsPayloadLabelsUnattributedInProcessZeros() throws {
        // The regression this guards: a caller with no harness session gets real zeros from an
        // in-process proxy that never served anything. They must arrive labelled, and the
        // optional attribution fields must be absent rather than empty-but-present.
        let payload = SessionStatsToolPayload(
            requests: 0,
            totalTokens: 0,
            promptTokens: 0,
            completionTokens: 0,
            averageLatencyMs: nil,
            uptimeSeconds: 12,
            models: [:],
            promptCacheHitTokens: 0,
            promptCacheMissTokens: 0,
            promptCacheWriteTokens: 0,
            cacheHitRate: nil,
            cacheAccountingAvailable: false,
            scope: .inProcessProxy,
            attributed: false,
            sessionID: nil,
            source: nil,
            firstRequestAt: nil,
            lastRequestAt: nil
        )

        let json = try AgentJSON.encode(payload)
        let data = Data(json.utf8)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["requests"] as? Int == 0)
        #expect(object["scope"] as? String == "in_process_proxy")
        #expect(object["attributed"] as? Bool == false)
        #expect(object["session_id"] == nil)
        #expect(object["source"] == nil)
        #expect(object["first_request_at"] == nil)
        #expect(object["last_request_at"] == nil)
    }

    @Test func proxyStopPlanDoesNotSuggestConfigRemovalWhenConfigIsNotInstalled() {
        let plan = MCPStopResponsePlanner.plan(configInstalled: false)

        #expect(plan.text == "ProxyPilot stopped. Xcode config is not installed.")
        #expect(plan.nextActions.isEmpty)
    }

    @Test func proxyStopPlanSuggestsConfigRemovalWhenConfigIsInstalled() {
        let plan = MCPStopResponsePlanner.plan(configInstalled: true)

        #expect(plan.text.contains("Xcode config is still installed"))
        #expect(plan.nextActions.map(\.id) == ["authorize_xcode_config_remove"])
        #expect(plan.nextActions.map(\.kind) == [.user])
        #expect(plan.nextActions.allSatisfy { $0.destructive })
    }

    @Test func xcodeConfigInstallNextActionRequiresUserAuthorizationByDefault() {
        let action = MCPXcodeConfigConsent.installNextAction(port: 4123)

        #expect(action.id == "authorize_xcode_config_install")
        #expect(action.kind == .user)
        #expect(action.tool == nil)
        #expect(action.command?.contains(MCPXcodeConfigConsent.environmentVariable) == true)
        #expect(action.message?.contains(MCPXcodeConfigConsent.argumentName) == true)
        #expect(action.destructive)
    }

    @Test func xcodeConfigRemoveNextActionRequiresUserAuthorizationByDefault() {
        let action = MCPXcodeConfigConsent.removeNextAction()

        #expect(action.id == "authorize_xcode_config_remove")
        #expect(action.kind == .user)
        #expect(action.tool == nil)
        #expect(action.command?.contains(MCPXcodeConfigConsent.environmentVariable) == true)
        #expect(action.message?.contains(MCPXcodeConfigConsent.argumentName) == true)
        #expect(action.destructive)
    }

    @Test func ioSessionLogConsentIsDisabledByDefault() {
        #expect(MCPIOSessionLogConsent.environmentAllowsReads == false)
        #expect(MCPIOSessionLogConsent.environmentVariable == "PROXYPILOT_MCP_ALLOW_IO_LOGS")
        #expect(MCPIOSessionLogConsent.argumentName == "allow_io_log_read")
    }

    @Test func statusProbeUsesRequestedPortWhenNoManagedPortExists() {
        let port = MCPStatusPortResolver.probePort(currentPort: nil, requestedPort: 4024)

        #expect(port == 4024)
    }

    @Test func statusProbeUsesManagedPortWhenProxyIsRunning() {
        let port = MCPStatusPortResolver.probePort(currentPort: 4025, requestedPort: 4024)

        #expect(port == 4025)
    }
}
