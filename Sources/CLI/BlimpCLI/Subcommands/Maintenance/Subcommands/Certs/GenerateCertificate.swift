import ArgumentParser
import BlimpKit
import Foundation
import ProvisioningAPI
import Cronista

struct GenerateCertificate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate-cert",
        abstract: "Generate and store a new certificate; --rotate revokes all previous of the type"
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

    @Flag(help: "Revoke all previous certificates of the type and prune their stored p12s (requires --push)")
    var rotate: Bool = false

    func validate() throws {
        if rotate && !push {
            throw ValidationError("--rotate requires --push: revocation makes the new certificate the only valid one, so its p12 must reach the shared storage")
        }
    }

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
            push: push,
            rotate: rotate
        )

        logger.info("Certificate created successfully")
        logger.info("  ID: \(cert.id)")
        logger.info("  Name: \(cert.name)")
    }
}
