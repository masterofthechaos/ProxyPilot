import ArgumentParser
import Foundation

struct CapabilitiesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "capabilities", abstract: "Report machine-readable integration contract versions.")
    @Flag(name: .long) var json = false
    func run() throws {
        let payload: [String: Int] = ["route_control": 1, "active_model_aliasing": 1, "request_attribution": 1, "session_storage": 1]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
