import Foundation
import ProxyPilotCore
import Testing

private func makeRuntimeFixture() throws -> (
    root: URL,
    layout: ManagedAgentRuntimeLayout,
    manager: AgentRuntimeManager
) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-runtime-manager-tests-\(UUID().uuidString)")
    let layout = ManagedAgentRuntimeLayout(
        root: root.appendingPathComponent("runtime"),
        claudeConfigDirectory: root.appendingPathComponent("claude-config")
    )
    try FileManager.default.createDirectory(
        at: layout.nodeExecutable.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("node-fixture".utf8).write(to: layout.nodeExecutable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: layout.nodeExecutable.path)
    try FileManager.default.createDirectory(
        at: layout.adapterEntryPoint.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("adapter-fixture".utf8).write(to: layout.adapterEntryPoint)
    return (root, layout, AgentRuntimeManager(layout: layout, architecture: "arm64"))
}

@Test func runtimeStatusReportsNotInstalled() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-runtime-not-installed-\(UUID().uuidString)")
    let layout = ManagedAgentRuntimeLayout(
        root: root.appendingPathComponent("runtime"),
        claudeConfigDirectory: root.appendingPathComponent("claude-config")
    )

    #expect(AgentRuntimeManager(layout: layout).status() == .notInstalled)
}

@Test func runtimeStatusRejectsMissingManifest() throws {
    let fixture = try makeRuntimeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    #expect(fixture.manager.status() == .corrupt(
        reason: "Runtime manifest is missing or unreadable.",
        manifest: nil
    ))
}

@Test func pinnedReleaseContainsBothMacArchitecturesAndIntegrityMetadata() throws {
    let release = AgentRuntimeRelease.pinned

    #expect(release.nodeVersion == "26.3.0")
    #expect(release.adapterVersion == "0.44.0")
    #expect(release.nodeArchives["arm64"]?.sha256.count == 64)
    #expect(release.nodeArchives["x86_64"]?.sha256.count == 64)
    #expect(release.adapterIntegrity.hasPrefix("sha512-"))
}

@Test func executableLinksInstallAndRefreshStaleTargets() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-link-manager-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let launcher = root.appendingPathComponent("build/proxypilot-agent")
    let cli = root.appendingPathComponent("build/proxypilot")
    try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
    for executable in [launcher, cli] {
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }
    let manager = AgentExecutableLinkManager(binDirectory: root.appendingPathComponent("bin"))

    try manager.install(launcherSource: launcher, cliSource: cli)
    #expect(manager.launcherStatus(expectedSource: launcher) == .ready)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: manager.cliURL.path) == cli.path)

    let replacement = root.appendingPathComponent("updated/proxypilot-agent")
    try FileManager.default.createDirectory(at: replacement.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: replacement.path, contents: Data())
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: replacement.path)
    #expect(manager.launcherStatus(expectedSource: replacement) == .staleTarget(launcher.path))

    try manager.install(launcherSource: replacement, cliSource: cli)
    #expect(manager.launcherStatus(expectedSource: replacement) == .ready)
}
