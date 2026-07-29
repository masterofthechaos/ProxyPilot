import Foundation
import Testing
@testable import ProxyPilotCore

@Suite struct ActiveModelAliasTests {
    @Test func aliasRequiresAnActiveAllowlist() {
        #expect(ActiveModelAlias.accepts(ActiveModelAlias.id, allowedModels: ["actual-model"]))
        #expect(!ActiveModelAlias.accepts(ActiveModelAlias.id, allowedModels: []))
        #expect(ActiveModelAlias.accepts("actual-model", allowedModels: ["actual-model"]))
        #expect(!ActiveModelAlias.accepts("other", allowedModels: ["actual-model"]))
    }

    @Test func rewritesAliasAndNeverChangesLiteralModels() throws {
        let aliasBody = Data(#"{"model":"proxypilot-active","messages":[]}"#.utf8)
        let rewritten = ActiveModelAlias.rewriteJSONBody(aliasBody, activeModel: "provider-model")
        let object = try #require(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        #expect(object["model"] as? String == "provider-model")

        let literal = Data(#"{"model":"literal","messages":[]}"#.utf8)
        #expect(ActiveModelAlias.rewriteJSONBody(literal, activeModel: "provider-model") == literal)
        #expect(ActiveModelAlias.rewriteJSONBody(aliasBody, activeModel: "") == aliasBody)
    }
}
