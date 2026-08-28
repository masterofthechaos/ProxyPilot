import Foundation

@MainActor
final class RepoGPSService: ObservableObject {
    struct DistributionStatus: Decodable, Equatable {
        var installed: Bool
        var ownership: String
        var currentVersion: String?
        var previousVersion: String?
        var executable: String?
        var behaviorPackVersion: String?
        var engineReady: Bool

        enum CodingKeys: String, CodingKey {
            case installed, ownership, executable
            case currentVersion = "current_version"
            case previousVersion = "previous_version"
            case behaviorPackVersion = "behavior_pack_version"
            case engineReady = "engine_ready"
        }

        static let missing = Self(installed: false, ownership: "missing", currentVersion: nil, previousVersion: nil, executable: nil, behaviorPackVersion: nil, engineReady: false)
    }

    struct SessionStatus: Decodable, Equatable {
        struct Lease: Decodable, Equatable {
            var sessionID: UUID
            var repository: String
            var mode: String
            var activity: String
            var startedAt: Date
            var repoGPSVersion: String
            var behaviorPackVersion: String

            enum CodingKeys: String, CodingKey {
                case repository, mode, activity
                case sessionID = "session_id"
                case startedAt = "started_at"
                case repoGPSVersion = "repogps_version"
                case behaviorPackVersion = "behavior_pack_version"
            }
        }

        var active: Bool
        var lease: Lease?
        var pendingSignals: Int
        var acknowledgedSignals: Int

        enum CodingKeys: String, CodingKey {
            case active, lease
            case pendingSignals = "pending_signals"
            case acknowledgedSignals = "acknowledged_signals"
        }

        static let inactive = Self(active: false, lease: nil, pendingSignals: 0, acknowledgedSignals: 0)
    }

    struct UpdateStatus: Decodable, Equatable {
        var state: String
        var installedVersion: String
        var latestVersion: String
        var ownership: String
        var updateAvailable: Bool
        var compatible: Bool
        var feedURL: URL

        enum CodingKeys: String, CodingKey {
            case state, ownership, compatible
            case installedVersion = "installed_version"
            case latestVersion = "latest_version"
            case updateAvailable = "update_available"
            case feedURL = "feed_url"
        }
    }

    @Published private(set) var distribution = DistributionStatus.missing
    @Published private(set) var session = SessionStatus.inactive
    @Published private(set) var updateStatus: UpdateStatus?
    @Published private(set) var bundledVersion: String?
    @Published private(set) var isWorking = false
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var isInstallingProxyPilotCLI = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastReceipt: String?

    typealias CLIActivator = @MainActor () async -> String?

    private let home: URL
    private let bundle: Bundle
    private let cliActivator: CLIActivator
    private var refreshTask: Task<Void, Never>?
    private var lastUpdateCheckAt: Date?

