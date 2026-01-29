import Foundation
import Cronista
import ProvisioningAPI
import Gito

/// Coordinator for syncing provisioning profiles with Git storage.
/// Handles profile creation, storage, and synchronization.
/// Certificate management is handled separately by CertificateManager.
public struct ProfileSyncCoordinator: Sendable {
    private let profileService: any ProfileService
    private let deviceService: any DeviceService
    private let git: any GitManaging
    private let push: Bool
    private nonisolated(unsafe) let logger = Cronista(module: "blimp", category: "ProfileSyncCoordinator")

    public init(
        profileService: any ProfileService,
        deviceService: any DeviceService,
        git: any GitManaging,
        push: Bool = false
    ) {
        self.profileService = profileService
        self.deviceService = deviceService
        self.git = git
        self.push = push
    }

    /// Syncs provisioning profiles for the given bundle IDs.
    /// - Parameters:
    ///   - platform: Target platform
    ///   - type: Profile type
    ///   - bundleIds: Bundle identifiers to sync
    ///   - certificateId: ID of the certificate to use (must exist in Apple Developer Portal)
    ///   - force: If true, regenerates profiles even if they exist
    public func sync(
        platform: ProvisioningAPI.Platform,
        type: ProvisioningAPI.ProfileType,
        bundleIds: [String],
        certificateId: String,
        force: Bool = false
    ) async throws {
        logger.info("Starting profile sync for \(platform.rawValue) \(type.rawValue)")
        logger.info("Bundle IDs: \(bundleIds.joined(separator: ", "))")
        logger.info("Using certificate: \(certificateId)")

        try await git.cloneOrPull()

        for bundleId in bundleIds {
            try await syncProfile(
                bundleId: bundleId,
                type: type,
                platform: platform,
                certificateId: certificateId,
                force: force
            )
        }

        logger.info("Profile sync completed successfully.")
    }

    private func syncProfile(
        bundleId: String,
        type: ProvisioningAPI.ProfileType,
        platform: ProvisioningAPI.Platform,
        certificateId: String,
        force: Bool
    ) async throws {
        let profileDir = "profiles/\(platform.rawValue)/\(type.rawValue)"
        let fileName = "\(bundleId).mobileprovision"
        let filePath = "\(profileDir)/\(fileName)"

        let fileExists = await git.fileExists(path: filePath)

        if !force && fileExists {
            logger.info("Profile \(bundleId) exists in storage, skipping.")
            return
        }

        let existingProfiles = try await profileService.listProfiles(name: bundleId)
        if let existing = existingProfiles.first {
            logger.info("Deleting existing profile \(bundleId) for regeneration")
            try await profileService.deleteProfile(id: existing.id)
        }

        let deviceIds = try await resolveDeviceIds(type: type, platform: platform)

        guard let bundleResourceId = try await profileService.getBundleId(identifier: bundleId) else {
            throw Error.missingData("Could not find Bundle ID resource for \(bundleId)")
        }

        let newProfile = try await profileService.createProfile(
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

        logger.info("Synced profile: \(bundleId)")
    }

    private func resolveDeviceIds(type: ProvisioningAPI.ProfileType, platform: ProvisioningAPI.Platform) async throws -> [String]? {
        guard requiresDevices(type: type) else {
            return nil
        }

        let devices = try await deviceService.listDevices(platform: platform)
        let enabledDevices = devices.filter { $0.status == .enabled }

        if enabledDevices.isEmpty {
            logger.warning("No enabled devices found for \(platform.rawValue). Profile creation may fail.")
        } else {
            logger.info("Found \(enabledDevices.count) enabled devices")
        }

        return enabledDevices.map { $0.id }
    }

    private func requiresDevices(type: ProvisioningAPI.ProfileType) -> Bool {
        switch type {
        case .iosAppDevelopment, .tvosAppDevelopment, .macAppDevelopment, .macCatalystAppDevelopment:
            return true
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
