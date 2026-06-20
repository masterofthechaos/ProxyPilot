import ArgumentParser
import Foundation
import ProxyPilotCore

struct AgentInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install the managed ProxyPilot Agent runtime and register it with Xcode when proven safe."
    )

    @Flag(name: .long, help: "Emit JSON output.")
    var json = false

    mutating func run() async throws {
        #if os(macOS)
        let capability = AgentCommandSupport.capability()
        guard capability.proxyPilotAgent.showsProxyPilotAgentControls else {
            OutputFormatter.error(
                command: "agent install",
                code: "E054",
                message: "ProxyPilot Agent requires macOS 27 or newer and Xcode 27 or newer.",
                suggestion: "Continue using Claude Agent routing on this Mac.",
                json: json
            )
            throw ExitCode.failure
        }
        guard let helpers = AgentCommandSupport.helperSources() else {
            OutputFormatter.error(
                command: "agent install",
                code: "E055",
                message: "The proxypilot-agent helper is missing beside the ProxyPilot CLI.",
                suggestion: "Reinstall ProxyPilot or build both CLI products before retrying.",
                json: json
            )
            throw ExitCode.failure
        }

        let runtimeManager = AgentRuntimeManager()
        let linkManager = AgentExecutableLinkManager()
        let registrationManager = ACPRegistrationManager()
        do {
            let manifest = try await runtimeManager.install()
            try linkManager.install(launcherSource: helpers.launcher, cliSource: helpers.cli)

            let registration: String
            let message: String
            switch capability.proxyPilotAgent {
            case .automaticRegistration(let xcode):
                _ = try registrationManager.register(xcodeBuild: xcode.build)
                registration = "automatic"
                message = "ProxyPilot Agent installed and registered. Reopen Xcode Intelligence settings if it does not appear immediately."
            case .manualRegistration:
                registration = "manual_required"
                message = "ProxyPilot Agent runtime installed. \(AgentCommandSupport.manualRegistrationMessage(executable: registrationManager.executablePath)) Reopen Xcode Intelligence settings afterward."
            case .hidden:
                throw ExitCode.failure
            }

            OutputFormatter.success(
                command: "agent install",
                data: AgentInstallPayload(
                    status: "installed",
                    registration: registration,
                    nodeVersion: manifest.nodeVersion,
                    adapterVersion: manifest.adapterVersion,
                    executablePath: registrationManager.executablePath
                ),
                humanMessage: message,
                json: json
            )
        } catch let exit as ExitCode {
            throw exit
        } catch {
            OutputFormatter.error(
                command: "agent install",
                code: "E056",
                message: error.localizedDescription,
                suggestion: "Retry from the ProxyPilot app or run 'proxypilot agent status --json' for details.",
                json: json
            )
            throw ExitCode.failure
        }
        #else
        OutputFormatter.error(
            command: "agent install",
            code: "E050",
            message: "ProxyPilot Agent installation is only supported on macOS.",
            suggestion: nil,
            json: json
        )
        throw ExitCode.failure
        #endif
    }
}

private struct AgentInstallPayload: Encodable {
    let status: String
    let registration: String
    let nodeVersion: String
    let adapterVersion: String
    let executablePath: String

    enum CodingKeys: String, CodingKey {
        case status, registration
        case nodeVersion = "node_version"
        case adapterVersion = "adapter_version"
        case executablePath = "executable_path"
    }
}
