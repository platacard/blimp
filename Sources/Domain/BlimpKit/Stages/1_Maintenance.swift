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
    /// - Certificate generation, revocation and storage
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

        public func listDevices(platform: ProvisioningAPI.Platform?, status: ProvisioningAPI.Device.Status? = nil) async throws -> [ProvisioningAPI.Device] {
            let devices = try await api.listDevices(platform: platform, status: status)
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
            let certGenerator = OpenSSLCertificateGenerator()

            let manager = CertificateManager(
                certificateService: api,
                git: git,
                certGenerator: certGenerator,
                passphrase: passphrase,
                push: push
            )

            return try await manager.createAndStoreCertificate(type: type, platform: platform)
        }

        /// Finds a valid certificate ID from storage that matches Apple Developer Portal.
        /// Does NOT require passphrase - only checks file existence.
        public func findCertificate(
            type: ProvisioningAPI.CertificateType,
            platform: ProvisioningAPI.Platform,
            storagePath: String
        ) async throws -> String? {
            let certs = try await findAllCertificates(type: type, platform: platform, storagePath: storagePath)
            return certs.first
        }

        /// Finds ALL valid certificate IDs from storage that match Apple Developer Portal.
        /// - Parameters:
        ///   - type: Certificate type
        ///   - platform: Target platform
        ///   - storagePath: Path to git storage
        ///   - filterNames: Optional list of certificate names to match (substring match). If nil, returns all.
        public func findAllCertificates(
            type: ProvisioningAPI.CertificateType,
            platform: ProvisioningAPI.Platform,
            storagePath: String,
            filterNames: [String]? = nil
        ) async throws -> [String] {
            let git = GitStorage(localPath: storagePath)
            try await git.cloneOrPull()

            let certDir = type.storageDirectory(for: platform)
            let appleCerts = try await api.listCertificates(filterType: type)

            logger.info("Found \(appleCerts.count) \(type.rawValue) certificates on Developer Portal")

            var validCertIds: [String] = []
            for cert in appleCerts {
                let p12Path = "\(certDir)/\(cert.id).p12"
                if await git.fileExists(path: p12Path) {
                    if let filterNames {
                        let matches = filterNames.contains { cert.name.localizedCaseInsensitiveContains($0) }
                        if matches {
                            logger.info("Found matching certificate \(cert.name) (\(cert.id))")
                            validCertIds.append(cert.id)
                        }
                    } else {
                        logger.info("Found valid certificate \(cert.name) (\(cert.id))")
                        validCertIds.append(cert.id)
                    }
                }
            }

            return validCertIds
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

        /// Installs provisioning profiles from Git storage to the system.
        public func installProfiles(
            platform: ProvisioningAPI.Platform,
            type: ProvisioningAPI.ProfileType,
            bundleIdPattern: String?,
            storagePath: String
        ) async throws -> [InstalledProfile] {
            let git = GitStorage(localPath: storagePath)
            let installer = ProfileInstaller(git: git)

            return try await installer.installProfiles(
                platform: platform,
                type: type,
                bundleIdPattern: bundleIdPattern
            )
        }

        /// Syncs provisioning profiles for the given bundle IDs.
        /// Automatically finds the appropriate certificate(s) from storage based on profile type.
        /// Does NOT create certificates - use `generateCertificate` first if needed.
        /// - Parameters:
        ///   - bundleIds: Tuples of (bundleId, profileName). bundleId is used for Apple API lookup, profileName for the stored filename.
        ///   - certificateNames: Optional filter for certificate names. If nil, uses all valid certificates.
        public func syncProfiles(
            platform: ProvisioningAPI.Platform,
            type: ProvisioningAPI.ProfileType,
            bundleIds: [(bundleId: String, profileName: String)],
            force: Bool,
            storagePath: String,
            push: Bool = false,
            certificateNames: [String]? = nil
        ) async throws {
            let certType = certificateType(for: type)
            logger.info("Profile type \(type.rawValue) requires \(certType.rawValue) certificate")

            let certificateIds = try await findAllCertificates(
                type: certType,
                platform: platform,
                storagePath: storagePath,
                filterNames: certificateNames
            )

            guard !certificateIds.isEmpty else {
                throw MaintenanceError.certificateNotFound(
                    """
                    No valid \(certType.rawValue) certificate found in storage for \(platform.rawValue).

                    Run this command first:
                      blimp maintenance generate-cert --type \(certType.rawValue) --platform \(platform.rawValue) --storage-path \(storagePath) --passphrase <passphrase>
                    """
                )
            }

            logger.info("Using \(certificateIds.count) certificate(s) for profile sync")

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
                certificateIds: certificateIds,
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

        // MARK: - Helpers

        /// Maps profile type to required certificate type.
        private func certificateType(for profileType: ProvisioningAPI.ProfileType) -> ProvisioningAPI.CertificateType {
            switch profileType {
            case .iosAppDevelopment, .tvosAppDevelopment, .macAppDevelopment, .macCatalystAppDevelopment:
                return .development
            case .iosAppStore, .iosAppAdhoc, .tvosAppStore, .tvosAppAdhoc, .macAppStore, .macCatalystAppStore:
                return .distribution
            default:
                return .distribution
            }
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
