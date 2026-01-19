import Foundation
import ProvisioningAPI
import JWTProvider
import Cronista
import Gito

public extension Blimp {
    /// Maintenance stage:
    /// - Managing the provisioning profiles and certificates
    /// - Other checks and services
    struct Maintenance: Sendable {
        private let api: ProvisioningAPI

        nonisolated(unsafe) private let logger: Cronista

        public init(jwtProvider: any JWTProviding) {
            self.api = ProvisioningAPI(jwtProvider: jwtProvider)
            self.logger = Cronista(module: "blimp", category: "Maintenance")
        }
        
        public func registerDevice(name: String, udid: String, platform: ProvisioningAPI.Platform) async throws {
            let device = try await api.registerDevice(name: name, udid: udid, platform: platform)
            logger.info("Registered device: \(device.name) (\(device.id))")
        }
        
        public func sync(
            platform: ProvisioningAPI.Platform,
            type: ProvisioningAPI.ProfileType,
            bundleIds: [String],
            force: Bool,
            storagePath: String,
            passphrase: String,
            push: Bool = false
        ) async throws {
            let git = GitStorage(localPath: storagePath)
            let encrypter = FileEncrypter()
            let certGenerator = OpenSSLCertificateGenerator()

            let coordinator = ProvisioningCoordinator(
                api: api,
                git: git,
                encrypter: encrypter,
                certGenerator: certGenerator,
                passphrase: passphrase,
                push: push
            )
            try await coordinator.sync(platform: platform, type: type, bundleIds: bundleIds, force: force)
        }

        public func generateCertificate(
            type: ProvisioningAPI.CertificateType,
            platform: ProvisioningAPI.Platform,
            storagePath: String,
            passphrase: String
        ) async throws -> ProvisioningAPI.Certificate {
            let git = GitStorage(localPath: storagePath)
            let encrypter = FileEncrypter()
            let certGenerator = OpenSSLCertificateGenerator()

            try await git.cloneOrPull()

            // Generate CSR and private key
            let (csr, privateKey) = try certGenerator.generateCSR()

            // Create certificate in Apple Developer Portal
            let cert = try await api.createCertificate(csrContent: csr, type: type)
            guard let certContent = cert.content else {
                throw MaintenanceError.missingData("Certificate created but no content returned")
            }

            // Generate P12 from certificate and private key (includes passphrase protection)
            let p12 = try certGenerator.generateP12(certContent: certContent, privateKey: privateKey, passphrase: passphrase)

            // Store encrypted P12 in git
            let certDir = "certificates/\(platform.rawValue)/\(type.rawValue)"
            let p12Path = "\(certDir)/\(cert.id).p12"

            let encryptedP12 = try encrypter.encrypt(data: p12, password: passphrase)

            try await git.writeFile(path: p12Path, content: encryptedP12)

            logger.info("Created and stored certificate: \(cert.id)")
            return cert
        }

        /// Initialize local-only storage (can add remote later)
        public func initializeLocalStorage(path: String, branch: String = "main") async throws {
            let repo = GitStorage(localPath: path, branch: branch)
            try await repo.cloneOrPull()
            logger.info("Local hangar initialized at \(path)")
        }

        /// Add or update remote for existing local storage
        public func setStorageRemote(path: String, remoteURL: String) async throws {
            let repo = GitStorage(localPath: path)
            try await repo.setRemote(url: remoteURL)
            logger.info("Remote set to \(remoteURL)")
        }

        // MARK: - Device Management

        public func listDevices(platform: ProvisioningAPI.Platform?) async throws -> [ProvisioningAPI.Device] {
            let devices = try await api.listDevices(platform: platform)
            logger.info("Found \(devices.count) devices in the hangar")
            return devices
        }

        // MARK: - Certificate Management

        public func listCertificates(type: ProvisioningAPI.CertificateType?) async throws -> [ProvisioningAPI.Certificate] {
            let certs = try await api.listCertificates(filterType: type)
            logger.info("Found \(certs.count) certificates")
            return certs
        }

        public func revokeCertificate(id: String) async throws {
            try await api.deleteCertificate(id: id)
            logger.info("Revoked certificate: \(id)")
        }

        // MARK: - Profile Management

        public func listProfiles(name: String?) async throws -> [ProvisioningAPI.Profile] {
            let profiles = try await api.listProfiles(name: name)
            logger.info("Found \(profiles.count) profiles")
            return profiles
        }

        public func removeProfile(id: String) async throws {
            try await api.deleteProfile(id: id)
            logger.info("Removed profile: \(id)")
        }

        public enum MaintenanceError: Error, LocalizedError {
            case missingData(String)

            public var errorDescription: String? {
                switch self {
                case .missingData(let msg): return msg
                }
            }
        }
    }
}
