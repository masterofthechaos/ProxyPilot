import XCTest
@testable import ProxyPilot

final class SettingsSectionTests: XCTestCase {
    func testSettingsSectionsExposeNativeSidebarMetadataInOrder() {
        XCTAssertEqual(SettingsSection.allCases, [.home, .history, .proxy, .keys, .advanced, .customization])
        XCTAssertEqual(SettingsSection.sidebarSections, [.home, .history, .proxy, .keys, .advanced, .customization])
        XCTAssertEqual(SettingsSection.home.title, "Home")
        XCTAssertEqual(SettingsSection.history.title, "Session History")
        XCTAssertEqual(SettingsSection.proxy.title, "Proxy")
        XCTAssertEqual(SettingsSection.keys.title, "Keys & Providers")
        XCTAssertEqual(SettingsSection.advanced.title, "Advanced")
        XCTAssertEqual(SettingsSection.customization.title, "Customization")
        XCTAssertEqual(SettingsSection.home.systemImage, "house")
        XCTAssertEqual(SettingsSection.history.systemImage, "clock.arrow.circlepath")
        XCTAssertEqual(SettingsSection.proxy.systemImage, "network")
        XCTAssertEqual(SettingsSection.keys.systemImage, "key")
        XCTAssertEqual(SettingsSection.advanced.systemImage, "gearshape")
        XCTAssertEqual(SettingsSection.customization.systemImage, "paintpalette")
    }

    func testSettingsSectionsExposeCompactTabTitlesForCollapsedSidebar() {
        XCTAssertEqual(SettingsSection.collapsedTabSections, [.home, .history, .proxy, .keys, .advanced])
        XCTAssertEqual(SettingsSection.collapsedTabSections.map(\.compactTitle), ["Home", "History", "Proxy", "Keys & Providers", "Advanced"])
        XCTAssertFalse(SettingsSection.collapsedTabSections.contains(.customization))
    }

    func testProxySectionFocusExposesModelsTargetAndHighlightDuration() {
        XCTAssertEqual(ProxySectionFocus.models.rawValue, "models")
        XCTAssertEqual(ProxySectionFocus.models.highlightDurationSeconds, 4)
    }

    func testModelSelectionListLayoutStaysBoundedForLargeProviderCatalogs() {
        // Pins the bounded-scroll cap so a provider with hundreds of non-collapsible
        // models (e.g. OpenRouter) can't silently regress back to an unbounded frame
        // that pushes the Xcode/Agent sections off screen.
        XCTAssertEqual(ModelSelectionListLayout.minHeight, 120)
        XCTAssertEqual(ModelSelectionListLayout.maxHeight, 400)
        XCTAssertLessThan(ModelSelectionListLayout.minHeight, ModelSelectionListLayout.maxHeight)
    }
}
