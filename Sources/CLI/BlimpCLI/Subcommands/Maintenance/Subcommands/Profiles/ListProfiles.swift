import ArgumentParser
import BlimpKit
import Cronista
import Foundation

struct ListProfiles: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-profiles",
        abstract: "List provisioning profiles in Apple Developer Portal"
    )

    @Option(help: "Filter by profile name")
    var name: String?

    func run() async throws {
        let logger = Cronista(module: "blimp", category: "Maintenance")
        let profiles = try await Blimp.Maintenance.default.listProfiles(name: name)

        if profiles.isEmpty {
            logger.info("No profiles found")
        } else {
            logger.info("Profiles:")
            for profile in profiles {
                let typeStr = profile.type?.rawValue ?? "unknown"
                logger.info("  \(profile.name) (\(typeStr))")
                logger.info("    ID: \(profile.id)")
                if let expDate = profile.expirationDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    logger.info("    Expires: \(formatter.string(from: expDate))")
                }
            }
        }
    }
}
