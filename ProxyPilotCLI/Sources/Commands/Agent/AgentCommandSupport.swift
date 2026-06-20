import Foundation
import ProxyPilotCore

#if os(macOS)
enum AgentCommandSupport {
    static func capability() -> AgentModesCapabilityPolicy.Evaluation {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let xcodes: [AgentModesCapabilityPolicy.Xcode]
        if let installation = XcodeBuildDetector.detectSelectedInstallation() {
            xcodes = [.init(
                id: installation.path.path,
                version: installation.version,
                build: installation.build
            )]
        } else {
            xcodes = []
        }
        return AgentModesCapabilityPolicy.evaluate(
            macOSVersion: .init(
                major: os.majorVersion,
                minor: os.minorVersion,
                patch: os.patchVersion
            ),
            xcodes: xcodes
        )
    }

    static func helperSources() -> (launcher: URL, cli: URL)? {
        guard let cli = Bundle.main.executableURL else { return nil }
        let launcher = cli.deletingLastPathComponent().appendingPathComponent("proxypilot-agent")
        guard FileManager.default.isExecutableFile(atPath: cli.path),
              FileManager.default.isExecutableFile(atPath: launcher.path) else {
            return nil
        }
        return (launcher, cli)
    }

    static func manualRegistrationMessage(executable: String) -> String {
        "In Xcode Settings > Intelligence, add an agent named ProxyPilot with executable \(executable). Leave Interpreter, Arguments, and Environment empty."
    }
}
#endif
