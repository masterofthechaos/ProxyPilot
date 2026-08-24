import Foundation

public enum ActiveModelAlias {
    public static let id = "proxypilot-active"
    public static func accepts(
        _ requested: String,
        allowedModels: Set<String>,
        activeModel: String
    ) -> Bool {
        requested == id
            ? !allowedModels.isEmpty && allowedModels.contains(activeModel)
            : ModelFilter.isAllowed(requested, in: allowedModels)
    }
    public static func rewriteJSONBody(_ body: Data, activeModel: String) -> Data {
        guard !activeModel.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["model"] as? String == id,
              let data = try? JSONSerialization.data(withJSONObject: object.merging(["model": activeModel]) { _, new in new }) else { return body }
        return data
    }
}
