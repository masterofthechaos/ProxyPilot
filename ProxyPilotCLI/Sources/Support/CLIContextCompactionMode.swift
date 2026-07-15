import ArgumentParser
import Foundation
import ProxyPilotCore

enum CLIContextCompactionMode: String, CaseIterable, ExpressibleByArgument {
    /// Follow the shared GUI/CLI selection persisted in AgentLaunchSettings.
    case auto
    case on
    case off

    init?(argument: String) {
        switch argument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "auto":
            self = .auto
        case "on", "enabled", "true":
            self = .on
        case "off", "disabled", "false":
            self = .off
        default:
            return nil
        }
    }

    func configuration(
        launchSettings: @autoclosure () -> AgentLaunchSettings = AgentLaunchSettings.resolve(),
        featureAvailable: Bool = ContextCompactionFeatureGate.isAvailable
    ) -> ContextCompactionConfiguration {
        // Feature-gated until the shipped ruleset provides MVP functionality.
        // The flag stays parseable so scripts don't break; it just resolves
        // to disabled while the gate is unmet.
        guard featureAvailable else { return .disabled }
        switch self {
        case .auto:
            return ContextCompactionConfiguration(isEnabled: launchSettings().contextCompactionEnabled)
        case .on:
            return .enabled
        case .off:
            return .disabled
        }
    }
}
