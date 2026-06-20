import ArgumentParser

struct AgentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent",
        abstract: "Manage ProxyPilot Agent mode for supported Xcode installations.",
        subcommands: [
            AgentInstallCommand.self,
            AgentStatusCommand.self,
            AgentRemoveCommand.self,
        ]
    )
}
