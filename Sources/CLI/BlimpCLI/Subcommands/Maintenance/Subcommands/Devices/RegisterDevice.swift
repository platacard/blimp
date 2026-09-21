import ArgumentParser
import BlimpKit
import Cronista
import ProvisioningAPI

struct RegisterDevice: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "register-device",
        abstract: "Register a new device in Apple Developer Portal"
    )

    @Argument(help: "The device UDID")
    var udid: String

    @Argument(help: "The device name")
    var name: String

    @Option(help: "Platform: ios, macos, tvos, catalyst")
    var platform: ProvisioningAPI.Platform = .ios

    func run() async throws {
        let logger = Cronista(module: "blimp", category: "Maintenance")
        let registration = try await Blimp.Maintenance.default.registerDevice(name: name, udid: udid, platform: platform)
        switch registration {
        case .registered(let device) where device.status == .processing:
            logger.success("Device '\(name)' registered, Apple is still processing it. Provisioning profiles can include it once processing completes.")
        case .registered:
            logger.success("Device '\(name)' registered successfully")
        case .alreadyRegistered(let device):
            logger.warning("Device '\(device.name)' (\(device.udid)) is already registered, status: \(device.status). Update dev provisioning profiles: blimp maintenance sync-profiles --type development")
        }
    }
}
