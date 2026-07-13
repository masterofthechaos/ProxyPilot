import XCTest
@testable import ProxyPilot

@MainActor
final class DockTileControllerTests: XCTestCase {
    func testDockTileInstallsForAllBundlesOutsideXCTest() {
        XCTAssertTrue(ProxyPilotDockTileController.shouldInstall(
            bundleIdentifier: "com.example.ProxyPilot",
            environment: [:]
        ))
        XCTAssertTrue(ProxyPilotDockTileController.shouldInstall(
            bundleIdentifier: "com.example.ProxyPilot-alpha",
            environment: [:]
        ))
        XCTAssertFalse(ProxyPilotDockTileController.shouldInstall(
            bundleIdentifier: "com.example.ProxyPilot",
            environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"]
        ))
    }

    func testModelNameNormalizationUsesLeafAndRemovesExacto() {
        XCTAssertEqual(
            ProxyPilotDockModelName.normalize("anthropic/claude-opus-4.8-thinking:exacto"),
            "CLAUDE-OPUS-4.8-THINKING"
        )
        XCTAssertEqual(ProxyPilotDockModelName.normalize("models/gemini_3.5-pro"), "GEMINI-3.5-PRO")
        XCTAssertEqual(ProxyPilotDockModelName.normalize("  local model 🧪  "), "LOCAL MODEL")
    }

    func testInactivePresentationUsesOrdinaryIconOnly() {
        let presentation = ProxyPilotDockPresentation.derive(
            isListening: false,
            pendingRequestCount: 0,
            activeModels: [],
            lastModelSeen: "gpt-5.6",
            configuredModel: "gpt-5.6",
            hasRecentFailure: false
        )

        XCTAssertEqual(presentation.activity, .inactive)
        XCTAssertEqual(presentation.modelLabel, "")
    }

    func testIdlePresentationUsesLastModelThenConfiguredFallback() {
        let lastModel = ProxyPilotDockPresentation.derive(
            isListening: true,
            pendingRequestCount: 0,
            activeModels: [],
            lastModelSeen: "openai/gpt-5.6",
            configuredModel: "anthropic/claude-sonnet-4.5",
            hasRecentFailure: false
        )
        XCTAssertEqual(lastModel.activity, .idle)
        XCTAssertEqual(lastModel.modelLabel, "GPT-5.6")

        let configuredModel = ProxyPilotDockPresentation.derive(
            isListening: true,
            pendingRequestCount: 0,
            activeModels: [],
            lastModelSeen: "",
            configuredModel: "anthropic/claude-sonnet-4.5",
            hasRecentFailure: false
        )
        XCTAssertEqual(configuredModel.modelLabel, "CLAUDE-SONNET-4.5")
    }

    func testProcessingPresentationUsesAggregateActiveModels() {
        let single = ProxyPilotDockPresentation.derive(
            isListening: true,
            pendingRequestCount: 2,
            activeModels: ["x-ai/grok-build-0.1"],
            lastModelSeen: "",
            configuredModel: "",
            hasRecentFailure: false
        )
        XCTAssertEqual(single.activity, .processing)
        XCTAssertEqual(single.modelLabel, "GROK-BUILD-0.1")

        let multiple = ProxyPilotDockPresentation.derive(
            isListening: true,
            pendingRequestCount: 2,
            activeModels: ["openai/gpt-5.6", "anthropic/claude-opus-4.8"],
            lastModelSeen: "",
            configuredModel: "",
            hasRecentFailure: false
        )
        XCTAssertEqual(multiple.activity, .processing)
        XCTAssertEqual(multiple.modelLabel, ProxyPilotDockPresentation.neutralMultiModelLabel)

        let equivalentAliases = ProxyPilotDockPresentation.derive(
            isListening: true,
            pendingRequestCount: 2,
            activeModels: ["openai/gpt-5.6", "gpt-5.6"],
            lastModelSeen: "",
            configuredModel: "",
            hasRecentFailure: false
        )
        XCTAssertEqual(equivalentAliases.modelLabel, "GPT-5.6")
    }

    func testFailureIsBriefIdleTreatmentAndDoesNotOverrideProcessing() {
        let failed = ProxyPilotDockPresentation.derive(
            isListening: true,
            pendingRequestCount: 0,
            activeModels: [],
            lastModelSeen: "deepseek/deepseek-v4",
            configuredModel: "",
            hasRecentFailure: true
        )
        XCTAssertEqual(failed.activity, .failed)

        let stillProcessing = ProxyPilotDockPresentation.derive(
            isListening: true,
            pendingRequestCount: 1,
            activeModels: ["deepseek/deepseek-v4"],
            lastModelSeen: "",
            configuredModel: "",
            hasRecentFailure: true
        )
        XCTAssertEqual(stillProcessing.activity, .processing)
    }

    func testShortNamesFitAndLongNamesRequireMarqueeWidth() {
        let availableWidth = ProxyPilotDockTileView.signRect.width
            - (ProxyPilotDockTileView.signHorizontalInset * 2)
        XCTAssertLessThanOrEqual(ProxyPilotDockLEDMatrix.textWidth("GPT-5.6"), availableWidth)
        XCTAssertGreaterThan(
            ProxyPilotDockLEDMatrix.textWidth("CLAUDE-OPUS-4.8-THINKING"),
            availableWidth
        )
    }

    func testReduceMotionDisablesAnimation() {
        let processing = ProxyPilotDockPresentation(activity: .processing, modelLabel: "LONG-MODEL-NAME")
        XCTAssertTrue(ProxyPilotDockTileView.shouldAnimate(processing, reduceMotion: false))
        XCTAssertFalse(ProxyPilotDockTileView.shouldAnimate(processing, reduceMotion: true))
        XCTAssertFalse(ProxyPilotDockTileView.shouldAnimate(
            ProxyPilotDockPresentation(activity: .idle, modelLabel: "GPT-5.6"),
            reduceMotion: false
        ))
    }
}
