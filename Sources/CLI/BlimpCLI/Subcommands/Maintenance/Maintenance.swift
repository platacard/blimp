import Foundation
import ArgumentParser

struct Maintenance: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "maintenance",
        abstract: "Manage provisioning profiles, certificates, and devices",
        subcommands: [
            // Storage
            Init.self,
            SetRemote.self,
            // Devices
            RegisterDevice.self,
            ListDevices.self,
            // Certificates
            ListCertificates.self,
            GenerateCertificate.self,
            RevokeCertificate.self,
            // Profiles
            ListProfiles.self,
            SyncProfiles.self,
            InstallProfiles.self,
            RemoveProfile.self
        ]
    )
}
