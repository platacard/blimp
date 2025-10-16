import Foundation
import BlimpKit
import ArgumentParser

struct Hangar: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hangar",
        abstract: "Additional checks and operations with App Store Connect API",
        subcommands: [
            Weight.self,
            Clearance.self
        ]
    )
}
