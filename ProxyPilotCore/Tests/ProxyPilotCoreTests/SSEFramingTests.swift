import Foundation
import Testing
@testable import ProxyPilotCore

/// A deliberately strict SSE reader: it dispatches an event only on a blank
/// line, exactly as `EventSource` and the AI SDK's parser do. Lenient readers
/// that dispatch per `data:` line hide the framing defect these tests pin, so
/// the strictness is the point — a forgiving parser here would let the
/// regression back in.
private struct StrictSSEReader {
    private(set) var dispatched: [String] = []

    static func parse(_ stream: String) -> [String] {
        var reader = StrictSSEReader()
        var pendingData: [String] = []
        // Splitting on "\n" yields a trailing empty element for any stream
        // ending in a newline. That artifact is not a blank line on the wire,
        // and counting it as one would fabricate an event terminator the
        // client never saw — the exact failure this suite exists to catch.
        var lines = stream.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        for line in lines {
            if line.isEmpty {
                if !pendingData.isEmpty {
                    reader.dispatched.append(pendingData.joined(separator: "\n"))
                    pendingData.removeAll()
                }
                continue
            }
            if line.hasPrefix(":") { continue }
            if line.hasPrefix("data:") {
                pendingData.append(String(line.dropFirst("data:".count))
                    .trimmingCharacters(in: .whitespaces))
            }
        }
        // Per the SSE specification, any data still pending when the stream
        // ends is discarded rather than dispatched. Modelling that is what
        // makes this reader a faithful stand-in for the client that dropped
        // the RepoGPS responses.
        return reader.dispatched
    }
}

@Suite struct SSEFramingTests {
    /// The chunk shape OpenRouter actually returned for the RepoGPS session
    /// that rendered nothing (session `716e6497`, 2026-08-05).
    private static let contentChunk =
        #"data: {"choices":[{"index":0,"delta":{"content":"Hello! How can I help you?","role":"assistant"},"finish_reason":null}]}"#
    private static let stopChunk =
        #"data: {"choices":[{"index":0,"delta":{"content":""},"finish_reason":"stop"}],"usage":{"completion_tokens":230}}"#
    private static let doneChunk = "data: [DONE]"

    @Test func dataLinesTakeTheBlankLineTerminator() {
        #expect(SSEFraming.terminated("data: {\"a\":1}") == "data: {\"a\":1}\n\n")
        #expect(SSEFraming.terminated("data: [DONE]") == "data: [DONE]\n\n")
    }

    @Test func nonDataFieldLinesStayInsideTheSameEvent() {
        // Anthropic sends `event:` and `data:` as one two-line event. A blank
        // line after `event:` would split it into two malformed events.
        #expect(SSEFraming.terminated("event: content_block_delta") == "event: content_block_delta\n")
        #expect(SSEFraming.terminated("id: 42") == "id: 42\n")
        #expect(SSEFraming.terminated(": OPENROUTER PROCESSING") == ": OPENROUTER PROCESSING\n")
    }

    @Test func blankInputStaysBlankSoSurvivingSeparatorsDoNotDoubleUp() {
        #expect(SSEFraming.terminated("") == "")
        #expect(SSEFraming.terminatedData("").isEmpty)
    }

    @Test func anthropicTwoLineEventReassemblesIntoOneDispatch() {
        let stream = SSEFraming.terminated("event: content_block_delta")
            + SSEFraming.terminated(#"data: {"type":"content_block_delta"}"#)
        #expect(stream == "event: content_block_delta\ndata: {\"type\":\"content_block_delta\"}\n\n")
        #expect(StrictSSEReader.parse(stream).count == 1)
    }

    /// The regression pin. Reverting `SSEFraming.terminated` to `line + "\n"`
    /// must make this fail — that single-newline form is precisely what
    /// shipped, and a strict client extracted nothing from it.
    @Test func strictClientRecoversEveryEventFromFramedOutput() {
        let framed = [Self.contentChunk, Self.stopChunk, Self.doneChunk]
            .map(SSEFraming.terminated)
            .joined()

        let events = StrictSSEReader.parse(framed)

        #expect(events.count == 3)
        #expect(events.first?.contains("Hello! How can I help you?") == true)
        #expect(events.dropFirst().first?.contains("\"finish_reason\":\"stop\"") == true)
        #expect(events.last == "[DONE]")
    }

    /// Documents the defect itself: single-newline separators leave a strict
    /// client with zero dispatched events even though every byte of content
    /// is present in the stream. This is why OpenCode recorded an assistant
    /// turn with no text, `reason: "unknown"`, and zero tokens.
    @Test func singleNewlineSeparatorsStrandEveryEvent() {
        let unframed = [Self.contentChunk, Self.stopChunk, Self.doneChunk]
            .map { $0 + "\n" }
            .joined()

        #expect(unframed.contains("Hello! How can I help you?"))
        #expect(StrictSSEReader.parse(unframed).isEmpty)
    }
}
