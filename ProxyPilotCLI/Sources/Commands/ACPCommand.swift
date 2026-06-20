import ArgumentParser

struct ACPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "acp",
        abstract: "Manage Xcode ACP agent registration for ProxyPilot.",
        shouldDisplay: false,
        subcommands: [
            ACPRegisterCommand.self,
            ACPRemoveCommand.self,
            ACPStatusCommand.self,
        ]
    )
}
