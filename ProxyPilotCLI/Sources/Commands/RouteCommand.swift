#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import ArgumentParser
import Foundation
import ProxyPilotCore

struct RouteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "route", abstract: "Manage the shared CLI-owned route.", subcommands: [RouteStatusCommand.self, RouteSetCommand.self, RouteEnsureCommand.self])
}

// `RouteSelection` and the route.json/route.lock accessors live in
// Support/RouteStateStore.swift so the MCP `proxy_route_set` tool writes through
// the same store and lock as this command.
private typealias RouteState = RouteStateStore

private enum RouteReadiness {
    static func models(port: UInt16) async -> Set<String>? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/models"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["data"] as? [[String: Any]] else { return nil }
        return Set(entries.compactMap { $0["id"] as? String })
    }
    static func selected(port: UInt16, model: String) async -> Bool {
        guard PidFile.read() != nil, let ids = await models(port: port) else { return false }
        return ids.contains(model) && ids.contains(ActiveModelAlias.id)
    }
}

struct RouteStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status")
    @Flag(name: .long) var json = false
    func run() async throws {
        let selected = RouteState.load(); let selectedPort = selected?.port ?? 4000; let probe = await CLIProxyRuntime.probeProxy(on: selectedPort); let pid = PidFile.read()
        let applied = if let selected { await RouteReadiness.selected(port: selected.port, model: selected.model) } else { false }
        let verificationState = applied ? "models_ready" : (probe.reachable ? "mismatched" : "stopped")
        guard json else {
            if let selected {
                print("Route:   \(selected.provider) / \(selected.model) (port \(selected.port))")
            } else {
                print("Route:   none selected (port \(selectedPort))")
            }
            print("Applied: \(applied ? "yes" : "no")")
            print("Proxy:   \(probe.reachable ? "reachable" : "not reachable"), owner \(pid == nil ? "none" : "cli")")
            print("State:   \(verificationState)")
            return
        }
        let payload: [String: Any] = ["selected": selected != nil, "applied": applied, "reachable": probe.reachable, "owner": pid == nil ? "none" : "cli", "provider": selected?.provider ?? NSNull(), "model": selected?.model ?? NSNull(), "port": Int(selectedPort), "verification_state": verificationState]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]); print(String(decoding: data, as: UTF8.self))
    }
}

struct RouteSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set")
    @Option(name: .long) var provider: String
    @Option(name: .long) var model: String
    @Option(name: .long) var port: UInt16 = 4000
    @Flag(name: .long) var json = false
    func run() async throws {
        try FileManager.default.createDirectory(at: RouteState.directory, withIntermediateDirectories: true)
        let fd = open(RouteState.lock.path, O_CREAT | O_RDWR, 0o600); guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw ValidationError("Another route switch is in progress") }; defer { flock(fd, LOCK_UN); close(fd) }
        let previous = RouteState.load()
        if let pid = PidFile.read() {
            guard kill(pid, SIGTERM) == 0 else { throw ValidationError("Could not stop CLI-owned route") }
            for _ in 0..<100 { if !PidFile.isProcessRunning(pid: pid), await RouteReadiness.models(port: port) == nil { break }; try? await Task.sleep(for: .milliseconds(100)) }
            if await RouteReadiness.models(port: port) != nil {
                guard kill(pid, SIGKILL) == 0 else { throw ValidationError("Previous CLI-owned route did not release port \(port), and force-stop failed") }
                for _ in 0..<50 { if await RouteReadiness.models(port: port) == nil { break }; try? await Task.sleep(for: .milliseconds(100)) }
            }
            PidFile.remove()
            guard await RouteReadiness.models(port: port) == nil else { throw ValidationError("Previous CLI-owned route did not release port \(port)") }
        }
        else if (await CLIProxyRuntime.probeProxy(on: port)).reachable { throw ValidationError("Port \(port) is owned by the GUI or an unmanaged listener; refusing to stop it") }
        do { try await start(provider: provider, model: model, port: port); try RouteState.save(.init(provider: provider, model: model, port: port, updatedAt: Date())) }
        catch { if let previous { try? await start(provider: previous.provider, model: previous.model, port: previous.port) }; throw error }
        try await RouteStatusCommand(json: json).run()
    }
    private func start(provider: String, model: String, port: UInt16) async throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); process.arguments = ["start", "--provider", provider, "--model", model, "--port", String(port), "--daemon", "--json"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe; try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ValidationError(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)) }
        for _ in 0..<100 { if await RouteReadiness.selected(port: port, model: model) { return }; try? await Task.sleep(for: .milliseconds(100)) }
        throw ValidationError("Route became reachable without the requested model and managed PID")
    }
}

struct RouteEnsureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ensure")
    @Flag(name: .long) var json = false
    func run() async throws {
        if let selected = RouteState.load(), !(await CLIProxyRuntime.probeProxy(on: selected.port)).reachable {
            let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); process.arguments = ["route", "set", "--provider", selected.provider, "--model", selected.model, "--port", String(selected.port), "--json"]
            process.standardOutput = FileHandle.standardOutput; process.standardError = FileHandle.standardError
            try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw ExitCode.failure }
        } else {
            // Deliberately unconditional JSON: `rgps` invokes `route ensure`
            // directly and predates the --json flag being honored, so switching
            // this to human output on a bare invocation would break it. Revisit
            // once the RepoGPS side is known to pass --json.
            try await RouteStatusCommand(json: true).run()
        }
    }
}
