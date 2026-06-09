import Foundation

enum ShellArgumentEscaper {
    /// Wraps a value in POSIX single quotes so it can be pasted as one shell argument.
    ///
    /// Single-quoted shell strings do not evaluate command substitutions, backticks,
    /// semicolons, newlines, or double quotes. Literal single quotes are represented
    /// by closing the quote, emitting an escaped quote, then reopening the quote.
    static func singleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
