import ArgumentParser
import BlimpKit
import Foundation
import ProvisioningAPI
import Cronista

struct InstallCertificates: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-certs",
        abstract: "Install certificates from storage into the macOS keychain"
    )

    @Option(help: "Certificate type: development, distribution")
    var type: ProvisioningAPI.CertificateType = .development

    @Option(help: "Platform: ios, macos, tvos, catalyst")
    var platform: ProvisioningAPI.Platform = .ios

    @Option(help: "Storage path")
    var storagePath: String = "."

    @Option(help: "Keychain path (defaults to login keychain)")
    var keychain: String?

    @Option(help: "Keychain password for codesign access without UI prompts (or set \(SecretEnvKey.keychainPassword))")
    var keychainPassword: String?

    @Option(help: "Certificate password (or set \(SecretEnvKey.certificatesPassword), or enter interactively)")
    var passphrase: String?

    @Flag(help: "Skip installing the Apple WWDR intermediate certificate")
    var skipWwdr = false

    func run() async throws {
        let logger = Cronista(module: "blimp", category: "Maintenance")
        let passphrase = try resolveSecret(
            cliValue: passphrase,
            environmentKey: SecretEnvKey.certificatesPassword,
            prompt: "Enter passphrase: "
        )
        let keychainPassword = self.keychainPassword ?? ProcessInfo.processInfo.environment[SecretEnvKey.keychainPassword]
        let resolvedPath = storagePath == "." ? FileManager.default.currentDirectoryPath : storagePath

        let installer = CertificateInstaller(storagePath: resolvedPath)

        let installed = try await installer.installCertificates(
            platform: platform,
            type: type,
            passphrase: passphrase,
            keychain: keychain.map { .path($0) } ?? .login,
            keychainPassword: keychainPassword,
            installWWDR: !skipWwdr
        )

        logger.success("Installed \(installed.count) certificate(s):")
        for cert in installed {
            logger.info("  \(cert.certificateId) -> \(cert.keychainPath)")
        }
    }
}
