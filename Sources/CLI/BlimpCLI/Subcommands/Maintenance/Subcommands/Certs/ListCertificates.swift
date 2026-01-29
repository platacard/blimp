import ArgumentParser
import BlimpKit
import Cronista
import ProvisioningAPI

struct ListCertificates: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-certs",
        abstract: "List certificates in Apple Developer Portal"
    )

    @Option(help: "Filter by type: development, distribution")
    var type: ProvisioningAPI.CertificateType?

    func run() async throws {
        let logger = Cronista(module: "blimp", category: "Maintenance")
        let certs = try await Blimp.Maintenance.default.listCertificates(type: type)

        if certs.isEmpty {
            logger.info("No certificates found")
        } else {
            logger.info("Certificates:")
            for cert in certs {
                let typeStr = cert.type?.rawValue ?? "unknown"
                logger.info("  \(cert.name) (\(typeStr))")
                logger.info("    ID: \(cert.id)")
                if let serial = cert.serialNumber {
                    logger.info("    Serial: \(serial)")
                }
            }
        }
    }
}
