import ArgumentParser
import Foundation
import ProxyPilotCore

struct ACPRemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove ProxyPilot's Xcode ACP agent registration."
    )

    @Flag(name: .long, help: "Emit JSON output.")
    var json: Bool = false

    mutating func run() async throws {
        #if os(macOS)
        let manager = ACPRegistrationManager()
        do {
            let result = try manager.remove()
            let message = result.removed
                ? "ProxyPilot ACP agent registration removed. If Xcode is open, quit and relaunch Xcode for changes to take effect."
                : "ProxyPilot ACP agent was not registered. No changes made."
            OutputFormatter.success(
                command: "acp remove",
                data: ACPRemovePayload(result: result),
                humanMessage: message,
                json: json
            )
        } catch ACPRegistrationManager.ManagerError.unsupportedXcodeBuild(let build) {
            OutputFormatter.error(
                command: "acp remove",
                code: "E051",
                message: "Automatic ACP registration removal is not enabled for Xcode build \(build ?? "unknown").",
                suggestion: "Remove ProxyPilot manually in Xcode Settings -> Intelligence -> Agents.",
                json: json
            )
            throw ExitCode.failure
        } catch {
            OutputFormatter.error(
                command: "acp remove",
                code: "E053",
                message: "Failed to remove ProxyPilot ACP agent registration: \(error.localizedDescription)",
                suggestion: "Check permissions under ~/Library/Developer/Xcode/CodingAssistant/ACP.",
                json: json
            )
            throw ExitCode.failure
        }
        #else
        OutputFormatter.error(
            command: "acp remove",
            code: "E050",
            message: "'proxypilot acp remove' is only supported on macOS.",
            suggestion: nil,
            json: json
        )
        throw ExitCode.failure
        #endif
    }
}

#if os(macOS)
private struct ACPRemovePayload: Encodable {
    let status: String
    let registered: Bool
    let removed: Bool
    let removedPlistPath: String?
    let xcodeBuild: String?

    init(result: ACPRegistrationManager.RemovalResult) {
        self.status = result.status.state.rawValue
        self.registered = result.status.isRegistered
        self.removed = result.removed
        self.removedPlistPath = result.removedPlistPath
        self.xcodeBuild = result.status.xcodeBuild
    }

    enum CodingKeys: String, CodingKey {
        case status
        case registered
        case removed
        case removedPlistPath = "removed_plist_path"
        case xcodeBuild = "xcode_build"
    }
}
#endif
