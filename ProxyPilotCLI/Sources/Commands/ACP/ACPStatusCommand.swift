import ArgumentParser
import Foundation
import ProxyPilotCore

struct ACPStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show whether ProxyPilot is registered as an Xcode ACP agent."
    )

    @Flag(name: .long, help: "Emit JSON output.")
    var json: Bool = false

    mutating func run() async throws {
        #if os(macOS)
        let manager = ACPRegistrationManager()
        let status = manager.status()
        OutputFormatter.success(
            command: "acp status",
            data: ACPStatusPayload(status: status),
            humanMessage: humanMessage(for: status),
            json: json,
            nextActions: nextActions(for: status)
        )
        #else
        OutputFormatter.error(
            command: "acp status",
            code: "E050",
            message: "'proxypilot acp status' is only supported on macOS.",
            suggestion: nil,
            json: json
        )
        throw ExitCode.failure
        #endif
    }
}

#if os(macOS)
func humanMessage(for status: ACPRegistrationManager.Status) -> String {
    let build = status.xcodeBuild ?? "unknown"
    switch status.state {
    case .registered:
        return "ProxyPilot ACP agent is registered.\nXcode build: \(build)\nExecutable: \(status.registeredExecutablePath ?? status.expectedExecutablePath)\nPlist: \(status.plistPath ?? "(unknown)")"
    case .stalePath:
        return "ProxyPilot ACP agent is registered with a stale executable path.\nXcode build: \(build)\nCurrent: \(status.registeredExecutablePath ?? "(unknown)")\nExpected: \(status.expectedExecutablePath)\nRun 'proxypilot acp register' to update it."
    case .notRegistered:
        return "ProxyPilot ACP agent is not registered.\nXcode build: \(build)\nExpected executable: \(status.expectedExecutablePath)"
    case .unknownSeed:
        return "ProxyPilot ACP automatic registration is not enabled for this Xcode build.\nXcode build: \(build)\nUse Xcode Settings -> Intelligence -> Agents to add ProxyPilot manually if needed.\nExecutable: \(status.expectedExecutablePath)"
    }
}

func nextActions(for status: ACPRegistrationManager.Status) -> [NextAction] {
    switch status.state {
    case .registered, .unknownSeed:
        return []
    case .stalePath, .notRegistered:
        return [
            NextAction(
                id: "register_acp_agent",
                kind: .cli,
                command: "proxypilot acp register",
                message: "Register ProxyPilot as an Xcode ACP agent.",
                destructive: false
            ),
        ]
    }
}

struct ACPStatusPayload: Encodable {
    let status: String
    let registered: Bool
    let agentName: String
    let expectedExecutablePath: String
    let registeredExecutablePath: String?
    let plistPath: String?
    let xcodeBuild: String?

    init(status: ACPRegistrationManager.Status) {
        self.status = status.state.rawValue
        self.registered = status.isRegistered
        self.agentName = status.agentName
        self.expectedExecutablePath = status.expectedExecutablePath
        self.registeredExecutablePath = status.registeredExecutablePath
        self.plistPath = status.plistPath
        self.xcodeBuild = status.xcodeBuild
    }

    enum CodingKeys: String, CodingKey {
        case status
        case registered
        case agentName = "agent_name"
        case expectedExecutablePath = "expected_executable_path"
        case registeredExecutablePath = "registered_executable_path"
        case plistPath = "plist_path"
        case xcodeBuild = "xcode_build"
    }
}
#endif
