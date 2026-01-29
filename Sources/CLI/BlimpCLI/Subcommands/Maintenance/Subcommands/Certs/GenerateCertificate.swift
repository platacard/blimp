import ArgumentParser
import BlimpKit
import Foundation
import ProvisioningAPI
import Cronista

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
        let logger = Cronista(module: "blimp", category: "Maintenance")
        let passphrase = try resolvePassphrase(passphrase)
        let resolvedPath = storagePath == "." ? FileManager.default.currentDirectoryPath : storagePath

        let cert = try await Blimp.Maintenance.default.generateCertificate(
            type: type,
            platform: platform,
            storagePath: resolvedPath,
            passphrase: passphrase
        )

        logger.info("Certificate created successfully")
        logger.info("  ID: \(cert.id)")
        logger.info("  Name: \(cert.name)")
    }
}

// MARK: - Passphrase interactive input

private func resolvePassphrase(_ cliValue: String?) throws -> String {
    // Environment variable first (CI-friendly)
    if let value = ProcessInfo.processInfo.environment["BLIMP_PASSPHRASE"] { return value }
    if let value = cliValue { return value }

    // Interactive fallback
    print("Enter passphrase: ", terminator: "")
    guard let pass = readSecureInput() else {
        throw ValidationError("Failed to read passphrase")
    }
    return pass
}

private func readSecureInput() -> String? {
    var oldTermios = termios()
    tcgetattr(STDIN_FILENO, &oldTermios)

    var newTermios = oldTermios
    newTermios.c_lflag &= ~UInt(ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

    let result = readLine()

    tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
    print()

    return result
}
