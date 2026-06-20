import Foundation
import ProxyPilotCore
import Testing

private let supportedBuild = "27A5194q"

private func temporaryACPDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("acp-registration-manager-tests-\(UUID().uuidString)")
        .appendingPathComponent("ACP", isDirectory: true)
}

private func manager(at directory: URL) -> ACPRegistrationManager {
    ACPRegistrationManager(
        acpDirectoryURL: directory,
        executablePath: "/Users/example/.proxypilot/bin/proxypilot-agent"
    )
}

private func plistObject(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try #require(
        PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    )
}

@Test func registerWritesMinimalACPPlistAndOmitsInterpreter() throws {
    let directory = temporaryACPDirectory()
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    let subject = manager(at: directory)

    let result = try subject.register(xcodeBuild: supportedBuild)

    #expect(result.created)
    #expect(!result.updated)
    #expect(result.status.state == .registered)
    let plistPath = try #require(result.status.plistPath)
    let object = try plistObject(at: URL(fileURLWithPath: plistPath))
    #expect(object["agent"] as? String == "/Users/example/.proxypilot/bin/proxypilot-agent")
    #expect(object["name"] as? String == "ProxyPilot")
    #expect((object["arguments"] as? [String]) == [])
    #expect((object["environment"] as? [String: String]) == [:])
    #expect(object["interpreter"] == nil)

    let attrs = try FileManager.default.attributesOfItem(atPath: plistPath)
    #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func registerIsIdempotent() throws {
    let directory = temporaryACPDirectory()
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    let subject = manager(at: directory)

    let first = try subject.register(xcodeBuild: supportedBuild)
    let second = try subject.register(xcodeBuild: supportedBuild)

    #expect(first.status.plistPath == second.status.plistPath)
    #expect(!second.created)
    #expect(second.updated)
    #expect(!second.adopted)
    let plists = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .filter { $0.hasSuffix(".plist") }
    #expect(plists.count == 1)
}

@Test func registerAdoptsExistingProxyPilotEntryWithStalePath() throws {
    let directory = temporaryACPDirectory()
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let staleURL = directory.appendingPathComponent("STALE.plist")
    let stale: [String: Any] = [
        "agent": "/old/proxypilot-agent",
        "arguments": [],
        "environment": [:],
        "name": "ProxyPilot",
    ]
    try PropertyListSerialization.data(fromPropertyList: stale, format: .xml, options: 0)
        .write(to: staleURL)
    let subject = manager(at: directory)

    let before = subject.status(xcodeBuild: supportedBuild)
    let result = try subject.register(xcodeBuild: supportedBuild)

    #expect(before.state == .stalePath)
    #expect(result.adopted)
    #expect(URL(fileURLWithPath: try #require(result.status.plistPath)).lastPathComponent == staleURL.lastPathComponent)
    #expect(result.status.registeredExecutablePath == "/Users/example/.proxypilot/bin/proxypilot-agent")
}

@Test func removeDeletesOnlyMatchingProxyPilotRegistration() throws {
    let directory = temporaryACPDirectory()
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let subject = manager(at: directory)
    let registered = try subject.register(xcodeBuild: supportedBuild)
    let otherURL = directory.appendingPathComponent("OTHER.plist")
    let other: [String: Any] = [
        "agent": "/usr/bin/true",
        "arguments": [],
        "environment": [:],
        "name": "Other Agent",
    ]
    try PropertyListSerialization.data(fromPropertyList: other, format: .xml, options: 0)
        .write(to: otherURL)

    let removal = try subject.remove(xcodeBuild: supportedBuild)

    #expect(removal.removed)
    #expect(removal.removedPlistPath == registered.status.plistPath)
    #expect(removal.status.state == .notRegistered)
    #expect(FileManager.default.fileExists(atPath: otherURL.path))
    if let path = registered.status.plistPath {
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}

@Test func statusReportsUnknownSeedWithoutMutatingFiles() throws {
    let directory = temporaryACPDirectory()
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    let subject = manager(at: directory)

    let status = subject.status(xcodeBuild: "27A0000z")

    #expect(status.state == .notRegistered)
    #expect(status.xcodeBuild == "27A0000z")
    #expect(!status.automaticRegistrationSupported)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    #expect(throws: ACPRegistrationManager.ManagerError.unsupportedXcodeBuild("27A0000z")) {
        try subject.register(xcodeBuild: "27A0000z")
    }
}

@Test func removeIsSafeOnUnprovenBuildBecauseItOnlyDeletesMatchingRegistration() throws {
    let directory = temporaryACPDirectory()
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    let subject = manager(at: directory)
    _ = try subject.register(xcodeBuild: supportedBuild)

    let result = try subject.remove(xcodeBuild: "27A9999z")

    #expect(result.removed)
    #expect(result.status.state == .notRegistered)
    #expect(!result.status.automaticRegistrationSupported)
}

@Test func xcodeBuildDetectorPrefersVersionPlistProductBuildVersion() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("xcode-build-detector-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let contents = root
        .appendingPathComponent("Xcode-beta.app")
        .appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

    let info: [String: Any] = [
        "CFBundleIdentifier": "com.apple.dt.Xcode",
        "DTXcodeBuild": "27A5194o",
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
    let version: [String: Any] = [
        "ProductBuildVersion": "27A5194q",
    ]
    try PropertyListSerialization.data(fromPropertyList: version, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("version.plist"))

    let build = XcodeBuildDetector.detectBuildNumber(at: root.appendingPathComponent("Xcode-beta.app"))

    #expect(build == "27A5194q")
}
