import Foundation

public enum SensitiveTextSanitizer {
    public static func sanitize(_ text: String, maxCharacters: Int) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        var output = singleLine
        let rules: [(String, String)] = [
            (#"(?i)(bearer\s+)([^\s,;\"']+)"#, "$1***"),
            (#"(?i)((?:x-)?api[-_ ]?key\s*[:=]\s*[\"]?)([^\s,;\"']+)"#, "$1***"),
            (#"(?i)(authorization\s*[:=]\s*[\"]?)([^\r\n\"]+)"#, "$1***")
        ]
        for (pattern, replacement) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: replacement)
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard maxCharacters >= 0, trimmed.count > maxCharacters else { return trimmed }
        return String(trimmed.prefix(maxCharacters)) + "..."
    }
}
