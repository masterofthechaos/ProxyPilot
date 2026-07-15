import Foundation

/// Entry point both proxy servers call to apply Active Context Compaction
/// to an Anthropic `/v1/messages` request's top-level `system` field.
///
/// Runs pre-translation, before `AnthropicTranslator.requestToOpenAI`
/// materializes the system message — so user `messages` and `tools` are
/// structurally out of reach. The `/chat/completions` path is deliberately
/// uncovered in v1: the Xcode agent's context wall only arrives via
/// Anthropic-format `/v1/messages`. The engine operates on plain text, so
/// covering the raw OpenAI path later is one additional call on
/// `messages[0].content` where `role == "system"`.
public enum ContextCompactionAdapter {
    /// - Parameter system: the request's `system` value as received —
    ///   a `String` or an array of `{"type": "text", "text": ...}` blocks.
    /// - Returns: a mutation whose `system` is non-nil only when a
    ///   recognized wall was compacted; callers must leave the original
    ///   request value untouched otherwise.
    public static func compactAnthropicSystem(
        _ system: Any?,
        provider: UpstreamProvider,
        configuration: ContextCompactionConfiguration,
        ruleset: ContextCompactionRuleset = ContextCompactionRules.ruleset,
        cache: ContextCompactionCache = .shared
    ) -> ContextCompactionMutation {
        guard configuration.isEnabled else {
            return .passThrough(strategy: ContextCompactionStrategy.disabled)
        }
        guard provider.supportsContextCompaction else {
            return .passThrough(
                strategy: ContextCompactionStrategy.unsupportedProvider,
                notes: ["Context compaction only targets local-inference providers."]
            )
        }
        guard let systemText = flattenedSystemText(system), !systemText.isEmpty else {
            return .passThrough(strategy: ContextCompactionStrategy.noSystem)
        }

        let (preamble, body) = ContextCompactionEngine.splitVolatilePreamble(systemText)
        let cacheKey = ContextCompactionCache.key(rulesetVersion: ruleset.version, body: body)

        if let cached = cache.outcome(forKey: cacheKey) {
            switch cached {
            case .miss:
                return .passThrough(
                    strategy: ContextCompactionStrategy.fingerprintMiss,
                    notes: ["ruleset_v\(ruleset.version)", "cached_verdict"]
                )
            case .compacted(let compactedBody, let matchedRuleIDs):
                return mutation(
                    preamble: preamble,
                    compactedBody: compactedBody,
                    original: systemText,
                    matchedRuleIDs: matchedRuleIDs,
                    rulesetVersion: ruleset.version,
                    strategy: ContextCompactionStrategy.cacheHit
                )
            }
        }

        let result = ContextCompactionEngine.compactBody(body, ruleset: ruleset)
        guard let compactedBody = result.body else {
            cache.store(.miss, forKey: cacheKey)
            return .passThrough(
                strategy: ContextCompactionStrategy.fingerprintMiss,
                notes: ["ruleset_v\(ruleset.version)"]
            )
        }

        cache.store(.compacted(body: compactedBody, matchedRuleIDs: result.matchedRuleIDs), forKey: cacheKey)
        return mutation(
            preamble: preamble,
            compactedBody: compactedBody,
            original: systemText,
            matchedRuleIDs: result.matchedRuleIDs,
            rulesetVersion: ruleset.version,
            strategy: ContextCompactionStrategy.compacted
        )
    }

    /// Flattens a `system` value the same way the translator does
    /// (`AnthropicTranslator.requestToOpenAI` joins text blocks with "\n"),
    /// so replacing block arrays with one compacted string yields identical
    /// translator output.
    static func flattenedSystemText(_ system: Any?) -> String? {
        if let text = system as? String {
            return text
        }
        if let blocks = system as? [[String: Any]] {
            let text = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func mutation(
        preamble: String,
        compactedBody: String,
        original: String,
        matchedRuleIDs: [String],
        rulesetVersion: Int,
        strategy: String
    ) -> ContextCompactionMutation {
        let compacted = preamble + compactedBody
        return ContextCompactionMutation(
            system: compacted,
            applied: true,
            strategy: strategy,
            notes: ["ruleset_v\(rulesetVersion)", "rules=\(matchedRuleIDs.joined(separator: ","))"],
            originalUTF8Bytes: original.utf8.count,
            compactedUTF8Bytes: compacted.utf8.count
        )
    }
}
