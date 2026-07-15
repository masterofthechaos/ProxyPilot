import Foundation

/// Result of an Active Context Compaction attempt on an Anthropic
/// `system` field.
///
/// Fail-open contract: when `applied` is false, `system` is nil and the
/// caller MUST leave the original request value untouched. Never
/// re-serialize the original text through the mutation — unrecognized
/// prompts have to reach the upstream byte-identical so llama.cpp-style
/// prefix caches stay warm.
public struct ContextCompactionMutation: Sendable {
    /// Replacement value for the Anthropic `system` field. Nil means
    /// "leave the original untouched" (passthrough).
    public let system: String?
    public let applied: Bool
    public let strategy: String
    public let notes: [String]
    public let originalUTF8Bytes: Int
    public let compactedUTF8Bytes: Int

    public init(
        system: String?,
        applied: Bool,
        strategy: String,
        notes: [String] = [],
        originalUTF8Bytes: Int = 0,
        compactedUTF8Bytes: Int = 0
    ) {
        self.system = system
        self.applied = applied
        self.strategy = strategy
        self.notes = notes
        self.originalUTF8Bytes = originalUTF8Bytes
        self.compactedUTF8Bytes = compactedUTF8Bytes
    }

    public static func passThrough(strategy: String, notes: [String] = []) -> ContextCompactionMutation {
        ContextCompactionMutation(system: nil, applied: false, strategy: strategy, notes: notes)
    }
}

/// Stable strategy identifiers surfaced in logs and stats.
public enum ContextCompactionStrategy {
    public static let disabled = "disabled"
    public static let unsupportedProvider = "unsupported_provider"
    public static let noSystem = "no_system"
    public static let fingerprintMiss = "fingerprint_miss"
    public static let compacted = "compacted_v1"
    public static let cacheHit = "cache_hit_v1"
}
