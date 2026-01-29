import ArgumentParser
import BlimpKit
import Cronista

struct RevokeCertificate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "revoke-cert",
        abstract: "Revoke a certificate from Apple Developer Portal"
    )

    @Argument(help: "Certificate name to revoke")
    var name: String

    func run() async throws {
        let logger = Cronista(module: "blimp", category: "Maintenance")
        let certs = try await Blimp.Maintenance.default.listCertificates(type: nil)
        guard let cert = certs.first(where: { $0.name == name }) else {
            throw ValidationError("Certificate '\(name)' not found")
        }

        try await Blimp.Maintenance.default.revokeCertificate(id: cert.id)
        logger.success("Certificate '\(name)' revoked successfully")
    }
}
