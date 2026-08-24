import Foundation

#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

/// Pure, deterministic section-replacement engine for Active Context
/// Compaction.
///
/// Determinism is a hard requirement, not a nicety: llama.cpp-based
/// runtimes (Ollama, LM Studio) reuse their KV cache only when the prompt
/// prefix is byte-stable across requests. The engine is therefore a pure
/// function of (system text, ruleset) — no clock, randomness, or session
/// state — and callers must forward the original text untouched whenever
/// `body` comes back nil.
public enum ContextCompactionEngine {
    /// Exact leading line the Xcode Claude Agent prepends per request with
    /// a rotating `cch=<hex>` value. Same literal that
    /// `PromptCacheAdapter.removeLeadingAnthropicBillingHeader` keys on.
    public static let volatileBillingPrefix = "x-anthropic-billing-header:"

    public struct Result: Sendable, Equatable {
        /// Compacted body text, or nil when nothing was recognized
        /// (fail-open passthrough).
        public let body: String?
        public let matchedRuleIDs: [String]

        public init(body: String?, matchedRuleIDs: [String] = []) {
            self.body = body
            self.matchedRuleIDs = matchedRuleIDs
        }
    }

    /// Splits the volatile per-request billing line (if present) from the
    /// stable remainder. The preamble — including its trailing newline —
    /// must be reattached unchanged to any compacted output, and excluded
    /// from cache keys so rotating `cch=` values cannot defeat the cache.
    public static func splitVolatilePreamble(_ text: String) -> (preamble: String, body: String) {
        guard text.hasPrefix(volatileBillingPrefix) else {
            return (preamble: "", body: text)
        }
        guard let newline = text.range(of: "\n") else {
            // The entire text is the billing line; nothing stable to compact.
            return (preamble: text, body: "")
        }
        return (preamble: String(text[..<newline.upperBound]), body: String(text[newline.upperBound...]))
    }

    /// Attempts to compact a stable (preamble-free) system body.
    ///
    /// Gate: the ruleset must be non-empty, the body at least
    /// `minimumSystemLength` UTF-8 bytes, and every wall sentinel present.
    /// Sections run from a rule's `startAnchor` to the next located
    /// anchor (or end of text); each is replaced only when its
    /// CRLF-normalized SHA-256 equals the rule's hash. Zero matches —
    /// including any gate failure — returns `body: nil`.
    public static func compactBody(_ body: String, ruleset: ContextCompactionRuleset) -> Result {
        guard !ruleset.rules.isEmpty,
              !ruleset.wallSentinels.isEmpty,
              body.utf8.count >= ruleset.minimumSystemLength,
              ruleset.wallSentinels.allSatisfy({ body.contains($0) }) else {
            return Result(body: nil)
        }

        // Single forward scan: locate each rule's anchor after the
        // previous match. Rules whose anchors are missing (or appear out
        // of order) simply don't participate.
        var located: [(rule: ContextCompactionRule, range: Range<String.Index>)] = []
        var searchStart = body.startIndex
        for rule in ruleset.rules {
            if let anchorRange = body.range(of: rule.startAnchor, range: searchStart..<body.endIndex) {
                located.append((rule: rule, range: anchorRange))
                searchStart = anchorRange.upperBound
            }
        }
        guard !located.isEmpty else {
            return Result(body: nil)
        }

        var output = String(body[..<located[0].range.lowerBound])
        var matchedRuleIDs: [String] = []
        for (index, entry) in located.enumerated() {
            let sectionEnd = index + 1 < located.count ? located[index + 1].range.lowerBound : body.endIndex
            let section = String(body[entry.range.lowerBound..<sectionEnd])
            if sha256Hex(normalizeLineEndings(section)) == entry.rule.sectionSHA256 {
                matchedRuleIDs.append(entry.rule.id)
                output += entry.rule.condensedReplacement
            } else {
                output += section
            }
        }

        guard !matchedRuleIDs.isEmpty else {
            return Result(body: nil)
        }
        return Result(body: output, matchedRuleIDs: matchedRuleIDs)
    }

    /// CRLF → LF only. No other normalization: hashes must stay pinned to
    /// the text that was analyzed by hand.
    static func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
    }

    static func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
