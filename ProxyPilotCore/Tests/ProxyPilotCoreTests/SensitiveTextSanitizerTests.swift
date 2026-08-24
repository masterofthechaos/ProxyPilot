import Testing
@testable import ProxyPilotCore

@Suite struct SensitiveTextSanitizerTests {
    @Test func stripsControlLinesSecretsAndBoundsOutput() {
        let value = "first\nAuthorization: Bearer secret-token api_key=hidden"
        let result = SensitiveTextSanitizer.sanitize(value, maxCharacters: 40)
        #expect(!result.contains("\n"))
        #expect(!result.contains("secret-token"))
        #expect(!result.contains("hidden"))
        #expect(result.count <= 43)
    }
}
