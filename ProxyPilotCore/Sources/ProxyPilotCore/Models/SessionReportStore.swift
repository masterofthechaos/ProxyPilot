import Foundation

public struct SessionReportEvent: Sendable, Codable, Equatable {
    public let id: UUID
    public let schemaVersion: Int
    public let source: String
    public let sessionID: String
    public let record: RequestRecord

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = 1,
        source: String,
        sessionID: String,
        record: RequestRecord
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.source = source
        self.sessionID = sessionID
        self.record = record
    }
}

public enum SessionReportStore {
    public static let maximumFileBytes = 8 * 1_024 * 1_024
    public static let maximumEventBytes = 64 * 1_024
    public static var defaultURL: URL {
        #if os(macOS)
        if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return applicationSupport
                .appendingPathComponent("ProxyPilot", isDirectory: true)
                .appendingPathComponent("session-report.jsonl")
        }
        #endif

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("proxypilot", isDirectory: true)
            .appendingPathComponent("session-report.jsonl")
    }

    public static func append(_ event: SessionReportEvent, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(event)
        data.append(0x0A)
        guard data.count <= maximumEventBytes else { return }

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        } else if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize),
                  size + data.count > maximumFileBytes {
            try Data().write(to: url, options: .atomic)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    public static func readEvents(from url: URL = defaultURL) throws -> [SessionReportEvent] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let start = size > UInt64(maximumFileBytes) ? size - UInt64(maximumFileBytes) : 0
        try handle.seek(toOffset: start)
        var data = try handle.readToEnd() ?? Data()
        if start > 0, let newline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(data.startIndex...newline)
        }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard line.utf8.count <= maximumEventBytes else { return nil }
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(SessionReportEvent.self, from: data)
            }
    }

    public static func reset(at url: URL = defaultURL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
