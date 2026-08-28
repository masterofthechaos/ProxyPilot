import Foundation

/// Provider adapter for RepoGPS Tutor. The public RepoGPS contract speaks in
/// terms of consult and delegate; this adapter projects those roles onto
/// OpenRouter server tools for the first backend implementation.
///
/// `consultation_policy: "required"` means "consult the Advisor at least once
/// per user turn" — not "force a tool call on every round." This adapter is
/// stateless, but every request carries the full OpenAI chat-completions
/// `messages` history, so per-turn state is derived from that history rather
/// than stored: `tool_choice: "required"` is only set on the FIRST round of
/// the current user turn — the round that begins immediately after the last
/// `role: "user"` message, before any assistant tool call or tool result has
/// appeared later in that same turn. Once the model has issued a tool call
/// in the current turn (resolved or not), forcing is not reapplied until the
/// next `role: "user"` message opens a new turn, even if earlier turns
/// contained tool activity. If `messages` is missing, malformed, or not an
/// array of message objects, the adapter fails safe by NOT forcing —
/// termination beats forcing. This logic assumes OpenAI chat-completions
/// message shape (`role: "tool"` for tool results); it only ever runs on the
/// `/v1/chat/completions` route, which is not reachable from the separate
/// Anthropic `/v1/messages` translation path in either proxy engine.
public enum TutorRequestAdapter {
    public static let headerName = "X-RepoGPS-Tutor"

    public static func mutateChatCompletionsBody(
        _ body: Data,
        envelopeHeader: String?,
        attribution: RequestAttribution?,
        provider: UpstreamProvider
    ) -> Data {
        guard provider == .openRouter,
              attribution?.client == "repogps",
              let envelopeHeader,
              let envelope = decodeEnvelope(envelopeHeader),
              envelope.backend == "openrouter",
              var request = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return body
        }

        let toolsValue = request["tools"]
        guard toolsValue == nil || toolsValue is [[String: Any]] else {
            return body
        }
        // Canonical envelope-derived projections win: any caller-supplied tool
        // claiming a reserved Tutor server-tool type is dropped and replaced,
        // never merged, so a client can never shadow the envelope's validated
        // advisor/worker parameters by pre-supplying its own tool of that type.
        var tools = (toolsValue as? [[String: Any]] ?? []).filter { tool in
            !Self.reservedToolTypes.contains(tool["type"] as? String ?? "")
        }
        tools.append(advisorTool(envelope.advisor))
        tools.append(subagentTool(envelope.worker, webAccess: envelope.workerWebAccess))
        request["tools"] = tools
        if envelope.consultationPolicy == "required", isFirstRoundOfCurrentUserTurn(request["messages"]) {
            request["tool_choice"] = "required"
        }
        return (try? JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])) ?? body
    }

    private static let reservedToolTypes: Set<String> = ["openrouter:advisor", "openrouter:subagent"]

    /// Returns true only for the first round of the current user turn, i.e.
    /// the span of `messages` after the last `role: "user"` message contains
    /// neither an assistant message with a non-empty `tool_calls` array nor
    /// any `role: "tool"` message. See the type-level doc comment for the
    /// consultation-policy rationale. Fails safe to `false` (do not force)
    /// when `messages` is missing, not an array, or contains non-object
    /// entries, and when no `role: "user"` message is present at all.
    private static func isFirstRoundOfCurrentUserTurn(_ messagesValue: Any?) -> Bool {
        guard let messages = messagesValue as? [[String: Any]] else { return false }
        guard let lastUserIndex = messages.lastIndex(where: { ($0["role"] as? String) == "user" }) else {
            return false
        }
        let span = messages[(lastUserIndex + 1)...]
        let hasAssistantToolCall = span.contains { message in
            (message["role"] as? String) == "assistant"
                && !((message["tool_calls"] as? [Any])?.isEmpty ?? true)
        }
        let hasToolResult = span.contains { ($0["role"] as? String) == "tool" }
        return !hasAssistantToolCall && !hasToolResult
    }

    private static func advisorTool(_ role: Role) -> [String: Any] {
        [
            "type": "openrouter:advisor",
            "parameters": [
                "name": "Tutor",
                "model": role.model,
                "instructions": "Act as RepoGPS Tutor: challenge assumptions, identify correctness and safety risks, and return concise, actionable guidance. Do not attempt to re-enter Tutor.",
                "forward_transcript": false,
                "max_completion_tokens": role.maxCompletionTokens,
                "max_tool_calls": role.maxToolCalls,
            ],
        ]
    }

    private static func subagentTool(_ role: Role, webAccess: Bool) -> [String: Any] {
        var parameters: [String: Any] = [
            "model": role.model,
            "instructions": "Act as a focused RepoGPS Tutor worker. Complete only the self-contained task description, preserve its constraints, and return the requested outcome without assuming parent-conversation context.",
            "max_completion_tokens": role.maxCompletionTokens,
            "max_tool_calls": role.maxToolCalls,
        ]
        if webAccess {
            parameters["tools"] = [["type": "openrouter:web_search"]]
        }
        return ["type": "openrouter:subagent", "parameters": parameters]
    }

    private static func decodeEnvelope(_ value: String) -> Envelope? {
        guard value.utf8.count <= 8_192 else { return nil }
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1,
              ["automatic", "required"].contains(envelope.consultationPolicy),
              envelope.advisor.isValid,
              envelope.worker.isValid
        else {
            return nil
        }
        return envelope
    }

    private struct Envelope: Decodable {
        let version: Int
        let backend: String
        let consultationPolicy: String
        let advisor: Role
        let worker: Role
        let workerWebAccess: Bool

        enum CodingKeys: String, CodingKey {
            case version
            case backend
            case consultationPolicy = "consultation_policy"
            case advisor
            case worker
            case workerWebAccess = "worker_web_access"
        }
    }

    private struct Role: Decodable {
        let model: String
        let maxCompletionTokens: Int
        let maxToolCalls: Int

        var isValid: Bool {
            !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && model.utf8.count <= 512
                && (1...65_536).contains(maxCompletionTokens)
                && (1...25).contains(maxToolCalls)
        }

        enum CodingKeys: String, CodingKey {
            case model
            case maxCompletionTokens = "max_completion_tokens"
            case maxToolCalls = "max_tool_calls"
        }
    }
}
