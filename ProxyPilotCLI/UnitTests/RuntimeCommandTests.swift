import Testing
@testable import proxypilot

struct RuntimeCommandTests {
    @Test func sharedRuntimeVersionTracksTheCLIReleaseVersion() {
        #expect(SharedRuntime.version == ProxyPilotCommand.configuration.version)
    }
}
