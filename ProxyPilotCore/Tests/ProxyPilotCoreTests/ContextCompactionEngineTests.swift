import Foundation
import Testing
@testable import ProxyPilotCore

/// Engine tests run against a SYNTHETIC wall + ruleset built in-test.
/// The real Xcode context wall must never appear in this repo's test
/// fixtures (tests sync to the public mirror); production rules are
/// authored separately from a private capture.
@Suite("ContextCompactionEngine")
struct ContextCompactionEngineTests {
    // MARK: - Synthetic fixture

    static let alphaSection = "## Section Alpha\n" + String(repeating: "Alpha instructions line.\n", count: 20)
    static let betaSection = "## Section Beta\n" + String(repeating: "Beta instructions line.\n", count: 20)
    static let gammaSection = "## Section Gamma\n" + String(repeating: "Gamma instructions line.\n", count: 20)
    static let wallHeader = "SYNTHETIC XCODE WALL for engine tests\n" + String(repeating: "Preface text.\n", count: 10)

    static var syntheticBody: String { wallHeader + alphaSection + betaSection + gammaSection }

    static func syntheticRuleset(
        minimumLength: Int = 100,
        alphaHash: String? = nil,
        betaHash: String? = nil,
        gammaHash: String? = nil
    ) -> ContextCompactionRuleset {
        ContextCompactionRuleset(
            version: 7,
            wallSentinels: ["SYNTHETIC XCODE WALL", "## Section Alpha"],
            minimumSystemLength: minimumLength,
            rules: [
                ContextCompactionRule(
                    id: "alpha",
                    startAnchor: "## Section Alpha",
                    sectionSHA256: alphaHash ?? ContextCompactionEngine.sha256Hex(alphaSection),
                    condensedReplacement: "## Alpha (condensed)\n"
                ),
                ContextCompactionRule(
                    id: "beta",
                    startAnchor: "## Section Beta",
                    sectionSHA256: betaHash ?? ContextCompactionEngine.sha256Hex(betaSection),
                    condensedReplacement: "## Beta (condensed)\n"
                ),
                ContextCompactionRule(
                    id: "gamma",
                    startAnchor: "## Section Gamma",
                    sectionSHA256: gammaHash ?? ContextCompactionEngine.sha256Hex(gammaSection),
                    condensedReplacement: "## Gamma (condensed)\n"
                ),
            ]
        )
    }

    // MARK: - Matching

    @Test func fullMatchReplacesAllSections() {
        let result = ContextCompactionEngine.compactBody(Self.syntheticBody, ruleset: Self.syntheticRuleset())

        #expect(result.matchedRuleIDs == ["alpha", "beta", "gamma"])
        #expect(result.body == Self.wallHeader + "## Alpha (condensed)\n## Beta (condensed)\n## Gamma (condensed)\n")
    }

    @Test func hashDriftKeepsThatSectionVerbatim() {
        // Beta's hash is computed from different text → beta must survive verbatim.
        let ruleset = Self.syntheticRuleset(betaHash: ContextCompactionEngine.sha256Hex("something else"))
        let result = ContextCompactionEngine.compactBody(Self.syntheticBody, ruleset: ruleset)

        #expect(result.matchedRuleIDs == ["alpha", "gamma"])
        #expect(result.body == Self.wallHeader + "## Alpha (condensed)\n" + Self.betaSection + "## Gamma (condensed)\n")
    }

    @Test func perturbedSectionContentFailsItsHash() {
        let perturbed = Self.syntheticBody.replacingOccurrences(
            of: "Beta instructions line.",
            with: "Beta instructions line!"
        )
        let result = ContextCompactionEngine.compactBody(perturbed, ruleset: Self.syntheticRuleset())

        #expect(!result.matchedRuleIDs.contains("beta"))
        #expect(result.body?.contains("Beta instructions line!") == true)
    }

    @Test func crlfSectionMatchesHashComputedFromLF() {
        let crlfBody = Self.syntheticBody.replacingOccurrences(of: "\n", with: "\r\n")
        let result = ContextCompactionEngine.compactBody(crlfBody, ruleset: Self.syntheticRuleset())

        #expect(result.matchedRuleIDs == ["alpha", "beta", "gamma"])
    }

    // MARK: - Fail-open gates

