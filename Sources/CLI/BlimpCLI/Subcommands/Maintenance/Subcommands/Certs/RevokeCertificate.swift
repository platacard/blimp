import ArgumentParser
import BlimpKit

struct RevokeCertificate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "revoke-cert",
        abstract: "Revoke a certificate from Apple Developer Portal"
    )

    @Argument(help: "Certificate name to revoke")
    var name: String

    func run() async throws {
        let certs = try await Blimp.Maintenance.default.listCertificates(type: nil)
        guard let cert = certs.first(where: { $0.name == name }) else {
            throw ValidationError("Certificate '\(name)' not found")
        }

        try await Blimp.Maintenance.default.revokeCertificate(id: cert.id)
        print("Certificate '\(name)' revoked successfully")
    }
}
