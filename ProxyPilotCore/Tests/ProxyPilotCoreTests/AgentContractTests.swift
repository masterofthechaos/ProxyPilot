import XCTest
@testable import ProxyPilotCore

final class AgentContractTests: XCTestCase {
    func testEnvelopeUsesSchemaVersionAndSortedKeys() throws {
        let payload = StatusPayload(
            running: true,
            process: .init(managed: false, pid: nil),
            http: .init(reachable: true, port: 4000, modelsCount: 12),
            effectiveStatus: "running_unmanaged"
        )
        let envelope = AgentEnvelope(command: "status", data: payload)

        let first = try AgentJSON.encode(envelope)
        let second = try AgentJSON.encode(envelope)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.contains("\"schema_version\":1"))
        XCTAssertTrue(first.contains("\"models_count\":12"))
        XCTAssertTrue(first.contains("\"port\":4000"))
        XCTAssertFalse(first.contains("\"port\":\"4000\""))
    }

    func testStatusPayloadCanExposeProxyOwner() throws {
        let payload = StatusPayload(
            running: true,
            process: .init(managed: false, pid: nil, owner: "external_or_gui"),
            http: .init(reachable: true, port: 4000, modelsCount: 3),
            effectiveStatus: "running_unmanaged"
        )
        let envelope = AgentEnvelope(command: "status", data: payload)
        let json = try AgentJSON.encode(envelope)

        XCTAssertTrue(json.contains("\"owner\":\"external_or_gui\""))
    }

    func testStatusPayloadCanExposeHTTPProbeError() throws {
        let payload = StatusPayload(
            running: false,
            process: .init(managed: false, pid: nil, owner: "none"),
            http: .init(reachable: false, port: 4000, modelsCount: nil, errorMessage: "Operation not permitted"),
            effectiveStatus: "stopped"
        )
        let envelope = AgentEnvelope(command: "status", data: payload)
        let json = try AgentJSON.encode(envelope)

        XCTAssertTrue(json.contains("\"error\":\"Operation not permitted\""))
    }

    func testErrorEnvelopeIncludesRecoverableNextAction() throws {
        let action = NextAction(
            id: "set_auth",
            kind: .cli,
            command: "proxypilot auth set --provider zai",
            destructive: false
        )
        let envelope = AgentErrorEnvelope(
            command: "start",
            error: AgentError(
                code: "E004",
                message: "No API key found for provider zai.",
                suggestion: "Run proxypilot auth set --provider zai.",
                recoverable: true
            ),
            nextActions: [action]
        )

        let json = try AgentJSON.encode(envelope)

        XCTAssertTrue(json.contains("\"ok\":false"))
        XCTAssertTrue(json.contains("\"recoverable\":true"))
        XCTAssertTrue(json.contains("\"next_actions\""))
        XCTAssertTrue(json.contains("\"kind\":\"cli\""))
    }

    func testNextActionArgumentsPreservePrimitiveTypes() throws {
        let action = NextAction(
            id: "auth_set_zai",
            kind: .mcpTool,
            tool: "auth_set",
            arguments: [
                "provider": .string("zai"),
                "port": .int(4000),
                "allow_secret_write": .bool(true),
            ],
            destructive: false
        )

        let json = try AgentJSON.encode(action)

        XCTAssertTrue(json.contains("\"provider\":\"zai\""))
        XCTAssertTrue(json.contains("\"port\":4000"))
        XCTAssertTrue(json.contains("\"allow_secret_write\":true"))
    }

    func testRoutingVerificationPayloadMarksLocalOnlyProbe() throws {
        let payload = RoutingVerificationPayload(
            localModelsReachable: true,
            modelsCount: 3,
            xcodeConfigInstalled: true,
            configuredBaseURL: "http://127.0.0.1:4000",
            portMatchesConfig: true,
            upstreamProbePerformed: false
        )

        let json = try AgentJSON.encode(AgentEnvelope(tool: "verify_routing", data: payload))

        XCTAssertTrue(json.contains("\"models_count\":3"))
        XCTAssertTrue(json.contains("\"upstream_probe_performed\":false"))
    }

    func testSessionSummaryPayloadGroupsEventsBySessionIDNewestFirst() throws {
        func record(_ timestamp: TimeInterval, prompt: Int, completion: Int) -> RequestRecord {
            RequestRecord(
                timestamp: Date(timeIntervalSince1970: timestamp),
                model: "glm-5",
                promptTokens: prompt,
                completionTokens: completion,
                durationSeconds: 1,
                path: "/v1/messages",
                wasStreaming: false
            )
        }

        let events = [
            SessionReportEvent(source: "cli", sessionID: "session-a", record: record(100, prompt: 10, completion: 5)),
            SessionReportEvent(source: "cli", sessionID: "session-a", record: record(200, prompt: 20, completion: 8)),
            SessionReportEvent(source: "gui", sessionID: "session-b", record: record(300, prompt: 30, completion: 12)),
        ]

        let summaries = SessionSummaryPayload.build(from: events)

        XCTAssertEqual(summaries.map(\.id), ["session-b", "session-a"], "Newest session (by endedAt) should sort first")

        let sessionA = try XCTUnwrap(summaries.first { $0.id == "session-a" })
        XCTAssertEqual(sessionA.source, "cli")
        XCTAssertEqual(sessionA.requestCount, 2)
        XCTAssertEqual(sessionA.totalPromptTokens, 30)
        XCTAssertEqual(sessionA.totalCompletionTokens, 13)
        XCTAssertEqual(sessionA.totalTokens, 43)
        XCTAssertEqual(sessionA.startedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(sessionA.endedAt, Date(timeIntervalSince1970: 200))
    }

    func testSessionsListPayloadEncodesSnakeCaseKeys() throws {
        let summary = SessionSummaryPayload(
            id: "session-a",
            source: "cli",
            requestCount: 2,
            totalPromptTokens: 30,
            totalCompletionTokens: 13,
            totalTokens: 43,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        )
        let json = try AgentJSON.encode(AgentEnvelope(command: "sessions list", data: SessionsListPayload(sessions: [summary])))

        XCTAssertTrue(json.contains("\"request_count\":2"))
        XCTAssertTrue(json.contains("\"total_tokens\":43"))
        XCTAssertTrue(json.contains("\"started_at\":\"1970-01-01T00:01:40Z\""), "Dates must encode as ISO 8601, not raw seconds-since-2001")
    }
}
