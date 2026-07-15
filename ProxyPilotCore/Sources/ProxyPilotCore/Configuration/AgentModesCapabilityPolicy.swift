import Foundation

/// The shared product policy for Claude Agent and ProxyPilot Agent availability.
public enum AgentModesCapabilityPolicy {
    public static let minimumClaudeAgentVersion = Version(major: 26, minor: 3)
    public static let minimumProxyPilotAgentXcodeVersion = Version(major: 27)
    public static let provenAutomaticRegistrationBuilds: Set<String> = ["27A5194q"]

    public struct Version: Comparable, Equatable, Sendable {
        public let major: Int
        public let minor: Int
        public let patch: Int

        public init(major: Int, minor: Int = 0, patch: Int = 0) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        public init?(_ value: String) {
            let components = value.split(separator: ".", omittingEmptySubsequences: false)
            guard let major = Self.leadingInteger(in: components.first.map(String.init) ?? "") else {
                return nil
            }
            self.major = major
            self.minor = components.count > 1 ? Self.leadingInteger(in: String(components[1])) ?? 0 : 0
            self.patch = components.count > 2 ? Self.leadingInteger(in: String(components[2])) ?? 0 : 0
        }

        public static func < (lhs: Version, rhs: Version) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }

        private static func leadingInteger(in value: String) -> Int? {
            let digits = value.prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int(digits)
        }
    }

    public struct Xcode: Equatable, Sendable {
        public let id: String
        public let versionString: String
        public let version: Version?
        public let build: String?

        public init(id: String, version: String, build: String?) {
            self.id = id
            self.versionString = version
            self.version = Version(version)
            self.build = build?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
    }

    public enum HiddenReason: Equatable, Sendable {
        case xcodeNotFound
        case xcodeVersionTooOld(detected: Version?, required: Version)
    }

    public enum ManualRegistrationReason: Equatable, Sendable {
        case buildNotDetected
        case buildNotProven(String)
    }

    public enum ProxyPilotAgentAvailability: Equatable, Sendable {
        case hidden(HiddenReason)
        case manualRegistration(xcode: Xcode, reason: ManualRegistrationReason)
        case automaticRegistration(xcode: Xcode)

        public var showsProxyPilotAgentControls: Bool {
            switch self {
            case .hidden:
                false
            case .manualRegistration, .automaticRegistration:
                true
            }
        }

        public var allowsAutomaticRegistration: Bool {
            if case .automaticRegistration = self { return true }
            return false
        }
    }

    public struct Evaluation: Equatable, Sendable {
        public let claudeAgentXcode: Xcode?
        public let proxyPilotAgent: ProxyPilotAgentAvailability

        public var isClaudeAgentAvailable: Bool {
            claudeAgentXcode != nil
        }
    }

    /// Evaluates ProxyPilot Agent availability from the installed Xcodes alone.
    ///
    /// Availability is gated on the Xcode major version (Agent Modes is an Xcode
    /// feature), not on the host macOS version — Xcode 27 betas run on the prior
    /// macOS, and those users should still see the ProxyPilot Agent controls.
    public static func evaluate(
        xcodes: [Xcode],
        provenBuilds: Set<String> = provenAutomaticRegistrationBuilds
    ) -> Evaluation {
        let orderedXcodes = xcodes.sorted(by: isPreferredXcode)
        let claudeAgentXcode = orderedXcodes.first {
            guard let version = $0.version else { return false }
            return version >= minimumClaudeAgentVersion
        }

        guard !orderedXcodes.isEmpty else {
            return Evaluation(
                claudeAgentXcode: nil,
                proxyPilotAgent: .hidden(.xcodeNotFound)
            )
        }

        let eligibleXcodes = orderedXcodes.filter {
            guard let version = $0.version else { return false }
            return version >= minimumProxyPilotAgentXcodeVersion
        }
        guard !eligibleXcodes.isEmpty else {
            return Evaluation(
                claudeAgentXcode: claudeAgentXcode,
                proxyPilotAgent: .hidden(.xcodeVersionTooOld(
                    detected: orderedXcodes.first?.version,
                    required: minimumProxyPilotAgentXcodeVersion
                ))
            )
        }

        if let provenXcode = eligibleXcodes.first(where: { xcode in
            guard let build = xcode.build else { return false }
            return provenBuilds.contains(build)
        }) {
            return Evaluation(
                claudeAgentXcode: claudeAgentXcode,
                proxyPilotAgent: .automaticRegistration(xcode: provenXcode)
            )
        }

        let manualXcode = eligibleXcodes[0]
        let reason = manualXcode.build.map(ManualRegistrationReason.buildNotProven)
            ?? .buildNotDetected
        return Evaluation(
            claudeAgentXcode: claudeAgentXcode,
            proxyPilotAgent: .manualRegistration(xcode: manualXcode, reason: reason)
        )
    }

    private static func isPreferredXcode(_ lhs: Xcode, _ rhs: Xcode) -> Bool {
        switch (lhs.version, rhs.version) {
        case let (left?, right?) where left != right:
            return left > right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return lhs.id < rhs.id
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
