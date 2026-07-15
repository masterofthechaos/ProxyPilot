import ProxyPilotCore
import Testing

private typealias Policy = AgentModesCapabilityPolicy

private func xcode(
    _ version: String,
    build: String? = "27A5194q",
    id: String? = nil
) -> Policy.Xcode {
    Policy.Xcode(id: id ?? version, version: version, build: build)
}

@Test func versionParsingAndComparisonHandlesReleaseLabels() throws {
    #expect(try #require(Policy.Version("27.0 beta 1")) == .init(major: 27))
    #expect(try #require(Policy.Version("26.3.1")) > .init(major: 26, minor: 3))
    #expect(Policy.Version("unknown") == nil)
}

@Test func olderMacOSStillShowsProxyPilotAgentWhenXcodeQualifies() {
    // Xcode 27 betas run on the prior macOS; availability must not depend on
    // the host macOS version, only on the Xcode major version.
    let result = Policy.evaluate(xcodes: [xcode("27.0")])

    #expect(result.isClaudeAgentAvailable)
    #expect(result.claudeAgentXcode?.versionString == "27.0")
    #expect(result.proxyPilotAgent == .automaticRegistration(xcode: xcode("27.0")))
    #expect(result.proxyPilotAgent.showsProxyPilotAgentControls)
}

@Test func noXcodeHidesProxyPilotAgent() {
    let result = Policy.evaluate(xcodes: [])

    #expect(!result.isClaudeAgentAvailable)
    #expect(result.proxyPilotAgent == .hidden(.xcodeNotFound))
}

@Test func olderXcodeHidesProxyPilotAgentAtVersionBoundary() {
    let result = Policy.evaluate(xcodes: [xcode("26.3", build: "16E140")])

    #expect(result.isClaudeAgentAvailable)
    #expect(result.proxyPilotAgent == .hidden(.xcodeVersionTooOld(
        detected: .init(major: 26, minor: 3),
        required: .init(major: 27)
    )))
}

@Test func claudeAgentUsesIndependent263Boundary() {
    let below = Policy.evaluate(xcodes: [xcode("26.2.9", build: "16D1")])
    let boundary = Policy.evaluate(xcodes: [xcode("26.3", build: "16E140")])

    #expect(!below.isClaudeAgentAvailable)
    #expect(boundary.isClaudeAgentAvailable)
}

@Test func provenBuildAllowsAutomaticRegistration() {
    let candidate = xcode("27.0", build: "27A5194q")
    let result = Policy.evaluate(xcodes: [candidate])

    #expect(result.proxyPilotAgent == .automaticRegistration(xcode: candidate))
    #expect(result.proxyPilotAgent.showsProxyPilotAgentControls)
    #expect(result.proxyPilotAgent.allowsAutomaticRegistration)
}

@Test func unprovenBuildUsesManualRegistrationFallback() {
    let candidate = xcode("27.0", build: "27A9999z")
    let result = Policy.evaluate(xcodes: [candidate])

    #expect(result.proxyPilotAgent == .manualRegistration(
        xcode: candidate,
        reason: .buildNotProven("27A9999z")
    ))
    #expect(result.proxyPilotAgent.showsProxyPilotAgentControls)
    #expect(!result.proxyPilotAgent.allowsAutomaticRegistration)
}

@Test func missingBuildUsesManualRegistrationFallback() {
    let candidate = xcode("27.0", build: nil)
    let result = Policy.evaluate(xcodes: [candidate])

    #expect(result.proxyPilotAgent == .manualRegistration(
        xcode: candidate,
        reason: .buildNotDetected
    ))
}

@Test func provenInstallationWinsOverNewerUnprovenInstallation() {
    let proven = xcode("27.0", build: "27A5194q", id: "proven")
    let newer = xcode("28.0", build: "28A1000a", id: "newer")
    let result = Policy.evaluate(xcodes: [newer, proven])

    #expect(result.proxyPilotAgent == .automaticRegistration(xcode: proven))
    #expect(result.claudeAgentXcode == newer)
}

@Test func registrationManagerUsesTheSharedProvenBuildPolicy() {
    #expect(ACPRegistrationManager.supportedXcodeBuilds == Policy.provenAutomaticRegistrationBuilds)
}
