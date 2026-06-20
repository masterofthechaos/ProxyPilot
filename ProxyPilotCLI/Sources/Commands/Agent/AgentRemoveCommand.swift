import ArgumentParser
import ProxyPilotCore

struct AgentRemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove ProxyPilot Agent registration, launcher links, and managed runtime."
    )

    @Flag(name: .long, help: "Emit JSON output.")
    var json = false

    mutating func run() async throws {
        #if os(macOS)
        do {
            let removal = try ACPRegistrationManager().remove()
            try AgentExecutableLinkManager().remove()
            try AgentRuntimeManager().remove()
            OutputFormatter.success(
                command: "agent remove",
                data: AgentRemovePayload(status: "removed", registrationRemoved: removal.removed),
                humanMessage: "ProxyPilot Agent support removed. Reopen Xcode Intelligence settings if the entry remains visible.",
                json: json
            )
        } catch {
            OutputFormatter.error(
                command: "agent remove",
                code: "E057",
                message: error.localizedDescription,
                suggestion: "Check permissions under ~/.proxypilot and Xcode's CodingAssistant directory.",
                json: json
            )
            throw ExitCode.failure
        }
        #else
        OutputFormatter.error(
            command: "agent remove",
            code: "E050",
            message: "ProxyPilot Agent removal is only supported on macOS.",
            suggestion: nil,
            json: json
        )
        throw ExitCode.failure
        #endif
    }
}

private struct AgentRemovePayload: Encodable {
    let status: String
    let registrationRemoved: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case registrationRemoved = "registration_removed"
    }
}
