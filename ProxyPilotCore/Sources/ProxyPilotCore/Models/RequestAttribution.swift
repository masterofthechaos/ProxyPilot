import Foundation

public struct RequestAttribution: Sendable, Codable, Equatable {
    public let client: String
    public let sessionID: String

    public static func validated(client: String?, sessionID: String?) -> Self? {
        guard client?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "repogps",
              let rawSessionID = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              let uuid = UUID(uuidString: rawSessionID) else { return nil }
        return .init(client: "repogps", sessionID: uuid.uuidString.lowercased())
    }

    public static func validated(headers: [String: String]) -> Self? {
        func value(_ name: String) -> String? { headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value }
        return validated(client: value("X-ProxyPilot-Client"), sessionID: value("X-ProxyPilot-Session-ID"))
    }
}

public enum RequestAttributionContext {
    @TaskLocal public static var current: RequestAttribution?
}
