import ArgumentParser
import Foundation
import ProxyPilotCore

struct ACPRegisterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "register",
        abstract: "Register ProxyPilot as an Xcode ACP agent."
    )

    @Flag(name: .long, help: "Emit JSON output.")
    var json: Bool = false

    mutating func run() async throws {
        #if os(macOS)
        let manager = ACPRegistrationManager()
        do {
            let result = try manager.register()
            OutputFormatter.success(
                command: "acp register",
                data: ACPRegisterPayload(result: result),
                humanMessage: "ProxyPilot ACP agent registered.\nExecutable: \(result.status.expectedExecutablePath)\nIf Xcode is open, quit and relaunch Xcode for changes to take effect.",
                json: json
            )
        } catch ACPRegistrationManager.ManagerError.unsupportedXcodeBuild(let build) {
            OutputFormatter.error(
                command: "acp register",
                code: "E051",
                message: "Automatic ACP registration is not enabled for Xcode build \(build ?? "unknown").",
                suggestion: "Use Xcode Settings -> Intelligence -> Agents to add ProxyPilot manually. Executable: \(manager.executablePath)",
                json: json
            )
            throw ExitCode.failure
        } catch {
            OutputFormatter.error(
                command: "acp register",
                code: "E052",
                message: "Failed to register ProxyPilot ACP agent: \(error.localizedDescription)",
                suggestion: "Check permissions under ~/Library/Developer/Xcode/CodingAssistant/ACP.",
                json: json
            )
            throw ExitCode.failure
        }
        #else
        OutputFormatter.error(
            command: "acp register",
            code: "E050",
            message: "'proxypilot acp register' is only supported on macOS.",
            suggestion: nil,
            json: json
        )
        throw ExitCode.failure
        #endif
    }
}

#if os(macOS)
private struct ACPRegisterPayload: Encodable {
    let status: String
    let registered: Bool
    let created: Bool
    let updated: Bool
    let adopted: Bool
    let plistPath: String?
    let expectedExecutablePath: String
    let xcodeBuild: String?

    init(result: ACPRegistrationManager.RegistrationResult) {
        self.status = result.status.state.rawValue
        self.registered = result.status.isRegistered
        self.created = result.created
        self.updated = result.updated
        self.adopted = result.adopted
        self.plistPath = result.status.plistPath
        self.expectedExecutablePath = result.status.expectedExecutablePath
        self.xcodeBuild = result.status.xcodeBuild
    }

    enum CodingKeys: String, CodingKey {
        case status
        case registered
        case created
        case updated
        case adopted
        case plistPath = "plist_path"
        case expectedExecutablePath = "expected_executable_path"
        case xcodeBuild = "xcode_build"
    }
}
#endif
