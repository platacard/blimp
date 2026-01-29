import Foundation
import ArgumentParser
import BlimpKit

@main
struct BlimpCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "blimp",
        abstract: "Command line tools to manage iOS apps distribution",
        subcommands: [
            TakeOff.self,
            Approach.self,
            Land.self,
            Hangar.self,
            Maintenance.self
        ]
    )
}
