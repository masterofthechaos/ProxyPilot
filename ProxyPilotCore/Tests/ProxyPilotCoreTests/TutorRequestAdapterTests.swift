import Foundation
import XCTest
@testable import ProxyPilotCore

final class TutorRequestAdapterTests: XCTestCase {
    private let attribution = RequestAttribution(
        client: "repogps",
        sessionID: "00000000-0000-0000-0000-000000000123"
    )

    func testProjectsAdvisorThenSubagentWithoutDisturbingClientTools() throws {
        let original: [String: Any] = [
            "model": "proxypilot-active",
            "messages": [["role": "user", "content": "test"]],
            "tools": [[
                "type": "function",
                "function": ["name": "read_file", "parameters": ["type": "object"]],
            ]],
        ]
        let result = TutorRequestAdapter.mutateChatCompletionsBody(
            try JSONSerialization.data(withJSONObject: original),
            envelopeHeader: envelope(workerWebAccess: true),
            attribution: attribution,
            provider: .openRouter
        )
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: Any])
        let tools = try XCTUnwrap(request["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools[0]["type"] as? String, "function")
        XCTAssertEqual(tools[1]["type"] as? String, "openrouter:advisor")
        XCTAssertEqual(tools[2]["type"] as? String, "openrouter:subagent")

        let advisor = try XCTUnwrap(tools[1]["parameters"] as? [String: Any])
        XCTAssertEqual(advisor["name"] as? String, "Tutor")
        XCTAssertEqual(advisor["model"] as? String, "~advisor/example")
        XCTAssertEqual(advisor["forward_transcript"] as? Bool, false)
        XCTAssertEqual(advisor["max_completion_tokens"] as? Int, 4096)
        XCTAssertEqual(advisor["max_tool_calls"] as? Int, 3)

        let worker = try XCTUnwrap(tools[2]["parameters"] as? [String: Any])
        XCTAssertEqual(worker["model"] as? String, "~worker/example")
        XCTAssertEqual(worker["max_completion_tokens"] as? Int, 2048)
        XCTAssertEqual(worker["max_tool_calls"] as? Int, 5)
        let nested = try XCTUnwrap(worker["tools"] as? [[String: Any]])
        XCTAssertEqual(nested.count, 1)
        XCTAssertEqual(nested[0]["type"] as? String, "openrouter:web_search")
        XCTAssertNil(request["tool_choice"])
    }

    func testRequiredPolicyForcesConsultation() throws {
        // First round of the turn: messages end in a user message with no
        // tool activity yet, so forcing applies.
        let result = TutorRequestAdapter.mutateChatCompletionsBody(
            requestBody(),
            envelopeHeader: envelope(policy: "required"),
            attribution: attribution,
            provider: .openRouter
        )
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: Any])
        XCTAssertEqual(request["tool_choice"] as? String, "required")
    }

    func testRequiredPolicyDoesNotForceOnContinuationRound() throws {
        // Continuation round: the last user message is followed by an
        // assistant tool call and its role-"tool" result. Consultation
        // already happened this turn, so forcing must not be reapplied, and
        // a client-sent tool_choice value must survive untouched.
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "proxypilot-active",
            "messages": [
                ["role": "user", "content": "test"],
                [
                    "role": "assistant",
                    "content": NSNull(),
                    "tool_calls": [
                        ["id": "call_1", "type": "function", "function": ["name": "read_file", "arguments": "{}"]],
                    ],
                ],
                ["role": "tool", "tool_call_id": "call_1", "content": "file contents"],
            ],
            "tool_choice": "auto",
        ])
        let result = TutorRequestAdapter.mutateChatCompletionsBody(
            body,
            envelopeHeader: envelope(policy: "required"),
            attribution: attribution,
            provider: .openRouter
        )
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: Any])
        XCTAssertEqual(request["tool_choice"] as? String, "auto")
    }

    func testRequiredPolicyForcesAgainOnNewUserTurnAfterPriorToolActivity() throws {
        // A new user turn opens after an earlier turn that already contained
        // tool activity. The earlier assistant tool_calls message sits
        // BEFORE the last user message, so it must not suppress forcing for
        // this new turn.
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "proxypilot-active",
            "messages": [
                ["role": "user", "content": "first turn"],
                [
                    "role": "assistant",
                    "content": NSNull(),
                    "tool_calls": [
                        ["id": "call_1", "type": "function", "function": ["name": "read_file", "arguments": "{}"]],
                    ],
                ],
                ["role": "tool", "tool_call_id": "call_1", "content": "file contents"],
                ["role": "assistant", "content": "here is the answer"],
                ["role": "user", "content": "second turn"],
            ],
        ])
        let result = TutorRequestAdapter.mutateChatCompletionsBody(
            body,
            envelopeHeader: envelope(policy: "required"),
            attribution: attribution,
            provider: .openRouter
        )
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: Any])
        XCTAssertEqual(request["tool_choice"] as? String, "required")
    }

    func testNonRepoGPSAndNonOpenRouterRequestsRemainByteIdentical() {
        let body = requestBody()
        XCTAssertEqual(
            TutorRequestAdapter.mutateChatCompletionsBody(
                body,
                envelopeHeader: envelope(),
                attribution: nil,
                provider: .openRouter
            ),
            body
        )
        XCTAssertEqual(
            TutorRequestAdapter.mutateChatCompletionsBody(
                body,
                envelopeHeader: envelope(),
                attribution: attribution,
                provider: .openAI
            ),
            body
        )
    }

    func testMalformedUnknownAndOverBudgetEnvelopesFailClosed() {
        let body = requestBody()
        for header in [
            "not-base64",
            envelope(version: 2),
            envelope(advisorMaxToolCalls: 26),
            envelope(backend: "bespoke"),
        ] {
            XCTAssertEqual(
                TutorRequestAdapter.mutateChatCompletionsBody(
                    body,
                    envelopeHeader: header,
                    attribution: attribution,
                    provider: .openRouter
                ),
                body
            )
        }
    }

    func testMalformedClientToolsRemainByteIdentical() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "test",
            "messages": [],
            "tools": ["not-a-tool-object"],
        ])
        XCTAssertEqual(
            TutorRequestAdapter.mutateChatCompletionsBody(
                body,
                envelopeHeader: envelope(),
                attribution: attribution,
                provider: .openRouter
            ),
            body
        )
    }

    func testExistingServerToolsAreNotDuplicated() throws {
        // Caller-supplied tools claiming the reserved advisor/subagent types
        // must be REPLACED by the canonical envelope-derived projections, not
        // merged with them and not left to shadow the envelope's validated
        // parameters. Other client tools survive, in their original order.
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "test",
            "messages": [["role": "user", "content": "test"]],
            "tools": [
                ["type": "function", "function": ["name": "read_file", "parameters": ["type": "object"]]],
                ["type": "openrouter:advisor", "parameters": ["name": "Existing", "model": "attacker-controlled"]],
                ["type": "openrouter:subagent", "parameters": ["model": "~worker/existing"]],
            ],
        ])
        let result = TutorRequestAdapter.mutateChatCompletionsBody(
            body,
            envelopeHeader: envelope(workerWebAccess: true),
            attribution: attribution,
            provider: .openRouter
        )
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: Any])
        let tools = try XCTUnwrap(request["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools[0]["type"] as? String, "function")
        XCTAssertEqual(tools[1]["type"] as? String, "openrouter:advisor")
        XCTAssertEqual(tools[2]["type"] as? String, "openrouter:subagent")

        let advisor = try XCTUnwrap(tools[1]["parameters"] as? [String: Any])
        XCTAssertEqual(advisor["name"] as? String, "Tutor")
        XCTAssertEqual(advisor["model"] as? String, "~advisor/example")
        XCTAssertEqual(advisor["max_completion_tokens"] as? Int, 4096)
        XCTAssertEqual(advisor["max_tool_calls"] as? Int, 3)

        let worker = try XCTUnwrap(tools[2]["parameters"] as? [String: Any])
        XCTAssertEqual(worker["model"] as? String, "~worker/example")
        XCTAssertEqual(worker["max_completion_tokens"] as? Int, 2048)
        XCTAssertEqual(worker["max_tool_calls"] as? Int, 5)
        let nested = try XCTUnwrap(worker["tools"] as? [[String: Any]])
        XCTAssertEqual(nested.count, 1)
        XCTAssertEqual(nested[0]["type"] as? String, "openrouter:web_search")
    }

    private func requestBody() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "model": "proxypilot-active",
            "messages": [["role": "user", "content": "test"]],
        ])
    }

    private func envelope(
        version: Int = 1,
        backend: String = "openrouter",
        policy: String = "automatic",
        advisorMaxToolCalls: Int = 3,
        workerWebAccess: Bool = false
    ) -> String {
        let value: [String: Any] = [
            "version": version,
            "backend": backend,
            "consultation_policy": policy,
            "advisor": [
                "model": "~advisor/example",
                "max_completion_tokens": 4096,
                "max_tool_calls": advisorMaxToolCalls,
            ],
            "worker": [
                "model": "~worker/example",
                "max_completion_tokens": 2048,
                "max_tool_calls": 5,
            ],
            "worker_web_access": workerWebAccess,
        ]
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
