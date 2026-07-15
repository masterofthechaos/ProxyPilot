import Testing
import Foundation
import ProxyPilotCore
@testable import proxypilot

struct CLIContextCompactionModeTests {
    private static let optedInSettings = AgentLaunchSettings(contextCompactionEnabled: true)
    private static let optedOutSettings = AgentLaunchSettings(contextCompactionEnabled: false)

    @Test func allModesResolveDisabledWhileFeatureGateIsClosed() {
        // The flag stays parseable so scripts don't break, but until the
        // shipped ruleset provides MVP functionality every mode is a no-op.
        for mode in CLIContextCompactionMode.allCases {
            let config = mode.configuration(
                launchSettings: Self.optedInSettings,
                featureAvailable: false
            )
            #expect(!config.isEnabled, "\(mode)")
        }
    }

    @Test func modesResolveNormallyOnceFeatureGateOpens() {
        #expect(CLIContextCompactionMode.on
            .configuration(launchSettings: Self.optedOutSettings, featureAvailable: true).isEnabled)
        #expect(!CLIContextCompactionMode.off
            .configuration(launchSettings: Self.optedInSettings, featureAvailable: true).isEnabled)
        #expect(CLIContextCompactionMode.auto
            .configuration(launchSettings: Self.optedInSettings, featureAvailable: true).isEnabled)
        #expect(!CLIContextCompactionMode.auto
            .configuration(launchSettings: Self.optedOutSettings, featureAvailable: true).isEnabled)
    }

    @Test func productionGateIsCurrentlyOpen() {
        // Pins the live default: ruleset v2 (authored 2026-07-14 from the
        // Xcode agent wall capture) provides MVP functionality, so the
        // default featureAvailable argument resolves modes normally.
        #expect(ContextCompactionFeatureGate.isAvailable)
        #expect(CLIContextCompactionMode.on.configuration(launchSettings: Self.optedInSettings).isEnabled)
        #expect(!CLIContextCompactionMode.off.configuration(launchSettings: Self.optedInSettings).isEnabled)
    }
}
