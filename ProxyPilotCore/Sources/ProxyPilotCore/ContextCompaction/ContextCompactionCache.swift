import Foundation

/// In-memory LRU memoization for compaction results.
///
/// Purely an optimization: compaction is deterministic and a single
/// forward scan of the text, so correctness never depends on this cache
/// and it is deliberately not persisted. Keys are SHA-256 of
/// (ruleset version ‖ preamble-free system text), so identical walls hit
/// regardless of the rotating `cch=` billing value, and any ruleset bump
/// invalidates naturally.
///
/// `capacity` bounds entry *count*, not bytes: a compacted `Outcome` retains
/// its body, so worst-case residency is `capacity` × the request-body cap.
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
    /// Least-recently-used first; the eviction victim is always `first`.
    private var recencyOrder: [String] = []
    private let capacity: Int

    public init(capacity: Int = 16) {
        self.capacity = max(1, capacity)
    }

    public func outcome(forKey key: String) -> Outcome? {
        lock.lock()
        defer { lock.unlock() }
        guard let outcome = storage[key] else { return nil }
        touch(key)
        return outcome
    }

    public func store(_ outcome: Outcome, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if storage[key] == nil {
            recencyOrder.append(key)
            if recencyOrder.count > capacity {
                let evicted = recencyOrder.removeFirst()
                storage[evicted] = nil
            }
        } else {
            touch(key)
        }
        storage[key] = outcome
    }

    /// Moves `key` to the most-recently-used end. Callers must hold `lock`.
    ///
    /// Without this a hit would leave eviction order untouched, making the
    /// policy FIFO: `capacity` distinct cold lookups would evict a hot entry
    /// no matter how often it was read.
    private func touch(_ key: String) {
        guard let index = recencyOrder.firstIndex(of: key) else { return }
        recencyOrder.remove(at: index)
        recencyOrder.append(key)
    }

    public static func key(rulesetVersion: Int, body: String) -> String {
        ContextCompactionEngine.sha256Hex("v\(rulesetVersion)|\(body)")
    }
}
