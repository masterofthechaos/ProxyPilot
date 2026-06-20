import ArgumentParser
import Foundation
import ProxyPilotCore

struct AgentStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show ProxyPilot Agent capability, runtime, launcher, and Xcode registration state."
    )

    @Flag(name: .long, help: "Emit JSON output.")
    var json = false

    mutating func run() async throws {
        #if os(macOS)
        let capability = AgentCommandSupport.capability()
        let runtime = AgentRuntimeManager().status()
        let registration = ACPRegistrationManager().status()
        let capabilityName: String
        let manual: Bool
        switch capability.proxyPilotAgent {
        case .hidden:
            capabilityName = "unavailable"
            manual = false
        case .manualRegistration:
            capabilityName = "manual_registration"
            manual = true
        case .automaticRegistration:
            capabilityName = "automatic_registration"
            manual = false
        }
        let runtimeName: String = switch runtime {
        case .notInstalled: "not_installed"
        case .ready: "ready"
        case .stale: "stale"
        case .corrupt: "corrupt"
        }
        let payload = AgentStatusPayload(
            capability: capabilityName,
            runtime: runtimeName,
            registration: registration.state.rawValue,
            manualRegistrationRequired: manual,
            executablePath: registration.expectedExecutablePath,
            xcodeBuild: registration.xcodeBuild
        )
        OutputFormatter.success(
            command: "agent status",
            data: payload,
            humanMessage: "ProxyPilot Agent capability: \(capabilityName)\nRuntime: \(runtimeName)\nRegistration: \(registration.state.rawValue)\nExecutable: \(registration.expectedExecutablePath)",
            json: json
        )
        #else
        OutputFormatter.error(
            command: "agent status",
            code: "E050",
            message: "ProxyPilot Agent status is only supported on macOS.",
            suggestion: nil,
            json: json
        )
        throw ExitCode.failure
        #endif
    }
}

private struct AgentStatusPayload: Encodable {
    let capability: String
    let runtime: String
    let registration: String
    let manualRegistrationRequired: Bool
    let executablePath: String
    let xcodeBuild: String?

    enum CodingKeys: String, CodingKey {
        case capability, runtime, registration
        case manualRegistrationRequired = "manual_registration_required"
        case executablePath = "executable_path"
        case xcodeBuild = "xcode_build"
    }
}
