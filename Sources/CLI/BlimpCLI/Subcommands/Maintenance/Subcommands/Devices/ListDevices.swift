import ArgumentParser
import BlimpKit
import Cronista
import ProvisioningAPI

struct ListDevices: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-devices",
        abstract: "List devices in Apple Developer Portal"
    )

    @Option(help: "Filter by platform: ios, macos, tvos, catalyst")
    var platform: ProvisioningAPI.Platform?

    func run() async throws {
        let logger = Cronista(module: "blimp", category: "Maintenance")
        let devices = try await Blimp.Maintenance.default.listDevices(platform: platform)

        if devices.isEmpty {
            logger.info("No devices found")
        } else {
            logger.info("Devices:")
            for device in devices {
                let status = device.status == .enabled ? "✓" : "✗"
                let platformStr = device.platform?.rawValue ?? "unknown"
                logger.info("  \(status) \(device.name) (\(platformStr))")
                logger.info("    ID: \(device.id)")
                logger.info("    UDID: \(device.udid)")
            }
        }
    }
}
