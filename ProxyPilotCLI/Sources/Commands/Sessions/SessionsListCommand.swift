import ArgumentParser
import Foundation
import ProxyPilotCore

struct SessionsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List recorded proxy sessions (request counts, token totals, time range)."
    )

    @Flag(name: .long, help: "Emit JSON output.")
    var json = false

    mutating func run() async throws {
        let events = (try? SessionReportStore.readEvents()) ?? []
        let summaries = SessionSummaryPayload.build(from: events)

        if json {
            OutputFormatter.success(
                command: "sessions list",
                data: SessionsListPayload(sessions: summaries),
                humanMessage: "",
                json: true
            )
            return
        }

        guard !summaries.isEmpty else {
            print("No recorded sessions yet.")
            return
        }

        let formatter = ISO8601DateFormatter()
        for summary in summaries {
            let range = summary.startedAt.map(formatter.string(from:)) ?? "no timestamp"
            print("\(summary.id)  [\(summary.source)]  \(summary.requestCount) request\(summary.requestCount == 1 ? "" : "s")  \(summary.totalTokens) tokens  \(range)")
        }
    }
}
