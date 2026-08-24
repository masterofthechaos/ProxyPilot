import Foundation
import Testing
@testable import ProxyPilotCore

/// Eviction-policy tests for the compaction memo cache.
///
/// The cache is documented as LRU. These pin that claim: a FIFO
/// implementation passes every "does it cache at all" test but fails
/// `evictsLeastRecentlyUsedRatherThanOldestInserted`, which is exactly the
/// distinction that decides whether a hot entry survives a burst of cold ones.

@Test func cacheReturnsStoredOutcome() {
    let cache = ContextCompactionCache(capacity: 4)
    cache.store(.compacted(body: "short", matchedRuleIDs: ["r1"]), forKey: "k")

    guard case .compacted(let body, let ruleIDs)? = cache.outcome(forKey: "k") else {
        Issue.record("Expected a compacted outcome")
        return
    }
    #expect(body == "short")
    #expect(ruleIDs == ["r1"])
}

@Test func cacheEvictsOnceCapacityIsExceeded() {
    let cache = ContextCompactionCache(capacity: 2)
    cache.store(.miss, forKey: "a")
    cache.store(.miss, forKey: "b")
    cache.store(.miss, forKey: "c")

    #expect(cache.outcome(forKey: "a") == nil)
    #expect(cache.outcome(forKey: "b") != nil)
    #expect(cache.outcome(forKey: "c") != nil)
}

@Test func cacheEvictsLeastRecentlyUsedRatherThanOldestInserted() {
    let cache = ContextCompactionCache(capacity: 2)
    cache.store(.miss, forKey: "a")
    cache.store(.miss, forKey: "b")

    // Read "a", making "b" the least recently used entry.
    #expect(cache.outcome(forKey: "a") != nil)

    cache.store(.miss, forKey: "c")

    // Under FIFO "a" would have been evicted here despite being the hot entry.
    #expect(cache.outcome(forKey: "a") != nil, "A recently read entry must survive eviction")
    #expect(cache.outcome(forKey: "b") == nil, "The least recently used entry is the victim")
    #expect(cache.outcome(forKey: "c") != nil)
}

@Test func restoringAnExistingKeyRefreshesRecency() {
    let cache = ContextCompactionCache(capacity: 2)
    cache.store(.miss, forKey: "a")
    cache.store(.miss, forKey: "b")

    // Overwriting "a" counts as use, so "b" becomes the eviction victim.
    cache.store(.compacted(body: "fresh", matchedRuleIDs: []), forKey: "a")
    cache.store(.miss, forKey: "c")

    #expect(cache.outcome(forKey: "a") != nil)
    #expect(cache.outcome(forKey: "b") == nil)
}

@Test func cacheCapacityIsAtLeastOne() {
    let cache = ContextCompactionCache(capacity: 0)
    cache.store(.miss, forKey: "a")
    #expect(cache.outcome(forKey: "a") != nil)
}
