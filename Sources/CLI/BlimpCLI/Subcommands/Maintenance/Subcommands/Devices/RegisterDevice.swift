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
        try await Blimp.Maintenance.default.registerDevice(name: name, udid: udid, platform: platform)
        logger.success("Device '\(name)' registered successfully")
    }
}
