import ArgumentParser
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct RuntimeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "runtime", abstract: "Manage the shared versioned CLI runtime.", subcommands: [RuntimeActivateCommand.self, RuntimeStatusCommand.self])
}

enum SharedRuntime {
    static let version = ProxyPilotCommand.configuration.version
    static var root: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".proxypilot") }
    static var payload: URL { root.appendingPathComponent("cli/\(version)/proxypilot") }
    static var stable: URL { root.appendingPathComponent("bin/proxypilot") }
    static var lock: URL { root.appendingPathComponent("runtime.lock") }
    static func executableVersion(_ url: URL) -> String? { run(url, ["--version"])?.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func compatible(_ url: URL) -> Bool {
        guard let text = run(url, ["capabilities", "--json"]), let data = text.data(using: .utf8), let values = try? JSONSerialization.jsonObject(with: data) as? [String: Int] else { return false }
        return ["route_control", "active_model_aliasing", "request_attribution", "session_storage"].allSatisfy { values[$0, default: 0] >= 1 }
    }
    static func run(_ url: URL, _ args: [String]) -> String? { let p = Process(); let pipe = Pipe(); p.executableURL = url; p.arguments = args; p.standardOutput = pipe; p.standardError = Pipe(); guard (try? p.run()) != nil else { return nil }; p.waitUntilExit(); guard p.terminationStatus == 0 else { return nil }; return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) }
    static func sha256(_ url: URL) -> String? { run(URL(fileURLWithPath: "/usr/bin/shasum"), ["-a", "256", url.path])?.split(separator: " ").first.map(String.init) }
    static func newer(_ lhs: String, than rhs: String) -> Bool { lhs.split(separator: ".").map { Int($0) ?? 0 }.lexicographicallyPrecedes(rhs.split(separator: ".").map { Int($0) ?? 0 }) == false && lhs != rhs }
    static func atomicReplace(_ staged: URL, at destination: URL) throws {
        guard rename(staged.path, destination.path) == 0 else {
            throw ValidationError("Atomic runtime activation failed: errno \(errno)")
        }
    }
}

struct RuntimeActivateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "activate")
    @Flag(name: .long) var json = false
    func run() throws {
        try FileManager.default.createDirectory(at: SharedRuntime.root, withIntermediateDirectories: true)
        let fd = open(SharedRuntime.lock.path, O_CREAT | O_RDWR, 0o600); guard fd >= 0, flock(fd, LOCK_EX) == 0 else { throw ValidationError("Could not acquire runtime activation lock") }; defer { flock(fd, LOCK_UN); close(fd) }
        if let installed = SharedRuntime.executableVersion(SharedRuntime.stable), SharedRuntime.newer(installed, than: SharedRuntime.version) {
            guard SharedRuntime.compatible(SharedRuntime.stable) else { throw ValidationError("A newer incompatible shared runtime \(installed) is installed; refusing to replace or downgrade it") }
            print(#"{"action":"reused_newer","compatible":true,"path":"\#(SharedRuntime.stable.path)","version":"\#(installed)"}"#); return
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let directory = SharedRuntime.payload.deletingLastPathComponent(); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stage = directory.appendingPathComponent(".proxypilot-\(UUID().uuidString)"); try FileManager.default.copyItem(at: source, to: stage); try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stage.path)
        guard let sourceHash = SharedRuntime.sha256(source), sourceHash == SharedRuntime.sha256(stage) else { try? FileManager.default.removeItem(at: stage); throw ValidationError("Staged runtime checksum verification failed") }
        guard SharedRuntime.compatible(stage) else { try? FileManager.default.removeItem(at: stage); throw ValidationError("Staged runtime failed capability verification") }
        try SharedRuntime.atomicReplace(stage, at: SharedRuntime.payload)
        try FileManager.default.createDirectory(at: SharedRuntime.stable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let link = SharedRuntime.stable.deletingLastPathComponent().appendingPathComponent(".proxypilot-\(UUID().uuidString)"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: SharedRuntime.payload)
        try SharedRuntime.atomicReplace(link, at: SharedRuntime.stable)
        guard SharedRuntime.compatible(SharedRuntime.stable) else { throw ValidationError("Activated runtime failed capability verification") }
        print(#"{"action":"activated","compatible":true,"path":"\#(SharedRuntime.stable.path)","version":"\#(SharedRuntime.version)"}"#)
    }
}

struct RuntimeStatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status")
    @Flag(name: .long) var json = false
    func run() { let version = SharedRuntime.executableVersion(SharedRuntime.stable); print(#"{"compatible":\#(SharedRuntime.compatible(SharedRuntime.stable)),"path":"\#(SharedRuntime.stable.path)","ready":\#(version != nil),"version":"\#(version ?? "")"}"#) }
}
