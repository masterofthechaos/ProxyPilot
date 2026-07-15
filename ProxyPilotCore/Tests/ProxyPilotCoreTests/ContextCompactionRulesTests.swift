import Foundation
import Testing
@testable import ProxyPilotCore

/// Invariants any shipped production ruleset must satisfy. The v1 ruleset
/// is intentionally empty (no capture existed to author rules from), so
/// several checks pass trivially — they harden the follow-up that adds
/// real rules.
@Suite("ContextCompactionRules")
struct ContextCompactionRulesTests {
    private let ruleset = ContextCompactionRules.ruleset

    @Test func versionIsPositive() {
        #expect(ruleset.version >= 1)
    }

    @Test func minimumLengthGuardsAgainstSmallPrompts() {
        // The wall is ~30k tokens; anything conversational must never gate in.
        #expect(ruleset.minimumSystemLength >= 10_000)
    }

    @Test func ruleIDsAreUniqueAndNonEmpty() {
        let ids = ruleset.rules.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { !$0.isEmpty })
    }

    @Test func anchorsAreNonEmpty() {
        #expect(ruleset.rules.allSatisfy { !$0.startAnchor.isEmpty })
    }

    @Test func hashesAreLowercaseHexSHA256() {
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        for rule in ruleset.rules {
            #expect(rule.sectionSHA256.count == 64, "\(rule.id)")
            #expect(rule.sectionSHA256.unicodeScalars.allSatisfy { hexCharacters.contains($0) }, "\(rule.id)")
        }
    }

    @Test func replacementsAreNonEmptyAndShorterIsTheGoal() {
        // Boundary-only rules (unmatchable all-zero hash) exist purely to
        // delimit neighboring sections and never substitute their (empty)
        // replacement; every fireable rule must replace with something.
        for rule in ruleset.rules where rule.sectionSHA256 != ContextCompactionRules.neverMatches {
            #expect(!rule.condensedReplacement.isEmpty, "\(rule.id)")
        }
    }

    @Test func boundaryRulesCanNeverFire() {
        // An all-zero "hash" is not the SHA-256 of any text, so a boundary
        // rule's empty replacement is unreachable by construction.
        for rule in ruleset.rules where rule.condensedReplacement.isEmpty {
            #expect(rule.sectionSHA256 == ContextCompactionRules.neverMatches, "\(rule.id)")
        }
    }

    @Test func sentinelsRequiredWheneverRulesExist() {
        // A ruleset with rules but no sentinels would skip the wall gate.
        if !ruleset.rules.isEmpty {
            #expect(!ruleset.wallSentinels.isEmpty)
        }
    }

    @Test func v2RulesetShipsRealRules() {
        // v2 was authored from the 2026-07-14 private capture of the Xcode
        // 26.3 Claude Agent wall. Sentinels + rules present means the MVP
        // feature gate is open: ACCA's GUI section renders and CLI/GUI
        // configuration paths resolve normally.
        #expect(ruleset.version == 2)
        #expect(!ruleset.rules.isEmpty)
        #expect(!ruleset.wallSentinels.isEmpty)
        #expect(ruleset.providesMVPFunctionality)
        #expect(ContextCompactionFeatureGate.isAvailable)
    }

    @Test func condensedOutputIsSubstantiallySmaller() {
        // The point of the ruleset: firing every fireable rule must shrink
        // the wall. Compare replacement bytes against a conservative floor —
        // the real sections measured 27k+ at capture time.
        let replacementBytes = ruleset.rules.map(\.condensedReplacement.utf8.count).reduce(0, +)
        #expect(replacementBytes < 20_000)
    }

    @Test func featureGateOpensOnlyWithSentinelsAndRules() {
        let rule = ContextCompactionRule(
            id: "tone",
            startAnchor: "## Tone",
            sectionSHA256: String(repeating: "a", count: 64),
            condensedReplacement: "condensed"
        )
        let complete = ContextCompactionRuleset(
            version: 2, wallSentinels: ["sentinel"], minimumSystemLength: 20_000, rules: [rule]
        )
        let rulesButNoSentinels = ContextCompactionRuleset(
            version: 2, wallSentinels: [], minimumSystemLength: 20_000, rules: [rule]
        )
        let sentinelsButNoRules = ContextCompactionRuleset(
            version: 2, wallSentinels: ["sentinel"], minimumSystemLength: 20_000, rules: []
        )
        #expect(complete.providesMVPFunctionality)
        #expect(!rulesButNoSentinels.providesMVPFunctionality)
        #expect(!sentinelsButNoRules.providesMVPFunctionality)
    }
}
