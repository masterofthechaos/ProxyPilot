#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

/// The CLI-owned route selection, shared by `proxypilot route` and the MCP
/// `proxy_route_set` tool.
///
/// Both surfaces must write through here. A route change that updates the live
/// engine without recording it leaves `route status` reporting the superseded
/// provider/model, and lets `route ensure` restart on the old route — silently
/// reverting the change.
struct RouteSelection: Codable {
    let provider: String
    let model: String
    let port: UInt16
    let updatedAt: Date
}

/// Thrown when another route switch already holds the lock.
struct RouteLockUnavailable: Error {}

enum RouteStateStore {
    static var directory: URL { PidFile.pidFilePath.deletingLastPathComponent() }
    static var selection: URL { directory.appendingPathComponent("route.json") }
    static var lock: URL { directory.appendingPathComponent("route.lock") }

    static func load() -> RouteSelection? {
        guard let data = try? Data(contentsOf: selection) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RouteSelection.self, from: data)
    }

    static func save(_ value: RouteSelection) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: selection, options: .atomic)
    }

    /// Runs `body` while holding an exclusive, non-blocking `flock` on
    /// `route.lock`, serializing route changes across the CLI, the GUI (which
    /// shells out to `route set`), and the MCP tool.
    static func withExclusiveLock<T>(_ body: () async throws -> T) async throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = try acquireExclusiveLock()
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        return try await body()
    }

    /// Opens the lifecycle lock without allowing a subsequently spawned daemon
    /// to inherit it. `route set` launches `proxypilot start --daemon` while the
    /// lock is held; without `FD_CLOEXEC`, that long-lived child keeps the same
    /// flock alive after the parent returns and every future route change fails.
    static func acquireExclusiveLock(at lockURL: URL = lock) throws -> Int32 {
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw RouteLockUnavailable() }

        let descriptorFlags = fcntl(descriptor, F_GETFD)
        guard descriptorFlags >= 0,
              fcntl(descriptor, F_SETFD, descriptorFlags | FD_CLOEXEC) == 0 else {
            close(descriptor)
            throw RouteLockUnavailable()
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw RouteLockUnavailable()
        }
        return descriptor
    }
}
