import Foundation
import Cronista
import Corredor
import ProvisioningAPI
import Gito

/// The main coordinator for syncing certificates and profiles with Git,
/// ensuring they exist in Apple Developer Portal, and downloading them.
public struct ProvisioningCoordinator: Sendable {
    private let api: any ProvisioningService
    private let git: any GitManaging
    private let encrypter: any EncryptionService
    private let certGenerator: any CertificateGenerating
    private let passphrase: String
    private let push: Bool
    private nonisolated(unsafe) let logger = Cronista(module: "blimp", category: "ProvisioningCoordinator")

    public init(
        api: any ProvisioningService,
        git: any GitManaging,
        encrypter: any EncryptionService,
        certGenerator: any CertificateGenerating,
        passphrase: String,
        push: Bool = false
    ) {
        self.api = api
        self.git = git
        self.encrypter = encrypter
        self.certGenerator = certGenerator
        self.passphrase = passphrase
        self.push = push
    }

    public func sync(platform: ProvisioningAPI.Platform, type: ProvisioningAPI.ProfileType, bundleIds: [String], force: Bool = false) async throws {
        logger.info("Starting sync for \(platform.rawValue) \(type.rawValue) \(bundleIds)")

        // 1. Pull git repo
        try await git.cloneOrPull()

        // 2. Ensure valid certificate exists
        let certType = certTypeFor(profileType: type)
        let validCertId = try await ensureCertificate(type: certType, platform: platform)

        // 3. Ensure profiles exist for all bundle IDs
        for bundleId in bundleIds {
            try await ensureProfile(
                bundleId: bundleId,
                type: type,
                platform: platform,
                certificateId: validCertId,
                force: force
            )
        }

        logger.info("Sync completed successfully.")
    }

    private func ensureCertificate(type: ProvisioningAPI.CertificateType, platform: ProvisioningAPI.Platform) async throws -> String {
        let certDir = "certificates/\(platform.rawValue)/\(type.rawValue)"

        let appleCerts = try await api.listCertificates(filterType: type)
        logger.info("Found \(appleCerts.count) certificates of type \(type.rawValue) on Developer Portal")

        for cert in appleCerts {
            let p12Path = "\(certDir)/\(cert.id).p12"

            if await git.fileExists(path: p12Path) {
                logger.info("Found valid certificate \(cert.id) in storage")
                return cert.id
            }
        }

        logger.info("No valid certificate found in storage matching Apple Developer Portal. Creating new one...")
        return try await createAndStoreCertificate(type: type, platform: platform, dir: certDir)
    }

    private func createAndStoreCertificate(type: ProvisioningAPI.CertificateType, platform: ProvisioningAPI.Platform, dir: String) async throws -> String {
        let (csr, privateKey) = try certGenerator.generateCSR()

        let cert = try await api.createCertificate(csrContent: csr, type: type)
        guard let certContent = cert.content else {
            throw Error.missingData("Certificate created but no content returned")
        }

        let p12Path = "\(dir)/\(cert.id).p12"
        let p12 = try certGenerator.generateP12(certContent: certContent, privateKey: privateKey, passphrase: passphrase)
        let encryptedP12 = try encrypter.encrypt(data: p12, password: passphrase)

        try await git.writeFile(path: p12Path, content: encryptedP12)
        try await git.commitAndPush(message: "Add new certificate \(cert.id) for \(platform.rawValue) \(type.rawValue)", push: push)

        return cert.id
    }

    private func ensureProfile(bundleId: String, type: ProvisioningAPI.ProfileType, platform: ProvisioningAPI.Platform, certificateId: String, force: Bool) async throws {
        let profileDir = "profiles/\(platform.rawValue)/\(type.rawValue)"
        let fileName = "\(bundleId).mobileprovision"
        let filePath = "\(profileDir)/\(fileName)"

        let fileExists = await git.fileExists(path: filePath)

        if !force && fileExists {
            logger.info("Profile \(bundleId) exists in storage.")
            return
        }

        let profiles = try await api.listProfiles(name: bundleId)
        if let existing = profiles.first {
            logger.info("Deleting existing profile \(bundleId) for regeneration")
            try await api.deleteProfile(id: existing.id)
        }

        let deviceIds: [String]?
        if isDevelopment(type: type) || isAdHoc(type: type) {
            let devices = try await api.listDevices(platform: platform)
            let enabledDevices = devices.filter { $0.status == .enabled }
            if enabledDevices.isEmpty {
                logger.warning("No enabled devices found for \(platform.rawValue). Development/AdHoc profile may fail.")
            }
            deviceIds = enabledDevices.map { $0.id }
            logger.info("Found \(enabledDevices.count) enabled devices for profile")
        } else {
            deviceIds = nil
        }

        guard let bundleResourceId = try await api.getBundleId(identifier: bundleId) else {
            throw Error.missingData("Could not find Bundle ID resource for \(bundleId)")
        }

        let newProfile = try await api.createProfile(
            name: bundleId,
            type: type,
            bundleId: bundleResourceId,
            certificateIds: [certificateId],
            deviceIds: deviceIds
        )

        guard let content = newProfile.content else {
            throw Error.missingData("Profile created but no content returned")
        }

        try await git.writeFile(path: filePath, content: content)
        try await git.commitAndPush(message: "Update profile \(bundleId)", push: push)
    }

    private func certTypeFor(profileType: ProvisioningAPI.ProfileType) -> ProvisioningAPI.CertificateType {
        switch profileType {
        case .iosAppDevelopment, .tvosAppDevelopment, .macAppDevelopment, .macCatalystAppDevelopment:
            return .development
        case .iosAppStore, .tvosAppStore, .macAppStore, .macCatalystAppStore:
            return .distribution
        case .iosAppAdhoc, .tvosAppAdhoc:
            return .distribution
        default:
            return .distribution
        }
    }

    private func isDevelopment(type: ProvisioningAPI.ProfileType) -> Bool {
        switch type {
        case .iosAppDevelopment, .tvosAppDevelopment, .macAppDevelopment, .macCatalystAppDevelopment:
            return true
        default:
            return false
        }
    }

    private func isAdHoc(type: ProvisioningAPI.ProfileType) -> Bool {
        switch type {
        case .iosAppAdhoc, .tvosAppAdhoc:
            return true
        default:
            return false
        }
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