    @Test func missingSentinelReturnsNil() {
        let body = Self.syntheticBody.replacingOccurrences(of: "SYNTHETIC XCODE WALL", with: "SOME OTHER PROMPT")
        let result = ContextCompactionEngine.compactBody(body, ruleset: Self.syntheticRuleset())
        #expect(result.body == nil)
    }

    @Test func belowMinimumLengthReturnsNil() {
        let result = ContextCompactionEngine.compactBody(
            Self.syntheticBody,
            ruleset: Self.syntheticRuleset(minimumLength: 1_000_000)
        )
        #expect(result.body == nil)
    }

    @Test func zeroMatchedRulesReturnsNil() {
        let wrong = ContextCompactionEngine.sha256Hex("no match")
        let ruleset = Self.syntheticRuleset(alphaHash: wrong, betaHash: wrong, gammaHash: wrong)
        let result = ContextCompactionEngine.compactBody(Self.syntheticBody, ruleset: ruleset)

        #expect(result.body == nil)
    }

    @Test func emptyProductionRulesetNeverFires() {
        // Shipped v1 ruleset is intentionally empty: enabled ACCA is a safe no-op.
        let bigBody = String(repeating: "x", count: ContextCompactionRules.ruleset.minimumSystemLength + 1)
        let result = ContextCompactionEngine.compactBody(bigBody, ruleset: ContextCompactionRules.ruleset)
        #expect(result.body == nil)
    }

    // MARK: - Determinism

    @Test func repeatedCompactionIsByteIdentical() {
        let ruleset = Self.syntheticRuleset()
        let first = ContextCompactionEngine.compactBody(Self.syntheticBody, ruleset: ruleset)
        for _ in 0..<5 {
            let again = ContextCompactionEngine.compactBody(Self.syntheticBody, ruleset: ruleset)
            #expect(again == first)
        }
    }

    // MARK: - Volatile preamble

    @Test func splitVolatilePreambleSeparatesBillingLine() {
        let text = "x-anthropic-billing-header: plan=pro; cch=abc123\nStable body"
        let (preamble, body) = ContextCompactionEngine.splitVolatilePreamble(text)

        #expect(preamble == "x-anthropic-billing-header: plan=pro; cch=abc123\n")
        #expect(body == "Stable body")
    }

    @Test func splitVolatilePreambleWithoutBillingLineIsIdentity() {
        let (preamble, body) = ContextCompactionEngine.splitVolatilePreamble("Just a prompt")
        #expect(preamble.isEmpty)
        #expect(body == "Just a prompt")
    }

    @Test func splitVolatilePreambleBillingOnlyTextHasEmptyBody() {
        let text = "x-anthropic-billing-header: cch=zzz"
        let (preamble, body) = ContextCompactionEngine.splitVolatilePreamble(text)
        #expect(preamble == text)
        #expect(body.isEmpty)
    }

    @Test func cacheKeyIgnoresRotatingBillingValue() {
        let bodyA = ContextCompactionEngine.splitVolatilePreamble(
            "x-anthropic-billing-header: cch=aaa111\n" + Self.syntheticBody
        ).body
        let bodyB = ContextCompactionEngine.splitVolatilePreamble(
            "x-anthropic-billing-header: cch=bbb222\n" + Self.syntheticBody
        ).body

        let keyA = ContextCompactionCache.key(rulesetVersion: 7, body: bodyA)
        let keyB = ContextCompactionCache.key(rulesetVersion: 7, body: bodyB)
        #expect(keyA == keyB)
    }

    @Test func cacheKeyChangesWithRulesetVersion() {
        let keyV1 = ContextCompactionCache.key(rulesetVersion: 1, body: Self.syntheticBody)
        let keyV2 = ContextCompactionCache.key(rulesetVersion: 2, body: Self.syntheticBody)
        #expect(keyV1 != keyV2)
    }

    // MARK: - Cache behavior

    @Test func cacheEvictsOldestBeyondCapacity() {
        let cache = ContextCompactionCache(capacity: 2)
        cache.store(.miss, forKey: "k1")
        cache.store(.miss, forKey: "k2")
        cache.store(.miss, forKey: "k3")

        #expect(cache.outcome(forKey: "k1") == nil)
        #expect(cache.outcome(forKey: "k2") != nil)
        #expect(cache.outcome(forKey: "k3") != nil)
    }
}
