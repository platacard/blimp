import ArgumentParser
import BlimpKit
import Foundation
import ProvisioningAPI
import Cronista

struct GenerateCertificate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate-cert",
        abstract: "Rotate the certificate of a type: generate a new one, revoke all previous of that type"
    )

    @Option(help: "Certificate type: development, distribution")
    var type: ProvisioningAPI.CertificateType = .development

    @Option(help: "Platform: ios, macos, tvos, catalyst")
    var platform: ProvisioningAPI.Platform = .ios

    @Option(help: "Storage path")
    var storagePath: String = "."

    @Option(help: "Certificate password (or set \(SecretEnvKey.certificatesPassword), or enter interactively)")
    var passphrase: String?

    @Flag(help: "Push to remote after committing")
    var push: Bool = false

    func run() async throws {
        let logger = Cronista(module: "blimp", category: "Maintenance")
        let passphrase = try resolveSecret(
            cliValue: passphrase,
            environmentKey: SecretEnvKey.certificatesPassword,
            prompt: "Enter passphrase: "
        )
        let resolvedPath = storagePath == "." ? FileManager.default.currentDirectoryPath : storagePath

        let cert = try await Blimp.Maintenance.default.generateCertificate(
            type: type,
            platform: platform,
            storagePath: resolvedPath,
            passphrase: passphrase,
            push: push
        )

        logger.info("Certificate created successfully")
        logger.info("  ID: \(cert.id)")
        logger.info("  Name: \(cert.name)")
    }
}
