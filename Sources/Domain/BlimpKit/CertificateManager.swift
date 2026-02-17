import Foundation
import Cronista
import ProvisioningAPI
import Gito

/// Manager for certificate operations with Git storage.
/// Handles certificate creation, storage, and lookup.
public struct CertificateManager: Sendable {
    private let certificateService: any CertificateService
    private let git: any GitManaging
    private let encrypter: any EncryptionService
    private let certGenerator: any CertificateGenerating
    private let passphrase: String
    private let push: Bool
    private nonisolated(unsafe) let logger = Cronista(module: "blimp", category: "CertificateManager")

    public init(
        certificateService: any CertificateService,
        git: any GitManaging,
        encrypter: any EncryptionService,
        certGenerator: any CertificateGenerating,
        passphrase: String,
        push: Bool = false
    ) {
        self.certificateService = certificateService
        self.git = git
        self.encrypter = encrypter
        self.certGenerator = certGenerator
        self.passphrase = passphrase
        self.push = push
    }

    /// Finds a valid certificate ID from storage that matches one in Apple Developer Portal.
    /// - Parameters:
    ///   - type: Certificate type to look for
    ///   - platform: Target platform
    /// - Returns: Certificate ID if found, nil otherwise
    public func findValidCertificate(
        type: ProvisioningAPI.CertificateType,
        platform: ProvisioningAPI.Platform
    ) async throws -> String? {
        try await git.cloneOrPull()

        let certDir = type.storageDirectory(for: platform)
        let appleCerts = try await certificateService.listCertificates(filterType: type)

        logger.info("Found \(appleCerts.count) certificates of type \(type.rawValue) on Developer Portal")

        for cert in appleCerts {
            let p12Path = "\(certDir)/\(cert.id).p12"

            if await git.fileExists(path: p12Path) {
                logger.info("Found valid certificate \(cert.id) in storage")
                return cert.id
            }
        }

        return nil
    }

    /// Creates a new certificate and stores it encrypted in Git.
    /// - Parameters:
    ///   - type: Certificate type to create
    ///   - platform: Target platform
    /// - Returns: The created certificate
    public func createAndStoreCertificate(
        type: ProvisioningAPI.CertificateType,
        platform: ProvisioningAPI.Platform
    ) async throws -> ProvisioningAPI.Certificate {
        try await git.cloneOrPull()

        let certDir = type.storageDirectory(for: platform)

        let (csr, privateKey) = try certGenerator.generateCSR()

        let cert = try await certificateService.createCertificate(csrContent: csr, type: type)
        guard let certContent = cert.content else {
            throw Error.missingData("Certificate created but no content returned")
        }

        let p12 = try certGenerator.generateP12(certContent: certContent, privateKey: privateKey, passphrase: passphrase)
        let encryptedP12 = try encrypter.encrypt(data: p12, password: passphrase)

        let p12Path = "\(certDir)/\(cert.id).p12"
        try await git.writeFile(path: p12Path, content: encryptedP12)
        try await git.commitAndPush(message: "Add certificate \(cert.id) for \(platform.rawValue) \(type.rawValue)", push: push)

        logger.info("Created and stored certificate: \(cert.id)")
        return cert
    }

    /// Finds an existing valid certificate or creates a new one.
    /// - Parameters:
    ///   - type: Certificate type
    ///   - platform: Target platform
    /// - Returns: Certificate ID (existing or newly created)
    public func ensureCertificate(
        type: ProvisioningAPI.CertificateType,
        platform: ProvisioningAPI.Platform
    ) async throws -> String {
        if let existingId = try await findValidCertificate(type: type, platform: platform) {
            return existingId
        }

        logger.info("No valid certificate found in storage. Creating new one...")
        let cert = try await createAndStoreCertificate(type: type, platform: platform)
        return cert.id
    }

    public enum Error: Swift.Error, LocalizedError {
        case missingData(String)

        public var errorDescription: String? {
            switch self {
            case .missingData(let msg): return msg
            }
        }
    }
}
