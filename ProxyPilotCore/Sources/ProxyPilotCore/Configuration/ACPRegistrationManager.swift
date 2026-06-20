import Foundation

/// Manages Xcode 27 custom ACP agent registrations for ProxyPilot.
///
/// Xcode persists custom ACP agents as one plist per agent under
/// `~/Library/Developer/Xcode/CodingAssistant/ACP/`. The v2.0.0 Add-oracle
/// established the minimal schema used here: `agent`, `arguments`,
/// `environment`, and `name`. An empty Interpreter field is represented by
/// omitting the `interpreter` key entirely.
public struct ACPRegistrationManager: Sendable {
    public static let defaultAgentName = "ProxyPilot"
    public static let supportedXcodeBuilds = AgentModesCapabilityPolicy.provenAutomaticRegistrationBuilds

    public enum State: String, Codable, Sendable {
        case registered
        case stalePath = "stale_path"
        case notRegistered = "not_registered"
        case unknownSeed = "unknown_seed"
    }

    public struct Status: Sendable, Equatable {
        public let state: State
        public let agentName: String
        public let expectedExecutablePath: String
        public let registeredExecutablePath: String?
        public let plistPath: String?
        public let xcodeBuild: String?
        public let automaticRegistrationSupported: Bool

        public var isRegistered: Bool {
            state == .registered
        }
    }

    public struct RegistrationResult: Sendable, Equatable {
        public let status: Status
        public let created: Bool
        public let updated: Bool
        public let adopted: Bool
    }

    public struct RemovalResult: Sendable, Equatable {
        public let status: Status
        public let removed: Bool
        public let removedPlistPath: String?
    }

    public enum ManagerError: LocalizedError, Equatable {
        case unsupportedXcodeBuild(String?)
        case invalidRegistrationPlist(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedXcodeBuild(let build):
                if let build, !build.isEmpty {
                    return "Xcode build \(build) is not enabled for automatic ACP registration."
                }
                return "No supported Xcode 27 build was detected for automatic ACP registration."
            case .invalidRegistrationPlist(let path):
                return "Could not read ACP registration plist at \(path)."
            }
        }
    }

    public let acpDirectoryURL: URL
    public let agentName: String
    public let executablePath: String
    public let supportedBuilds: Set<String>

    public init(
        acpDirectoryURL: URL = ACPRegistrationManager.defaultACPDirectoryURL(),
        agentName: String = ACPRegistrationManager.defaultAgentName,
        executablePath: String = ACPRegistrationManager.defaultExecutablePath(),
        supportedBuilds: Set<String> = ACPRegistrationManager.supportedXcodeBuilds
    ) {
        self.acpDirectoryURL = acpDirectoryURL
        self.agentName = agentName
        self.executablePath = executablePath
        self.supportedBuilds = supportedBuilds
    }

    public static func defaultACPDirectoryURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home
            .appendingPathComponent("Library/Developer/Xcode/CodingAssistant/ACP", isDirectory: true)
    }

    public static func defaultExecutablePath(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        home
            .appendingPathComponent(".proxypilot/bin/proxypilot-agent")
            .path
    }

    public func status(xcodeBuild: String? = XcodeBuildDetector.detectSelectedBuild()) -> Status {
        let match = matchingRegistration()
        let baseState: State
        if let match {
            baseState = match.registration.agent == executablePath ? .registered : .stalePath
        } else {
            baseState = .notRegistered
        }

        return Status(
            state: baseState,
            agentName: agentName,
            expectedExecutablePath: executablePath,
            registeredExecutablePath: match?.registration.agent,
            plistPath: match?.url.path,
            xcodeBuild: xcodeBuild,
            automaticRegistrationSupported: isSupported(build: xcodeBuild)
        )
    }

    @discardableResult
    public func register(
        xcodeBuild: String? = XcodeBuildDetector.detectSelectedBuild()
    ) throws -> RegistrationResult {
        guard isSupported(build: xcodeBuild) else {
            throw ManagerError.unsupportedXcodeBuild(xcodeBuild)
        }

        try FileManager.default.createDirectory(at: acpDirectoryURL, withIntermediateDirectories: true)
        let existing = matchingRegistration()
        let registration = Registration(agent: executablePath, name: agentName)
        let destination = existing?.url ?? acpDirectoryURL
            .appendingPathComponent("\(UUID().uuidString.uppercased()).plist")

        try write(registration, to: destination)
        let postStatus = status(xcodeBuild: xcodeBuild)
        return RegistrationResult(
            status: postStatus,
            created: existing == nil,
            updated: existing != nil,
            adopted: existing != nil && existing?.registration.agent != executablePath
        )
    }

    @discardableResult
    public func remove(
        xcodeBuild: String? = XcodeBuildDetector.detectSelectedBuild()
    ) throws -> RemovalResult {
        guard let existing = matchingRegistration() else {
            return RemovalResult(status: status(xcodeBuild: xcodeBuild), removed: false, removedPlistPath: nil)
        }

        try FileManager.default.removeItem(at: existing.url)
        return RemovalResult(
            status: status(xcodeBuild: xcodeBuild),
            removed: true,
            removedPlistPath: existing.url.path
        )
    }

    private func isSupported(build: String?) -> Bool {
        guard let build, !build.isEmpty else { return false }
        return supportedBuilds.contains(build)
    }

    private func matchingRegistration() -> (url: URL, registration: Registration)? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: acpDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        return urls
            .filter { $0.pathExtension == "plist" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> (URL, Registration)? in
                guard let registration = try? readRegistration(at: url) else {
                    return nil
                }
                guard registration.name == agentName || registration.agent == executablePath else {
                    return nil
                }
                return (url, registration)
            }
            .first
    }

    private func readRegistration(at url: URL) throws -> Registration {
        let data = try Data(contentsOf: url)
        let decoder = PropertyListDecoder()
        return try decoder.decode(Registration.self, from: data)
    }

    private func write(_ registration: Registration, to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(registration)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private struct Registration: Codable, Equatable {
        var agent: String
        var arguments: [String]
        var environment: [String: String]
        var name: String

        init(agent: String, name: String) {
            self.agent = agent
            self.arguments = []
            self.environment = [:]
            self.name = name
        }
    }
}

