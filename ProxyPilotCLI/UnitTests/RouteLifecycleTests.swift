#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation
import Testing
@testable import proxypilot

struct RouteLifecycleTests {
    @Test func routeLockDescriptorIsCloseOnExec() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let descriptor = try RouteStateStore.acquireExclusiveLock(at: directory.appendingPathComponent("route.lock"))
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }

        let flags = fcntl(descriptor, F_GETFD)
        #expect(flags >= 0)
        #expect(flags & FD_CLOEXEC == FD_CLOEXEC)
    }

    @Test func routeStatusCommandRequiresParsingButReporterDoesNot() async throws {
        let parsed = try RouteStatusCommand.parse(["--json"])
        #expect(parsed.json)

        // This is the supported in-process path for `route set` and `route
        // ensure`; it must not touch an unparsed ArgumentParser wrapper.
        try await RouteStatusReporter.run(json: true)
    }
}
