import XCTest
@testable import ProxyPilot

final class ShellArgumentEscaperTests: XCTestCase {
    func testSingleQuoteWrapsSafeValues() {
        XCTAssertEqual(ShellArgumentEscaper.singleQuote("preferred=glm-5"), "'preferred=glm-5'")
    }

    func testSingleQuotePreventsCommandSubstitutionCharactersFromBecomingSyntax() {
        let malicious = "preferred=$(printf PWNED >/tmp/proxypilot_marker);`id`\nnext"

        XCTAssertEqual(
            ShellArgumentEscaper.singleQuote(malicious),
            "'preferred=$(printf PWNED >/tmp/proxypilot_marker);`id`\nnext'"
        )
    }

    func testSingleQuoteEscapesEmbeddedSingleQuotes() {
        XCTAssertEqual(
            ShellArgumentEscaper.singleQuote("preferred=bad'quote"),
            "'preferred=bad'\\''quote'"
        )
    }
}