public enum XcodeBuildDetector {
    public struct Installation: Equatable, Sendable {
        public let path: URL
        public let version: String
        public let build: String?

        public init(path: URL, version: String, build: String?) {
            self.path = path
            self.version = version
            self.build = build
        }
    }

    public static func detectSelectedBuild() -> String? {
        detectSelectedInstallation()?.build
    }

    public static func detectSelectedInstallation() -> Installation? {
        for path in selectedBundleCandidates() {
            let plistURL = path.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                  ) as? [String: Any],
                  plist["CFBundleIdentifier"] as? String == "com.apple.dt.Xcode",
                  let version = plist["CFBundleShortVersionString"] as? String else {
                continue
            }
            return Installation(path: path, version: version, build: detectBuildNumber(at: path))
        }
        return nil
    }

    private static func selectedBundleCandidates() -> [URL] {
        var candidates: [URL] = []
        if let selected = selectedDeveloperDirectory() {
            candidates.append(selected)
        }
        candidates.append(URL(fileURLWithPath: "/Applications/Xcode-beta.app"))
        candidates.append(URL(fileURLWithPath: "/Applications/Xcode.app"))

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func selectedDeveloperDirectory() -> URL? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        var url = URL(fileURLWithPath: output)
        while url.path != "/" {
            if url.pathExtension == "app" {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    public static func detectBuildNumber(at appURL: URL) -> String? {
        versionPlistBuildNumber(at: appURL) ?? infoPlistBuildNumber(at: appURL)
    }

    private static func versionPlistBuildNumber(at appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/version.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return nil
        }
        return plist["ProductBuildVersion"] as? String
    }

    private static func infoPlistBuildNumber(at appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == "com.apple.dt.Xcode" else {
            return nil
        }
        return plist["DTXcodeBuild"] as? String ?? plist["CFBundleVersion"] as? String
    }
}
