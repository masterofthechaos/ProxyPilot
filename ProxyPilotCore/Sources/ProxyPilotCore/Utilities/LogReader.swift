import Foundation

public enum LogReader {

    /// Default proxy log file path.
    public static let defaultLogURL = URL(fileURLWithPath: "/tmp/proxypilot_builtin_proxy.log")

    /// Read the last N lines from a log file, optionally redacting secrets.
    public static func tail(url: URL, lines: Int, redact: Bool = false) -> [String] {
        guard lines > 0 else { return [] }

        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        let allLines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let trimmed = allLines.filter { !$0.isEmpty }
        let sliced = Array(trimmed.suffix(lines))

        guard redact else { return sliced }
        return sliced.map { redactSecrets(in: $0) }
    }

    private static func redactSecrets(in line: String) -> String {
        var result = line
        // Redact Bearer tokens
        result = replacingAllMatches(in: result, pattern: "Bearer [^ \"]+", with: "Bearer [REDACTED]")
        // Redact api_key values
        result = replacingAllMatches(in: result, pattern: "api_key=[^ &\"]+", with: "api_key=[REDACTED]")
        // Redact Authorization header values
        result = replacingAllMatches(in: result, pattern: "Authorization: [^\r\n]+", with: "Authorization: [REDACTED]")
        return result
    }

    private static func replacingAllMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}
