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
        help: "Bundle IDs to sync"
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

        try await Blimp.Maintenance.default.syncProfiles(
            platform: platform,
            type: type.asAPI(platform: platform),
            bundleIds: bundleIds,
            force: force,
            storagePath: resolvedPath,
            push: push,
            certificateNames: certificateNames
        )

        logger.success("Profile sync completed successfully")
    }
}
