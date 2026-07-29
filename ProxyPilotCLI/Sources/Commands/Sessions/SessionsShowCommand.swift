import ArgumentParser
import Foundation
import ProxyPilotCore

struct SessionsShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a recorded session's request history, and optionally its decrypted input/output logs."
    )

    @Argument(help: "Session ID, as printed by 'proxypilot sessions list'.")
    var sessionID: String

    @Flag(name: .long, help: "Include decrypted input/output log records for this session, if input & output logging is enabled.")
    var includeLogs = false

    @Flag(name: .long, help: "Emit JSON output.")
    var json = false

    mutating func run() async throws {
        let events = (try? SessionReportStore.readEvents()) ?? []
        // Stored IDs are mixed-case (daemon vs. attributed sessions), so match
        // case-insensitively — `sessions show` should accept the ID however the
        // caller's tool reported it.
        let matching = events.filter { $0.sessionID.caseInsensitiveCompare(sessionID) == .orderedSame }

        guard let summary = SessionSummaryPayload.build(from: matching).first else {
            OutputFormatter.error(
                command: "sessions show",
                code: "E060",
                message: "No recorded session found with ID '\(sessionID)'.",
                suggestion: "Run 'proxypilot sessions list' to see recorded session IDs.",
                json: json
            )
            throw ExitCode.failure
        }

        let requests = matching
            .sorted { $0.record.timestamp < $1.record.timestamp }
            .map(\.record)

        var logs: [InputOutputLogRecord]?
        if includeLogs {
            if let recorder = try? InputOutputLoggingRecorder.productionIfKeyExists(source: "cli") {
                logs = (try? await recorder.readRecords(matchingSessionID: sessionID)) ?? []
            } else {
                logs = []
            }
        }

        let payload = SessionDetailPayload(summary: summary, requests: requests, logs: logs)

        if json {
            OutputFormatter.success(command: "sessions show", data: payload, humanMessage: "", json: true)
            return
        }

        let formatter = ISO8601DateFormatter()
        print("Session \(summary.id) [\(summary.source)]")
        print("Requests: \(summary.requestCount)  Tokens: \(summary.totalTokens) (prompt: \(summary.totalPromptTokens), completion: \(summary.totalCompletionTokens))")
        for request in requests {
            let latency = request.durationSeconds < 1
                ? "\(Int((request.durationSeconds * 1000).rounded()))ms"
                : String(format: "%.2fs", request.durationSeconds)
            print("  \(formatter.string(from: request.timestamp))  \(request.model)  \(request.promptTokens + request.completionTokens) tokens  \(latency)  \(request.path)")
        }

        if let logs {
            print("")
            print("Input/output logs: \(logs.count) record\(logs.count == 1 ? "" : "s")")
            for log in logs {
                print("  \(formatter.string(from: log.timestamp))  \(log.model)  \(log.wasStreaming ? "streaming" : "non-streaming")  status=\(log.statusCode.map(String.init) ?? "?")")
            }
        } else if includeLogs {
            print("")
            print("Input/output logs: none available (logging not enabled, or no encryption key found).")
        }
    }
}
