import ArgumentParser
import BlimpKit
import Foundation
import Cronista
import ProvisioningAPI

struct SyncProfiles: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync-profiles",
        abstract: "Sync provisioning profiles with storage (auto-detects certificate)"
    )

    @Option(
        name: .shortAndLong,
        parsing: .upToNextOption,
        help: "Bundle IDs to sync. Use bundleId:profileName to save under a different name (e.g. com.app:com.app.ah)"
    )
    var bundleIds: [String]

    @Option(help: "Platform: ios, macos, tvos, catalyst")
    var platform: ProvisioningAPI.Platform = .ios

    @Option(help: "Profile type: development, appstore, adhoc")
    var type: CLIProfileType = .development

    @Flag(help: "Force regeneration of profiles")
    var force: Bool = false

    @Option(help: "Storage path")
    var storagePath: String = "."

    @Flag(help: "Push to remote after committing")
    var push: Bool = false

    @Option(help: "Certificate selection: 'all' (default) or comma-separated names to filter")
    var certificates: String = "all"

    func run() async throws {
        let logger = Cronista(module: "blimp", category: "Maintenance")
        let resolvedPath = storagePath == "." ? FileManager.default.currentDirectoryPath : storagePath
        let certificateNames = parseCertificateSelection(certificates)

        var parsed: [(bundleId: String, profileName: String)] = []
        for entry in bundleIds {
            let parts = entry.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard !parts.isEmpty else {
                throw ValidationError("Invalid bundleId/profileName '\(entry)'. Expected format 'bundleId' or 'bundleId:profileName'.")
            }

            let bundleId = String(parts[0])
            guard !bundleId.isEmpty else {
                throw ValidationError("Invalid bundleId/profileName '\(entry)'. Bundle ID must not be empty.")
            }

            let profileName: String
            if parts.count > 1 {
                profileName = String(parts[1])
                guard !profileName.isEmpty else {
                    throw ValidationError("Invalid bundleId/profileName '\(entry)'. Profile name must not be empty when ':' is used.")
                }
            } else {
                profileName = bundleId
            }

            parsed.append((bundleId: bundleId, profileName: profileName))
        }

        try await Blimp.Maintenance.default.syncProfiles(
            platform: platform,
            type: type.asAPI(platform: platform),
            bundleIds: parsed,
            force: force,
            storagePath: resolvedPath,
            push: push,
            certificateNames: certificateNames
        )

        logger.success("Profile sync completed successfully")
    }
}
