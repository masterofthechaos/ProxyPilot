import Foundation

/// In-memory memoization for compaction results.
///
/// Purely an optimization: compaction is deterministic and a single
/// forward scan of the text, so correctness never depends on this cache
/// and it is deliberately not persisted. Keys are SHA-256 of
/// (ruleset version ‖ preamble-free system text), so identical walls hit
/// regardless of the rotating `cch=` billing value, and any ruleset bump
/// invalidates naturally.
public final class ContextCompactionCache: @unchecked Sendable {
    public enum Outcome: Sendable {
        /// Engine recognized the wall; cached compacted body.
        case compacted(body: String, matchedRuleIDs: [String])
        /// Engine did not recognize the text; cached passthrough verdict.
        case miss
    }

    public static let shared = ContextCompactionCache()

    private let lock = NSLock()
    private var storage: [String: Outcome] = [:]
    private var insertionOrder: [String] = []
    private let capacity: Int

    public init(capacity: Int = 16) {
        self.capacity = max(1, capacity)
    }

    public func outcome(forKey key: String) -> Outcome? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func store(_ outcome: Outcome, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if storage[key] == nil {
            insertionOrder.append(key)
            if insertionOrder.count > capacity {
                let evicted = insertionOrder.removeFirst()
                storage[evicted] = nil
            }
        }
        storage[key] = outcome
    }

    public static func key(rulesetVersion: Int, body: String) -> String {
        ContextCompactionEngine.sha256Hex("v\(rulesetVersion)|\(body)")
    }
}
