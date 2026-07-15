import Foundation

/// Configuration for Active Context Compaction (ACCA).
///
/// When enabled, ProxyPilot replaces recognized sections of the Xcode
/// agent's system instructions with hand-curated condensed equivalents
/// before forwarding to local-inference providers, reducing prefill time.
/// Modeled as a struct (rather than a bare Bool) so future modes — e.g.
/// cloud-assisted compression — can be added without re-plumbing callers.
public struct ContextCompactionConfiguration: Sendable, Codable, Equatable {
    public var isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    public static let disabled = ContextCompactionConfiguration(isEnabled: false)
    public static let enabled = ContextCompactionConfiguration(isEnabled: true)
}
