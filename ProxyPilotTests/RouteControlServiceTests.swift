import XCTest
@testable import ProxyPilot

final class RouteControlServiceTests: XCTestCase {

    // MARK: - Binary resolution

    /// The GUI must never reach the RepoGPS route through a PATH lookup. A
    /// stale `~/.local/bin/proxypilot` (v1.10.3 was found in the wild) has no
    /// `route` subcommand at all, so PATH resolution fails silently.
    func testCandidateBinariesPreferSharedRuntimeAndExcludePATH() {
        let home = URL(fileURLWithPath: "/Users/example")
        let candidates = RouteControlService.candidateBinaries(home: home)

        XCTAssertEqual(candidates.first?.path, "/Users/example/.proxypilot/bin/proxypilot")
        XCTAssertTrue(candidates.contains { $0.path.hasPrefix("/Applications/ProxyPilot.app") })
        XCTAssertFalse(candidates.contains { $0.path.contains(".local/bin") })
    }

    // MARK: - Capability gate

    func testRouteControlRequiresTheAdvertisedCapability() {
        let supported = Data(#"{"route_control":1,"active_model_aliasing":1}"#.utf8)
        let unsupported = Data(#"{"active_model_aliasing":1}"#.utf8)
        let explicitZero = Data(#"{"route_control":0}"#.utf8)

        XCTAssertTrue(RouteControlService.supportsRouteControl(supported))
        XCTAssertFalse(RouteControlService.supportsRouteControl(unsupported))
        XCTAssertFalse(RouteControlService.supportsRouteControl(explicitZero))
        XCTAssertFalse(RouteControlService.supportsRouteControl(Data("not json".utf8)))
    }

    // MARK: - Status parsing

    func testParsesLiveRouteStatus() {
        let payload = Data(#"""
        {"applied":true,"model":"google/gemini-3.5-flash","owner":"cli","port":4000,
         "provider":"openrouter","reachable":true,"selected":true,
         "verification_state":"models_ready"}
        """#.utf8)

        let status = RouteControlService.parseStatus(payload)

        XCTAssertEqual(status?.provider, "openrouter")
        XCTAssertEqual(status?.model, "google/gemini-3.5-flash")
        XCTAssertEqual(status?.owner, "cli")
        XCTAssertEqual(status?.port, 4000)
        XCTAssertEqual(status?.verificationState, "models_ready")
        XCTAssertTrue(status?.isServing == true)
    }

    /// `route status` reports null provider/model when nothing is selected —
    /// that must read as "no route", never as a route to an empty model.
    func testParsesUnselectedRouteWithoutInventingAModel() {
        let payload = Data(#"""
        {"applied":false,"model":null,"owner":"none","port":4000,"provider":null,
         "reachable":false,"selected":false,"verification_state":"stopped"}
        """#.utf8)

        let status = RouteControlService.parseStatus(payload)

        XCTAssertNil(status?.provider)
        XCTAssertNil(status?.model)
        XCTAssertFalse(status?.isServing == true)
        XCTAssertEqual(status?.summary, "No route selected")
    }

    func testNonObjectOutputIsTreatedAsUnavailableRatherThanAnEmptyRoute() {
        XCTAssertNil(RouteControlService.parseStatus(Data("Error: unexpected argument".utf8)))
        XCTAssertNil(RouteControlService.parseStatus(Data("[]".utf8)))
    }

    // MARK: - Summary wording

    /// `selected` only means `route.json` records a preference. Only `applied`
    /// means the daemon is serving it, and the difference is the whole reason
    /// the menu bar used to look authoritative over RepoGPS while being inert.
    func testSummaryDistinguishesSelectedFromActuallyServing() {
        var status = RouteControlService.Status()
        status.selected = true

        status.applied = false
        status.reachable = false
        XCTAssertEqual(status.summary, "Selected, not running")

        status.reachable = true
        XCTAssertEqual(status.summary, "Proxy reachable, serving a different route")

        status.applied = true
        status.port = 4477
        XCTAssertEqual(status.summary, "Serving on port 4477")
    }

    // MARK: - Failure reporting

    func testFailureMessagePrefersStructuredErrorThenRawText() {
        let structured = Data(#"{"ok":false,"error":{"message":"Another route switch is in progress"}}"#.utf8)
        XCTAssertEqual(
            RouteControlService.failureMessage(from: structured),
            "Another route switch is in progress"
        )

        let plain = Data("Error: Could not stop CLI-owned route\n".utf8)
        XCTAssertEqual(
            RouteControlService.failureMessage(from: plain),
            "Error: Could not stop CLI-owned route"
        )

        XCTAssertEqual(RouteControlService.failureMessage(from: Data()), "Route change failed.")
    }
}
