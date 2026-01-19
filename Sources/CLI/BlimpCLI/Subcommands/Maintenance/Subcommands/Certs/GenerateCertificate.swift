import ArgumentParser
import BlimpKit
import Foundation
import ProvisioningAPI

struct GenerateCertificate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate-cert",
        abstract: "Generate and store a new certificate"
    )

    @Option(help: "Certificate type: development, distribution")
    var type: ProvisioningAPI.CertificateType = .development

    @Option(help: "Platform: ios, macos, tvos, catalyst")
    var platform: ProvisioningAPI.Platform = .ios

    @Option(help: "Storage path")
    var storagePath: String = "."

    @Option(help: "Passphrase (or set BLIMP_PASSPHRASE, or enter interactively)")
    var passphrase: String?

    func run() async throws {
        let passphrase = try resolvePassphrase(passphrase)
        let resolvedPath = storagePath == "." ? FileManager.default.currentDirectoryPath : storagePath

        let cert = try await Blimp.Maintenance.default.generateCertificate(
            type: type,
            platform: platform,
            storagePath: resolvedPath,
            passphrase: passphrase
        )

        print("Certificate created successfully")
        print("  ID: \(cert.id)")
        print("  Name: \(cert.name)")
    }
}
