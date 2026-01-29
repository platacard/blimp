import ArgumentParser
import BlimpKit
import Cronista

struct RemoveProfile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove-profile",
        abstract: "Remove a provisioning profile from Apple Developer Portal"
    )

    @Argument(help: "Profile name to remove")
    var name: String

    func run() async throws {
        let logger = Cronista(module: "blimp", category: "Maintenance")
        let profiles = try await Blimp.Maintenance.default.listProfiles(name: name)
        guard let profile = profiles.first else {
            throw ValidationError("Profile '\(name)' not found")
        }

        try await Blimp.Maintenance.default.removeProfile(id: profile.id)
        logger.success("Profile '\(name)' removed successfully")
    }
}
