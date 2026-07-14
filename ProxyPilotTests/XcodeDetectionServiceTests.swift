import XCTest
import ProxyPilotCore
@testable import ProxyPilot

final class XcodeDetectionServiceTests: XCTestCase {

    func testVersionCompareEqual() {
        XCTAssertTrue(XcodeDetectionService.versionCompare("26.3", isAtLeast: "26.3"))
    }

    func testVersionCompareGreater() {
        XCTAssertTrue(XcodeDetectionService.versionCompare("26.4", isAtLeast: "26.3"))
    }

    func testVersionCompareLess() {
        XCTAssertFalse(XcodeDetectionService.versionCompare("26.2", isAtLeast: "26.3"))
    }

    func testVersionCompareMajorGreater() {
        XCTAssertTrue(XcodeDetectionService.versionCompare("27.0", isAtLeast: "26.3"))
    }

    func testVersionCompareMajorLess() {
        XCTAssertFalse(XcodeDetectionService.versionCompare("25.0", isAtLeast: "26.3"))
    }

    func testVersionCompareSingleComponent() {
        XCTAssertTrue(XcodeDetectionService.versionCompare("27", isAtLeast: "26.3"))
        XCTAssertFalse(XcodeDetectionService.versionCompare("26", isAtLeast: "26.3"))
    }

    func testVersionCompareThreeComponents() {
        XCTAssertTrue(XcodeDetectionService.versionCompare("26.3.1", isAtLeast: "26.3"))
        XCTAssertTrue(XcodeDetectionService.versionCompare("26.4.0", isAtLeast: "26.3.1"))
        XCTAssertFalse(XcodeDetectionService.versionCompare("26.2.9", isAtLeast: "26.3"))
    }

    func testMinimumVersionIsCorrect() {
        XCTAssertEqual(XcodeDetectionService.minimumAgenticVersion, "26.3")
    }

    func testConfigPathUsesClaudeAgentConfig() {
        XCTAssertEqual(XcodeDetectionService.configRelativePath, "Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig")
    }

    func testAgentModesCapabilityUsesSharedPolicy() {
        let installation = XcodeInstallation(
            id: "/Applications/Xcode-beta.app",
            path: URL(fileURLWithPath: "/Applications/Xcode-beta.app"),
            version: "27.0",
            buildNumber: "27A5194q",
            isBeta: true,
            supportsAgenticCoding: true,
            claudeBinaryVersion: "27.0",
            configPath: "/Users/example/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig"
        )

        let capability = XcodeDetectionService.agentModesCapability(for: [installation])

        XCTAssertTrue(capability.isClaudeAgentAvailable)
        XCTAssertTrue(capability.proxyPilotAgent.allowsAutomaticRegistration)
    }
}
