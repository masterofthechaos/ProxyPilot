import Foundation

/// Re-frames Server-Sent Events lines for the wire.
///
/// Both proxy engines consume upstream SSE line-by-line so they can inspect
/// and rewrite each event (usage accounting, provider normalization,
/// Anthropic validation). The line readers they use — `bytes.lines` on the
/// Darwin path, the newline-splitting bridge on Linux — hand back logical
/// lines with their terminators stripped, and the blank lines that separate
/// SSE events do not survive that trip. Re-emitting each line with a single
/// `\n` therefore produces a stream that *looks* correct in a log but never
/// terminates an event.
///
/// That distinction is not cosmetic. An SSE client dispatches an event only
/// when it sees a blank line, so a spec-compliant parser fed single-newline
/// frames buffers the entire response and delivers nothing: no text, no
/// usage, no finish reason. Lenient clients tolerate it, which is why the
/// defect can sit unnoticed behind whichever consumer happens to be forgiving.
///
/// `AnthropicTranslator.streamingEvent` already emits the correct
/// `event: …\ndata: …\n\n` shape for events it generates; this type is the
/// same convention applied to the passthrough paths, which re-emit lines that
/// arrived from upstream.
public enum SSEFraming {
    /// Returns `line` with the terminator that SSE framing requires.
    ///
    /// A `data:` line ends its event, so it takes the blank-line terminator
    /// (`\n\n`). Every other field line — `event:`, `id:`, `retry:`, and
    /// comments — belongs to an event still being accumulated and takes a
    /// single `\n`, which is what keeps multi-line events such as Anthropic's
    /// `event:`/`data:` pairs intact.
    ///
    /// Blank input returns blank output: the separators upstream sent are
    /// regenerated here, so a surviving one would only introduce a stray
    /// empty event. Callers may write the result unconditionally —
    /// `StreamedOutputCapture.append` ignores empty chunks and both engines
    /// treat an empty write as a no-op.
    public static func terminated(_ line: String) -> String {
        guard !line.isEmpty else { return "" }
        return line.hasPrefix("data:") ? line + "\n\n" : line + "\n"
    }

    /// `terminated(_:)` encoded as UTF-8, for call sites writing straight to
    /// a socket or capture buffer.
    public static func terminatedData(_ line: String) -> Data {
        Data(terminated(line).utf8)
    }
}
