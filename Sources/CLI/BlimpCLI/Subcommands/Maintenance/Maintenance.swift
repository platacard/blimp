import Foundation
import ArgumentParser

struct Maintenance: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "maintenance",
        abstract: "Manage provisioning profiles, certificates, and devices",
        subcommands: [
            Init.self,
            SetRemote.self,
            RegisterDevice.self,
            ListDevices.self,
            ListCertificates.self,
            GenerateCertificate.self,
            RevokeCertificate.self,
            ListProfiles.self,
            Sync.self,
            RemoveProfile.self
        ]
    )
}
