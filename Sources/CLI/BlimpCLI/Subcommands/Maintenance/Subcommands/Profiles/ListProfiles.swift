import ArgumentParser
import BlimpKit
import Foundation

struct ListProfiles: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-profiles",
        abstract: "List provisioning profiles in Apple Developer Portal"
    )

    @Option(help: "Filter by profile name")
    var name: String?

    func run() async throws {
        let profiles = try await Blimp.Maintenance.default.listProfiles(name: name)

        if profiles.isEmpty {
            print("No profiles found")
        } else {
            print("Profiles:")
            for profile in profiles {
                let typeStr = profile.type?.rawValue ?? "unknown"
                print("  \(profile.name) (\(typeStr))")
                print("    ID: \(profile.id)")
                if let expDate = profile.expirationDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    print("    Expires: \(formatter.string(from: expDate))")
                }
            }
        }
    }
}
