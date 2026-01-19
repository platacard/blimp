import ArgumentParser
import BlimpKit
import ProvisioningAPI

struct ListDevices: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-devices",
        abstract: "List devices in Apple Developer Portal"
    )

    @Option(help: "Filter by platform: ios, macos, tvos, catalyst")
    var platform: ProvisioningAPI.Platform?

    func run() async throws {
        let devices = try await Blimp.Maintenance.default.listDevices(platform: platform)

        if devices.isEmpty {
            print("No devices found")
        } else {
            print("Devices:")
            for device in devices {
                let status = device.status == .enabled ? "✓" : "✗"
                let platformStr = device.platform?.displayName ?? "unknown"
                print("  \(status) \(device.name) (\(platformStr))")
                print("    ID: \(device.id)")
                print("    UDID: \(device.udid)")
            }
        }
    }
}
