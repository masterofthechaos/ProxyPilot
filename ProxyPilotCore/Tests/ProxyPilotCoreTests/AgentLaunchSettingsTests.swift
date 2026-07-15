import Foundation
import ProxyPilotCore
import Testing

private func temporaryFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-launch-settings-tests-\(UUID().uuidString)")
        .appendingPathComponent("current-selection.json")
}

@Test func resolveReturnsDefaultsWhenFileIsMissing() {
    let settings = AgentLaunchSettings.resolve(from: temporaryFileURL())

    #expect(settings.port == ProxyPilotDefaults.defaultPort)
    #expect(settings.modelID == nil)
    #expect(settings.upstreamLabel == nil)
    #expect(settings.providerID == nil)
    #expect(settings.upstreamURL == nil)
    #expect(settings.credentialKey == nil)
    #expect(settings.promptCachingMode == .auto)
    #expect(settings.schema == AgentLaunchSettings.currentSchema)
}

@Test func savedSettingsRoundTrip() throws {
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let written = AgentLaunchSettings(
        port: 4321,
        modelID: "glm-4.7",
        upstreamLabel: "Z.ai",
        providerID: "zai",
        upstreamURL: "https://api.example.test/v1",
        credentialKey: "CUSTOM_TEST",
        promptCachingMode: .off
    )
    try written.save(to: url)

    let read = AgentLaunchSettings.resolve(from: url)
    #expect(read == written)
}

@Test func resolveFallsBackOnCorruptJSON() throws {
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json{{".utf8).write(to: url)

    let settings = AgentLaunchSettings.resolve(from: url)
    #expect(settings == AgentLaunchSettings())
}

@Test func resolveFallsBackOnNewerSchema() throws {
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let newer = ["schema": 999, "port": 5000] as [String: Any]
    try JSONSerialization.data(withJSONObject: newer).write(to: url)

    let settings = AgentLaunchSettings.resolve(from: url)
    #expect(settings == AgentLaunchSettings())
}

@Test func resolveFallsBackOnZeroPort() throws {
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let zeroPort = AgentLaunchSettings(port: 0)
    try zeroPort.save(to: url)

    let settings = AgentLaunchSettings.resolve(from: url)
    #expect(settings.port == ProxyPilotDefaults.defaultPort)
}

@Test func resolveIgnoresUnknownKeysForForwardCompatibility() throws {
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let payload: [String: Any] = [
        "schema": 1, "port": 4100, "modelID": "abc",
        "futureField": ["nested": true],
    ]
    try JSONSerialization.data(withJSONObject: payload).write(to: url)

    let settings = AgentLaunchSettings.resolve(from: url)
    #expect(settings.port == 4100)
    #expect(settings.modelID == "abc")
}

@Test func schemaOneSettingsDecodeWithNewColdStartDefaults() throws {
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let payload: [String: Any] = [
        "schema": 1,
        "port": 4100,
        "modelID": "legacy-model",
        "upstreamLabel": "Legacy Provider",
    ]
    try JSONSerialization.data(withJSONObject: payload).write(to: url)

    let settings = AgentLaunchSettings.resolve(from: url)
    #expect(settings.port == 4100)
    #expect(settings.providerID == nil)
    #expect(settings.upstreamURL == nil)
    #expect(settings.credentialKey == nil)
    #expect(settings.promptCachingMode == .auto)
}

@Test func contextCompactionEnabledRoundTrips() throws {
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let written = AgentLaunchSettings(port: 4322, contextCompactionEnabled: true)
    try written.save(to: url)

    let read = AgentLaunchSettings.resolve(from: url)
    #expect(read.contextCompactionEnabled)
    #expect(read == written)
}

@Test func legacyFileWithoutContextCompactionKeyDecodesToDisabled() throws {
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let legacy: [String: Any] = ["schema": 3, "port": 4100, "promptCachingMode": "auto"]
    try JSONSerialization.data(withJSONObject: legacy).write(to: url)

    let settings = AgentLaunchSettings.resolve(from: url)
    #expect(settings.port == 4100)
    #expect(!settings.contextCompactionEnabled)
}

@Test func contextCompactionFieldDidNotBumpSchema() {
    // Bumping the schema would make older launcher binaries reject the
    // whole file (resolve() requires schema <= currentSchema). The field
    // is optional-decoded instead.
    #expect(AgentLaunchSettings.currentSchema == 3)
}

@Test func storageURLHonorsXDGConfigHome() {
    let url = AgentLaunchSettings.storageURL(environment: ["XDG_CONFIG_HOME": "/tmp/xdg-test"])
    #expect(url.path == "/tmp/xdg-test/proxypilot/current-selection.json")
}

@Test func storageURLFallsBackToHomeConfig() {
    let home = URL(fileURLWithPath: "/Users/example")
    let url = AgentLaunchSettings.storageURL(environment: [:], home: home)
    #expect(url.path == "/Users/example/.config/proxypilot/current-selection.json")
}

@Test func saveSetsOwnerOnlyPermissions() throws {
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try AgentLaunchSettings(port: 4000).save(to: url)

    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = (attrs[.posixPermissions] as? NSNumber)?.intValue
    #expect(permissions == 0o600)
}
