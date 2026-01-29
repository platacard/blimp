import Foundation
import ProvisioningAPI
import JWTProvider
import Cronista
import Gito

public extension Blimp {
    /// Maintenance stage
    ///
    /// Provides:
    /// - Device registration and listing
    /// - Certificate generation, revocation and encrypted storage
    /// - Provisioning profile synchronization, listing, and removal
    struct Maintenance: Sendable {
        private let api: ProvisioningAPI

        nonisolated(unsafe) private let logger: Cronista

        public init(jwtProvider: any JWTProviding) {
            self.api = ProvisioningAPI(jwtProvider: jwtProvider)
            self.logger = Cronista(module: "blimp", category: "Maintenance")
        }

        // MARK: - Device Management

        public func registerDevice(name: String, udid: String, platform: ProvisioningAPI.Platform) async throws {
            let device = try await api.registerDevice(name: name, udid: udid, platform: platform)
            logger.info("Registered device: \(device.name) (\(device.id))")
        }

        public func listDevices(platform: ProvisioningAPI.Platform?) async throws -> [ProvisioningAPI.Device] {
            let devices = try await api.listDevices(platform: platform)
            logger.info("Found \(devices.count) devices")
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

        public func generateCertificate(
            type: ProvisioningAPI.CertificateType,
            platform: ProvisioningAPI.Platform,
            storagePath: String,
            passphrase: String,
            push: Bool = false
        ) async throws -> ProvisioningAPI.Certificate {
            let git = GitStorage(localPath: storagePath)
            let encrypter = FileEncrypter()
            let certGenerator = OpenSSLCertificateGenerator()

            let manager = CertificateManager(
                certificateService: api,
                git: git,
                encrypter: encrypter,
                certGenerator: certGenerator,
                passphrase: passphrase,
                push: push
            )

            return try await manager.createAndStoreCertificate(type: type, platform: platform)
        }

        /// Finds a valid certificate ID from storage that matches Apple Developer Portal.
        public func findCertificate(
            type: ProvisioningAPI.CertificateType,
            platform: ProvisioningAPI.Platform,
            storagePath: String,
            passphrase: String
        ) async throws -> String? {
            let git = GitStorage(localPath: storagePath)
            let encrypter = FileEncrypter()
            let certGenerator = OpenSSLCertificateGenerator()

            let manager = CertificateManager(
                certificateService: api,
                git: git,
                encrypter: encrypter,
                certGenerator: certGenerator,
                passphrase: passphrase
            )

            return try await manager.findValidCertificate(type: type, platform: platform)
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

        /// Syncs provisioning profiles for the given bundle IDs.
        /// Only updates profiles, does NOT create certificates.
        public func syncProfiles(
            platform: ProvisioningAPI.Platform,
            type: ProvisioningAPI.ProfileType,
            bundleIds: [String],
            certificateId: String,
            force: Bool,
            storagePath: String,
            push: Bool = false
        ) async throws {
            let git = GitStorage(localPath: storagePath)

            let coordinator = ProfileSyncCoordinator(
                profileService: api,
                deviceService: api,
                git: git,
                push: push
            )

            try await coordinator.sync(
                platform: platform,
                type: type,
                bundleIds: bundleIds,
                certificateId: certificateId,
                force: force
            )
        }

        // MARK: - Storage Management

        public func initializeLocalStorage(path: String, branch: String = "main") async throws {
            let repo = GitStorage(localPath: path, branch: branch)
            try await repo.cloneOrPull()
            logger.info("Local storage initialized at \(path)")
        }

        public func setStorageRemote(path: String, remoteURL: String) async throws {
            let repo = GitStorage(localPath: path)
            try await repo.setRemote(url: remoteURL)
            logger.info("Remote set to \(remoteURL)")
        }

        public enum MaintenanceError: Error, LocalizedError {
            case missingData(String)
            case certificateNotFound(String)

            public var errorDescription: String? {
                switch self {
                case .missingData(let msg): return msg
                case .certificateNotFound(let msg): return msg
                }
            }
        }
    }
}
