import ArgumentParser
import Foundation
import ProxyPilotCore

struct ProvidersCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "providers", abstract: "Inspect provider metadata.", subcommands: [ProvidersListCommand.self])
}

struct ProvidersListCommand: ParsableCommand {
    private struct Entry: Encodable { let id: String; let title: String; let credentialRequired: Bool; enum CodingKeys: String, CodingKey { case id, title; case credentialRequired = "credential_required" } }
    private struct Payload: Encodable { let providers: [Entry] }
    static let configuration = CommandConfiguration(commandName: "list")
    @Flag(name: .long) var json = false
    func run() throws {
        let values = UpstreamProvider.allCases.map { Entry(id: $0.rawValue, title: $0.title, credentialRequired: $0.requiresAPIKey) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Payload(providers: values))
        print(String(decoding: data, as: UTF8.self))
    }
}
