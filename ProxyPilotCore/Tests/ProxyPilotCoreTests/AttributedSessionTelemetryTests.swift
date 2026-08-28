import Foundation
import Testing
@testable import ProxyPilotCore

@Suite struct AttributedSessionTelemetryTests {
    private let repoGPSSession = "082BD58F-AD95-4F47-902F-943067BBD03D"

    private func event(
        source: String,
        sessionID: String,
        model: String,
        promptTokens: Int = 100,
        completionTokens: Int = 10,
        cacheHit: Int? = nil,
        cacheMiss: Int? = nil,
        cacheWrite: Int? = nil,
        durationSeconds: TimeInterval = 1.0,
        secondsFromReference: TimeInterval = 0
    ) -> SessionReportEvent {
        SessionReportEvent(
            source: source,
            sessionID: sessionID,
            record: RequestRecord(
                timestamp: Date(timeIntervalSinceReferenceDate: secondsFromReference),
                model: model,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                promptCacheHitTokens: cacheHit,
                promptCacheMissTokens: cacheMiss,
                promptCacheWriteTokens: cacheWrite,
                durationSeconds: durationSeconds,
                path: "/v1/chat/completions",
                wasStreaming: true
            )
        )
    }

    @Test func emptyStoreAggregatesToEmpty() {
        let telemetry = AttributedSessionTelemetry.aggregate(
            events: [],
            matching: RequestAttribution(client: "repogps", sessionID: repoGPSSession.lowercased())
        )
        #expect(telemetry == .empty)
        #expect(telemetry.requests == 0)
        #expect(telemetry.averageLatencyMs == nil)
        #expect(telemetry.cacheHitRate == nil)
        #expect(telemetry.cacheAccountingAvailable == false)
    }

    /// The regression this type exists for: a store dominated by other clients must not leak
    /// their traffic into a RepoGPS session's totals, and must not report the session as idle.
    @Test func aggregationIsScopedToTheAttributedSession() {
        let events = [
            event(source: "cli", sessionID: "daemon", model: "openai/gpt-5.6-luna-pro"),
            event(source: "gui", sessionID: "gui-session", model: "deepseek-v4-flash"),
            event(source: "repogps", sessionID: repoGPSSession.lowercased(), model: "google/gemini-3.7-flash"),
            event(source: "repogps", sessionID: repoGPSSession.lowercased(), model: "google/gemini-3.7-flash"),
            event(source: "repogps", sessionID: "11111111-1111-1111-1111-111111111111", model: "other/model")
        ]

        let telemetry = AttributedSessionTelemetry.aggregate(
            events: events,
            matching: RequestAttribution(client: "repogps", sessionID: repoGPSSession.lowercased())
        )

        #expect(telemetry.requests == 2)
        #expect(telemetry.models == ["google/gemini-3.7-flash": 2])
        #expect(telemetry.promptTokens == 200)
        #expect(telemetry.completionTokens == 20)
        #expect(telemetry.totalTokens == 220)
    }

    /// The environment and the session lease carry the uppercase UUID; the store carries the
    /// lowercase form written by `RequestAttribution.validated`.
    @Test func sessionMatchingIgnoresUUIDCase() {
        let events = [event(source: "repogps", sessionID: repoGPSSession.lowercased(), model: "google/gemini-3.7-flash")]

        let upper = AttributedSessionTelemetry.aggregate(
            events: events,
            matching: RequestAttribution(client: "repogps", sessionID: repoGPSSession)
        )
        let lower = AttributedSessionTelemetry.aggregate(
            events: events,
            matching: RequestAttribution(client: "repogps", sessionID: repoGPSSession.lowercased())
        )

        #expect(upper.requests == 1)
        #expect(upper == lower)
    }

    @Test func cacheAccountingSumsAndComputesHitRate() {
        let events = [
            event(source: "repogps", sessionID: repoGPSSession.lowercased(), model: "m", cacheHit: 0, cacheMiss: 21167),
            event(source: "repogps", sessionID: repoGPSSession.lowercased(), model: "m", cacheHit: 19419, cacheMiss: 3082, cacheWrite: 7)
        ]

        let telemetry = AttributedSessionTelemetry.aggregate(
            events: events,
            matching: RequestAttribution(client: "repogps", sessionID: repoGPSSession)
        )

        #expect(telemetry.promptCacheHitTokens == 19419)
        #expect(telemetry.promptCacheMissTokens == 24249)
        #expect(telemetry.promptCacheWriteTokens == 7)
        #expect(telemetry.cacheAccountingAvailable)
        let rate = try? #require(telemetry.cacheHitRate)
        #expect(abs((rate ?? 0) - Double(19419) / Double(43668)) < 0.000_001)
    }

    /// Records without cache fields must report accounting as unavailable, not as a 0% hit rate.
    @Test func absentCacheAccountingIsReportedAsUnavailable() {
        let events = [event(source: "repogps", sessionID: repoGPSSession.lowercased(), model: "m")]
        let telemetry = AttributedSessionTelemetry.aggregate(
            events: events,
            matching: RequestAttribution(client: "repogps", sessionID: repoGPSSession)
        )
        #expect(telemetry.cacheAccountingAvailable == false)
        #expect(telemetry.cacheHitRate == nil)
    }

    @Test func averageLatencyAndBoundsUseAllMatchingRecords() {
        let events = [
            event(source: "repogps", sessionID: repoGPSSession.lowercased(), model: "m", durationSeconds: 2.0, secondsFromReference: 100),
            event(source: "repogps", sessionID: repoGPSSession.lowercased(), model: "m", durationSeconds: 3.0, secondsFromReference: 50)
        ]
        let telemetry = AttributedSessionTelemetry.aggregate(
            events: events,
            matching: RequestAttribution(client: "repogps", sessionID: repoGPSSession)
        )
        #expect(telemetry.averageLatencyMs == 2500)
        #expect(telemetry.firstRequestAt == Date(timeIntervalSinceReferenceDate: 50))
        #expect(telemetry.lastRequestAt == Date(timeIntervalSinceReferenceDate: 100))
    }

    @Test func environmentAttributionReadsTheHarnessSessionIdentity() {
        let attribution = ClientSessionEnvironment.attribution(environment: [
            "RGPS_SESSION_ID": repoGPSSession,
            "OPENCODE_CLIENT": "repogps"
        ])
        #expect(attribution?.client == "repogps")
        #expect(attribution?.sessionID == repoGPSSession.lowercased())
    }

    @Test func environmentAttributionDefaultsClientWhenOnlySessionIsExported() {
        let attribution = ClientSessionEnvironment.attribution(environment: ["RGPS_SESSION_ID": repoGPSSession])
        #expect(attribution?.client == "repogps")
    }

    /// A plain `serve --mcp` (Xcode, a bare shell) has no harness session and must stay unattributed
    /// rather than silently adopting someone else's totals.
    @Test func environmentAttributionIsAbsentOutsideAHarnessSession() {
        #expect(ClientSessionEnvironment.attribution(environment: [:]) == nil)
        #expect(ClientSessionEnvironment.attribution(environment: ["RGPS_SESSION_ID": "not-a-uuid"]) == nil)
        #expect(ClientSessionEnvironment.attribution(environment: [
            "RGPS_SESSION_ID": repoGPSSession,
            "OPENCODE_CLIENT": "somethingelse"
        ]) == nil)
    }
}