    private static let automaticUpdateCheckInterval: TimeInterval = 6 * 60 * 60

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundle: Bundle = .main,
        cliActivator: CLIActivator? = nil
    ) {
        self.home = home
        self.bundle = bundle
        let bundledCLI = Self.bundledProxyPilotCLI(in: bundle)
        self.cliActivator = cliActivator ?? {
            await Self.activateProxyPilotCLI(at: bundledCLI)
        }
        bundledVersion = payloadManifest()?.payloadVersion
    }

    deinit { refreshTask?.cancel() }

    var isInstalledAndCompatible: Bool {
        distribution.installed && distribution.ownership == "managed" && distribution.currentVersion != nil
    }

    var bundledUpdateAvailable: Bool {
        guard distribution.ownership == "managed", let current = distribution.currentVersion, let bundledVersion else { return false }
        return Self.isStableVersion(bundledVersion, newerThan: current)
    }

    var remoteUpdateAvailable: Bool {
        guard distribution.ownership == "managed", let updateStatus else { return false }
        return updateStatus.compatible && updateStatus.updateAvailable
    }

    var updateAvailable: Bool {
        remoteUpdateAvailable || bundledUpdateAvailable
    }

    var executableURL: URL? {
        if let path = distribution.executable { return URL(fileURLWithPath: path) }
        let stable = home.appendingPathComponent(".repogps/bin/rgps")
        return FileManager.default.isExecutableFile(atPath: stable.path) ? stable : nil
    }

    nonisolated static func parseDistributionStatus(_ data: Data) -> DistributionStatus? {
        try? JSONDecoder().decode(DistributionStatus.self, from: data)
    }

    nonisolated static func parseSessionStatus(_ data: Data) -> SessionStatus? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let value = try? container.decode(String.self) {
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = fractional.date(from: value) {
                    return date
                }

                let standard = ISO8601DateFormatter()
                if let date = standard.date(from: value) {
                    return date
                }
            }

            if let value = try? container.decode(Double.self) {
                // RepoGPS 0.2.0's JSON command reporter uses JSONEncoder's
                // default date representation: seconds since 2001-01-01.
                return Date(timeIntervalSinceReferenceDate: value)
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 or Foundation reference-date timestamp."
            )
        }
        return try? decoder.decode(SessionStatus.self, from: data)
    }

    nonisolated static func parseUpdateStatus(_ data: Data) -> UpdateStatus? {
        try? JSONDecoder().decode(UpdateStatus.self, from: data)
    }

    nonisolated static func isStableVersion(_ candidate: String, newerThan current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    func startMonitoring() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(allowAutomaticUpdate: true)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh(allowAutomaticUpdate: Bool = false) async {
        bundledVersion = payloadManifest()?.payloadVersion
        let binary = executableURL ?? bundledExecutable
        guard let binary else {
            distribution = externalStatusIfPresent() ?? .missing
            session = .inactive
            updateStatus = nil
            return
        }
        if let data = await run(binary, ["distribution", "status", "--json"])?.data,
           let decoded = Self.parseDistributionStatus(data) {
            distribution = decoded
        } else if binary == bundledExecutable {
            distribution = externalStatusIfPresent() ?? .missing
        }
        if distribution.ownership != "managed" {
            updateStatus = nil
        } else if allowAutomaticUpdate, !isWorking {
            await checkForUpdates(force: false, reportFailure: false)
            if remoteUpdateAvailable {
                await installAvailableUpdate(installEngine: false)
                return
            }
            if bundledUpdateAvailable {
                await installBundled(adoptExternal: false, installEngine: false)
                return
            }
        }
        if let installed = executableURL,
           let data = await run(installed, ["session", "status", "--json"])?.data,
           let decoded = Self.parseSessionStatus(data) {
            session = decoded
        } else {
            session = .inactive
        }
    }

    func install(adoptExternal: Bool = false, installEngine: Bool = true) async {
        guard await installProxyPilotCLI(reportReceipt: false) else { return }
        if remoteUpdateAvailable, !adoptExternal {
            await installAvailableUpdate(installEngine: installEngine)
        } else {
            await installBundled(adoptExternal: adoptExternal, installEngine: installEngine)
        }
    }

    /// Activates the app-bundled CLI into the shared user runtime used by
    /// RepoGPS. This is both the automatic dependency step for RepoGPS install
    /// and the explicit recovery action shown beside a missing-route warning.
    @discardableResult
    func installProxyPilotCLI(reportReceipt: Bool = true) async -> Bool {
        guard !isInstallingProxyPilotCLI else { return false }
        isInstallingProxyPilotCLI = true
        defer { isInstallingProxyPilotCLI = false }

        if let detail = await cliActivator() {
            lastError = "Could not install ProxyPilot CLI: " + detail
            return false
        }

        lastError = nil
        if reportReceipt {
            lastReceipt = "Installed the bundled ProxyPilot CLI for RepoGPS routing."
        }
        return true
    }

    func repair() async {
        await installBundled(adoptExternal: false, installEngine: true, repair: true)
    }

    func checkForUpdates(force: Bool = true, reportFailure: Bool = true) async {
        guard distribution.ownership == "managed" else {
            updateStatus = nil
            if reportFailure {
                lastError = "Install or adopt RepoGPS before checking for managed updates."
            }
            return
        }
        if !force, let lastUpdateCheckAt,
           Date().timeIntervalSince(lastUpdateCheckAt) < Self.automaticUpdateCheckInterval {
            return
        }
        guard let bundledExecutable else {
            if reportFailure { lastError = "This ProxyPilot build does not contain the RepoGPS updater." }
            return
        }

        lastUpdateCheckAt = Date()
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        guard let result = await run(bundledExecutable, ["update", "--check", "--json"]),
              result.code == 0,
              let decoded = Self.parseUpdateStatus(result.data) else {
            if reportFailure {
                lastError = "Could not check for RepoGPS updates. The current installation was not changed."
            }
            return
        }

        updateStatus = decoded
        if reportFailure {
            lastError = nil
            lastReceipt = decoded.updateAvailable
                ? "RepoGPS \(decoded.latestVersion) is ready to install."
                : "RepoGPS \(decoded.installedVersion) is up to date."
        }
    }

    private func installAvailableUpdate(installEngine: Bool) async {
        guard let bundledExecutable else {
            lastError = "This ProxyPilot build does not contain the RepoGPS updater."
            return
        }
        isWorking = true
        defer { isWorking = false }
        guard await succeeds(bundledExecutable, ["update", "--json"]) else { return }
        if installEngine, let installed = stableExecutable,
           !(await succeeds(installed, ["engine", "install", "--json"])) { return }
        let version = updateStatus?.latestVersion ?? "the latest version"
        lastReceipt = installEngine
            ? "Updated RepoGPS to \(version) and verified its pinned coding engine."
            : "Updated RepoGPS to \(version)."
        lastError = nil
        updateStatus = nil
        lastUpdateCheckAt = nil
        await refresh()
    }

    private func installBundled(adoptExternal: Bool, installEngine: Bool, repair: Bool = false) async {
        guard let bundledExecutable, let payloadURL else {
            lastError = "This ProxyPilot build does not contain a RepoGPS payload."
            return
        }
        isWorking = true
        defer { isWorking = false }
        var args = ["distribution", repair ? "repair" : "install", "--payload", payloadURL.path, "--json"]
        if adoptExternal { args.append("--adopt") }
        guard await succeeds(bundledExecutable, args) else { return }
        if installEngine, let installed = stableExecutable,
           !(await succeeds(installed, ["engine", "install", "--json"])) { return }
        if repair {
            lastReceipt = "Repaired RepoGPS from ProxyPilot's signed bundled fallback."
        } else {
            lastReceipt = installEngine ? "Installed RepoGPS and its pinned coding engine." : "Updated RepoGPS from ProxyPilot's bundled fallback."
        }
        lastError = nil
        updateStatus = nil
        lastUpdateCheckAt = nil
        await refresh()
    }

    func rollback() async { await mutate(["distribution", "rollback", "--json"], receipt: "Rolled RepoGPS back to the previous managed payload.") }
    func remove() async { await mutate(["distribution", "remove", "--json"], receipt: "Removed the ProxyPilot-managed RepoGPS installation.") }

    /// Opens a small, one-use `.command` document in Terminal.app. Terminal,
    /// rather than ProxyPilot, owns the resulting process group and TTY; this is
    /// required for OpenCode's interactive input, resize, redraw, and Ctrl-C.
    @discardableResult
    func launch(in repository: URL) async -> Bool {
        guard let executableURL else {
            lastError = "Install RepoGPS before opening a terminal session."
            return false
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repository.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            lastError = "Choose an existing project folder."
            return false
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let launcherDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ProxyPilot-RepoGPS-Launches", isDirectory: true)
            try FileManager.default.createDirectory(
                at: launcherDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcherDirectory.path)

            let launcher = launcherDirectory.appendingPathComponent(UUID().uuidString + ".command")
            let script = Self.terminalLauncherScript(executable: executableURL, repository: repository)
            try Data(script.utf8).write(to: launcher, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)

            guard let result = await run(URL(fileURLWithPath: "/usr/bin/open"), ["-a", "Terminal", launcher.path]), result.code == 0 else {
                try? FileManager.default.removeItem(at: launcher)
                throw RepoGPSLaunchError.terminalDidNotOpen
            }

            lastError = nil
            lastReceipt = "Opened RepoGPS for \(repository.lastPathComponent) in Terminal. Home will show the cockpit when the TUI is ready."
            return true
        } catch {
            lastError = "Could not open RepoGPS in Terminal: \(error.localizedDescription)"
            return false
        }
    }

    func signal(_ type: String) async {
        guard let executableURL else { return }
        guard await succeeds(executableURL, ["session", "signal", "--type", type, "--json"]) else { return }
        lastReceipt = "Sent " + type + " to the active RepoGPS terminal session."
        await refresh()
    }

    private func mutate(_ arguments: [String], receipt: String) async {
        guard let executableURL else { return }
        isWorking = true
        defer { isWorking = false }
        guard await succeeds(executableURL, arguments) else { return }
        lastReceipt = receipt
        lastError = nil
        await refresh()
    }

    private var payloadURL: URL? { bundle.resourceURL?.appendingPathComponent("RepoGPSPayload") }
    nonisolated static func bundledProxyPilotCLI(in bundle: Bundle) -> URL {
        bundle.bundleURL.appendingPathComponent("Contents/Helpers/proxypilot")
    }

    private nonisolated static func activateProxyPilotCLI(at binary: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard FileManager.default.isExecutableFile(atPath: binary.path) else {
                return "This app does not contain an executable ProxyPilot CLI helper."
            }

            let process = Process()
            let output = Pipe()
            process.executableURL = binary
            process.arguments = ["runtime", "activate", "--json"]
            process.standardOutput = output
            process.standardError = output

            do {
                try process.run()
            } catch {
                return error.localizedDescription
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return message.isEmpty ? "The bundled CLI activation command failed." : message
            }
            return nil
        }.value
    }

    private var bundledExecutable: URL? {
        guard let value = payloadURL?.appendingPathComponent("bin/rgps"), FileManager.default.isExecutableFile(atPath: value.path) else { return nil }
        return value
    }
    private var stableExecutable: URL? {
        let value = home.appendingPathComponent(".repogps/bin/rgps")
        return FileManager.default.isExecutableFile(atPath: value.path) ? value : nil
    }
    private func externalStatusIfPresent() -> DistributionStatus? {
        let external = home.appendingPathComponent(".local/bin/rgps")
        guard FileManager.default.fileExists(atPath: external.path) else { return nil }
        return .init(installed: true, ownership: "external", currentVersion: nil, previousVersion: nil, executable: external.resolvingSymlinksInPath().path, behaviorPackVersion: nil, engineReady: false)
    }

    private struct PayloadManifest: Decodable { var payloadVersion: String; enum CodingKeys: String, CodingKey { case payloadVersion = "payload_version" } }
    private func payloadManifest() -> PayloadManifest? {
        guard let url = payloadURL?.appendingPathComponent("payload.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PayloadManifest.self, from: data)
    }

    private func succeeds(_ binary: URL, _ arguments: [String]) async -> Bool {
        guard let result = await run(binary, arguments) else { lastError = "Could not run RepoGPS."; return false }
        guard result.code == 0 else {
            lastError = result.message.isEmpty ? "RepoGPS command failed." : result.message
            return false
        }
        return true
    }

    private struct ProcessResult: Sendable { var data: Data; var code: Int32; var message: String }

    nonisolated static func terminalLauncherScript(executable: URL, repository: URL) -> String {
        let executable = shellQuote(executable.standardizedFileURL.path)
        let repository = shellQuote(repository.standardizedFileURL.path)
        return """
        #!/bin/zsh
        /bin/rm -f -- "$0" || true
        cd -- \(repository)
        exec \(executable) --dir \(repository)
        """ + "\n"
    }

    nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func run(_ binary: URL, _ arguments: [String]) async -> ProcessResult? {
        await Task.detached(priority: .utility) {
            let process = Process(); let output = Pipe(); let error = Pipe()
            process.executableURL = binary; process.arguments = arguments
            process.standardOutput = output; process.standardError = error
            guard (try? process.run()) != nil else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let message = String(decoding: errorData.isEmpty ? data : errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return ProcessResult(data: data, code: process.terminationStatus, message: message)
        }.value
    }
}

private enum RepoGPSLaunchError: LocalizedError {
    case terminalDidNotOpen

    var errorDescription: String? {
        "Terminal.app did not accept the RepoGPS launcher."
    }
}
