import ArgumentParser
import BlimpKit
import Foundation
import Cronista
import ProvisioningAPI

struct InstallProfiles: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-profiles",
        abstract: "Install provisioning profiles from storage to the system"
    )

    @Option(help: "Platform: ios, macos, tvos, catalyst")
    var platform: ProvisioningAPI.Platform = .ios

    @Option(help: "Profile type: development, appstore, adhoc")
    var type: CLIProfileType = .development

    @Option(help: "Bundle ID filter pattern (e.g., 'com.example.*')")
    var bundleId: String?

    @Option(help: "Storage path")
    var storagePath: String = "."

    func run() async throws {
        let logger = Cronista(module: "blimp", category: "Maintenance")
        let resolvedPath = storagePath == "." ? FileManager.default.currentDirectoryPath : storagePath

        let installed = try await Blimp.Maintenance.default.installProfiles(
            platform: platform,
            type: type.asAPI(platform: platform),
            bundleIdPattern: bundleId,
            storagePath: resolvedPath
        )

        if installed.isEmpty {
            logger.info("No profiles found to install")
        } else {
            logger.success("Installed \(installed.count) profile(s):")
            for profile in installed {
                logger.info("  \(profile.bundleId) -> \(profile.uuid)")
            }
        }
    }
}
