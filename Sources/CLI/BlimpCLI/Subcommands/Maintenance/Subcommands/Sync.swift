import ArgumentParser
import BlimpKit
import Foundation
import ProvisioningAPI

struct Sync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync provisioning profiles with storage"
    )

    @Option(
        name: .shortAndLong,
        parsing: .upToNextOption,
        help: "Bundle IDs to sync"
    )
    var bundleIds: [String]

    @Option(help: "Platform: ios, macos, tvos, catalyst")
    var platform: ProvisioningAPI.Platform = .ios

    @Option(help: "Profile type: development, appstore, adhoc, inhouse, direct")
    var type: CLIProfileType = .development

    @Flag(help: "Force regeneration of profiles")
    var force: Bool = false

    @Option(help: "Storage path")
    var storagePath: String = "."

    @Option(help: "Passphrase (or set BLIMP_PASSPHRASE, or enter interactively)")
    var passphrase: String?

    @Flag(help: "Push to remote after committing")
    var push: Bool = false

    func run() async throws {
        let passphrase = try resolvePassphrase(passphrase)
        let resolvedPath = storagePath == "." ? FileManager.default.currentDirectoryPath : storagePath

        try await Blimp.Maintenance.default.sync(
            platform: platform,
            type: type.asAPI(platform: platform),
            bundleIds: bundleIds,
            force: force,
            storagePath: resolvedPath,
            passphrase: passphrase,
            push: push
        )
        print("Sync completed successfully")
    }
}
