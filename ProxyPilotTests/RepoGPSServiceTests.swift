import XCTest
@testable import ProxyPilot

final class RepoGPSServiceTests: XCTestCase {
    @MainActor
    func testRepoGPSInstallActivatesProxyPilotCLIBeforePayloadInstallation() async {
        var activationCount = 0
        let service = RepoGPSService(
            home: URL(fileURLWithPath: "/private/tmp/repogps-install-test"),
            bundle: Bundle(for: Self.self),
            cliActivator: {
                activationCount += 1
                return nil
            }
        )

        await service.install()

        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(service.lastError, "This ProxyPilot build does not contain a RepoGPS payload.")
    }

    @MainActor
    func testProxyPilotCLIActivationFailureStopsRepoGPSInstallWithActionableError() async {
        let service = RepoGPSService(
            home: URL(fileURLWithPath: "/private/tmp/repogps-install-test"),
            bundle: Bundle(for: Self.self),
            cliActivator: { "permission denied" }
        )

        let installed = await service.installProxyPilotCLI()

        XCTAssertFalse(installed)
        XCTAssertEqual(service.lastError, "Could not install ProxyPilot CLI: permission denied")
    }

    func testGettingStartedContractExplainsTerminalEntryAndOrientationSafety() {
        XCTAssertEqual(RepoGPSGettingStarted.starterCommand, "cd /path/to/your/project\n~/.repogps/bin/rgps")
        XCTAssertEqual(
            RepoGPSGettingStarted.commands.map(\.command),
            [
                "cd /path/to/your/project\n~/.repogps/bin/rgps",
                "~/.repogps/bin/rgps --dir /path/to/your/project",
                "~/.repogps/bin/rgps orient --mode quick",
                "~/.repogps/bin/rgps orient --mode standard",
                "~/.repogps/bin/rgps orient --mode deep",
            ]
        )
        XCTAssertTrue(RepoGPSGettingStarted.commands[2].explanation.contains("does not create"))
        XCTAssertTrue(RepoGPSGettingStarted.commands[3].explanation.contains("confirmation"))
        XCTAssertFalse(RepoGPSGettingStarted.commands.contains { $0.command.contains("open -a") })
    }

    func testTerminalLauncherUsesExactPathsAndDeletesOnlyItsOwnScript() {
        let script = RepoGPSService.terminalLauncherScript(
            executable: URL(fileURLWithPath: "/Users/tester/.repogps/bin/rgps"),
            repository: URL(fileURLWithPath: "/Users/tester/Projects/Micah's App")
        )

        XCTAssertTrue(script.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(script.contains(#"/bin/rm -f -- "$0" || true"#))
        XCTAssertTrue(script.contains("cd -- '/Users/tester/Projects/Micah'\\''s App'"))
        XCTAssertTrue(script.contains("exec '/Users/tester/.repogps/bin/rgps' --dir '/Users/tester/Projects/Micah'\\''s App'"))
        XCTAssertFalse(script.contains("~/.repogps"))
        XCTAssertFalse(script.contains("open -a"))
    }

    func testDistributionContractDecodesManagedPayload() throws {
        let data = Data(#"{"installed":true,"ownership":"managed","current_version":"0.2.0","previous_version":"0.1.0","executable":"/tmp/rgps","behavior_pack_version":"1","engine_ready":true}"#.utf8)
        let status = try XCTUnwrap(RepoGPSService.parseDistributionStatus(data))
        XCTAssertEqual(status.currentVersion, "0.2.0")
        XCTAssertEqual(status.previousVersion, "0.1.0")
        XCTAssertEqual(status.behaviorPackVersion, "1")
        XCTAssertTrue(status.engineReady)
    }

    func testIndependentUpdateContractDecodesSignedFeedStatus() throws {
        let data = Data(#"{"state":"update-available","installed_version":"0.3.0","latest_version":"0.4.0","ownership":"managed","update_available":true,"compatible":true,"feed_url":"https://micah.chat/downloads/repogps-versions.json"}"#.utf8)

        let status = try XCTUnwrap(RepoGPSService.parseUpdateStatus(data))

        XCTAssertEqual(status.state, "update-available")
        XCTAssertEqual(status.installedVersion, "0.3.0")
        XCTAssertEqual(status.latestVersion, "0.4.0")
        XCTAssertEqual(status.ownership, "managed")
        XCTAssertTrue(status.updateAvailable)
        XCTAssertTrue(status.compatible)
        XCTAssertEqual(status.feedURL.absoluteString, "https://micah.chat/downloads/repogps-versions.json")
    }

    func testBundledFallbackComparisonNeverDowngradesManagedRepoGPS() {
        XCTAssertTrue(RepoGPSService.isStableVersion("0.4.0", newerThan: "0.3.0"))
        XCTAssertTrue(RepoGPSService.isStableVersion("0.10.0", newerThan: "0.9.0"))
        XCTAssertFalse(RepoGPSService.isStableVersion("0.4.0", newerThan: "0.4.0"))
        XCTAssertFalse(RepoGPSService.isStableVersion("0.3.0", newerThan: "0.4.0"))
    }

    func testLiveSessionContractDecodesCockpitFields() throws {
        let id = UUID()
        let data = Data("""
        {"active":true,"lease":{"session_id":"\(id.uuidString)","repository":"/tmp/repo","mode":"deep","activity":"tool","started_at":"2026-08-25T20:00:00Z","repogps_version":"0.2.0","behavior_pack_version":"1"},"pending_signals":2,"acknowledged_signals":3}
        """.utf8)
        let status = try XCTUnwrap(RepoGPSService.parseSessionStatus(data))
        XCTAssertTrue(status.active)
        XCTAssertEqual(status.lease?.sessionID, id)
        XCTAssertEqual(status.lease?.mode, "deep")
        XCTAssertEqual(status.lease?.activity, "tool")
        XCTAssertEqual(status.pendingSignals, 2)
        XCTAssertEqual(status.acknowledgedSignals, 3)
    }

    func testLiveSessionContractAcceptsRepoGPSReferenceDateTimestamp() throws {
        let id = UUID()
        let referenceSeconds = 809_401_052.0
        let data = Data("""
        {"active":true,"lease":{"session_id":"\(id.uuidString)","repository":"/tmp/repo","mode":"normal","activity":"idle","started_at":\(referenceSeconds),"repogps_version":"0.2.0","behavior_pack_version":"1"},"pending_signals":0,"acknowledged_signals":0}
        """.utf8)

        let status = try XCTUnwrap(RepoGPSService.parseSessionStatus(data))

        XCTAssertTrue(status.active)
        XCTAssertEqual(status.lease?.sessionID, id)
        XCTAssertEqual(status.lease?.startedAt, Date(timeIntervalSinceReferenceDate: referenceSeconds))
    }
}
