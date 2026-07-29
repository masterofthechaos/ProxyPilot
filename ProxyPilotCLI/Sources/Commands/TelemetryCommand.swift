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
        let events = try SessionReportStore.readEvents().filter { $0.source == attribution.client && $0.sessionID.caseInsensitiveCompare(attribution.sessionID) == .orderedSame }
        var models: [String: Int] = [:]; var prompt = 0; var completion = 0
        for event in events { models[event.record.model, default: 0] += 1; prompt += event.record.promptTokens; completion += event.record.completionTokens }
        let payload: [String: Any] = ["client": attribution.client, "session_id": attribution.sessionID, "requests": events.count, "prompt_tokens": prompt, "completion_tokens": completion, "total_tokens": prompt + completion, "models": models]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]); print(String(decoding: data, as: UTF8.self))
    }
}
