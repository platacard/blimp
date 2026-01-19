import ArgumentParser
import BlimpKit
import ProvisioningAPI

struct ListCertificates: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-certs",
        abstract: "List certificates in Apple Developer Portal"
    )

    @Option(help: "Filter by type: development, distribution")
    var type: ProvisioningAPI.CertificateType?

    func run() async throws {
        let certs = try await Blimp.Maintenance.default.listCertificates(type: type)

        if certs.isEmpty {
            print("No certificates found")
        } else {
            print("Certificates:")
            for cert in certs {
                let typeStr = cert.type?.rawValue ?? "unknown"
                print("  \(cert.name) (\(typeStr))")
                print("    ID: \(cert.id)")
                if let serial = cert.serialNumber {
                    print("    Serial: \(serial)")
                }
            }
        }
    }
}
