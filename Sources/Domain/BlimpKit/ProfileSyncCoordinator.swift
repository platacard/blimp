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
    /// Bundle IDs, devices and existing portal profiles of every entry to sync are looked up
    /// before the first portal profile is deleted, so a failed lookup leaves the portal untouched.
    /// Development and ad hoc profiles need at least one enabled device.
    /// - Parameters:
    ///   - platform: Target platform
    ///   - type: Profile type
    ///   - bundleIds: Tuples of (bundleId, profileName). bundleId is used for Apple API lookup, profileName for the stored filename.
    ///   - certificateIds: IDs of certificates to include (must exist in Apple Developer Portal)
    ///   - force: If true, regenerates profiles even if they exist
    public func sync(
        platform: ProvisioningAPI.Platform,
        type: ProvisioningAPI.ProfileType,
        bundleIds: [(bundleId: String, profileName: String)],
        certificateIds: [String],
        force: Bool = false
    ) async throws {
        if let duplicate = firstDuplicateProfileName(in: bundleIds) {
            throw Error.duplicateProfileName(duplicate)
        }

        logger.info("Starting profile sync for \(platform.rawValue) \(type.rawValue)")
        logger.info("Bundle IDs: \(bundleIds.map(\.bundleId).joined(separator: ", "))")
        logger.info("Using \(certificateIds.count) certificate(s): \(certificateIds.joined(separator: ", "))")

        try await git.cloneOrPull()

        let pending = try await resolvePendingProfiles(bundleIds: bundleIds, type: type, platform: platform, force: force)
        let deviceIds = pending.isEmpty ? nil : try await resolveDeviceIds(type: type, platform: platform)

        var synced: [String] = []
        for profile in pending {
            do {
                try await replace(profile, type: type, certificateIds: certificateIds, deviceIds: deviceIds)
            } catch {
                await commitBeforeFailing(synced, type: type)
                throw error
            }
            synced.append(profile.name)
        }

        try await commit(synced, type: type)

        logger.info("Profile sync completed successfully.")
    }

    public enum Error: Swift.Error, LocalizedError {
        case missingData(String)
        case duplicateProfileName(String)
        case noDevices(platform: ProvisioningAPI.Platform, type: ProvisioningAPI.ProfileType)
        case syncFailed(profileName: String, deletedProfileIds: [String], createdProfileId: String?, underlying: any Swift.Error)

        public var errorDescription: String? {
            switch self {
            case .missingData(let msg):
                return msg
            case .duplicateProfileName(let name):
                return "Profile name \(name) is listed more than once"
            case .noDevices(let platform, let type):
                return "\(type.rawValue) profiles need at least one enabled \(platform.rawValue) device, and there is none. "
                    + "Register one with: blimp maintenance register-device <udid> <name> --platform \(platform.rawValue)"
            case .syncFailed(let profileName, _, let createdProfileId?, let underlying):
                return "Could not store profile \(profileName): \(underlying.localizedDescription). "
                    + "Portal profile \(createdProfileId) was created; run sync-profiles again with --force to replace and store it."
            case .syncFailed(let profileName, let deletedProfileIds, nil, let underlying):
                let failure = "Could not sync profile \(profileName): \(underlying.localizedDescription)"
                guard !deletedProfileIds.isEmpty else { return failure }
                return "\(failure). Its previous portal profile was already deleted; run sync-profiles again with --force to recreate it."
            }
        }
    }
}

private extension ProfileSyncCoordinator {
    func firstDuplicateProfileName(in bundleIds: [(bundleId: String, profileName: String)]) -> String? {
        var seen: Set<String> = []
        return bundleIds.map(\.profileName).first { !seen.insert($0).inserted }
    }

    /// A profile to create, with every input resolved before the portal is changed.
    struct PendingProfile {
        let name: String
        let filePath: String
        let bundleResourceId: String
        let staleProfileIds: [String]
    }

    func resolvePendingProfiles(
        bundleIds: [(bundleId: String, profileName: String)],
        type: ProvisioningAPI.ProfileType,
        platform: ProvisioningAPI.Platform,
        force: Bool
    ) async throws -> [PendingProfile] {
        var pending: [PendingProfile] = []
        for entry in bundleIds {
            let filePath = "profiles/\(platform.rawValue)/\(type.rawValue)/\(entry.profileName).mobileprovision"

            if !force, await git.fileExists(path: filePath) {
                logger.info("Profile \(entry.profileName) exists in storage, skipping.")
                continue
            }

            guard let bundleResourceId = try await profileService.getBundleId(identifier: entry.bundleId) else {
                throw Error.missingData("Could not find Bundle ID resource for \(entry.bundleId)")
            }

            let staleProfileIds = force ? try await profileService.listProfiles(name: entry.profileName).map(\.id) : []

            pending.append(PendingProfile(
                name: entry.profileName,
                filePath: filePath,
                bundleResourceId: bundleResourceId,
                staleProfileIds: staleProfileIds
            ))
        }
        return pending
    }

    /// The portal refuses a second profile under the same name and profiles cannot be
    /// renamed, so the stale one is deleted right before its replacement is created.
    func replace(
        _ profile: PendingProfile,
        type: ProvisioningAPI.ProfileType,
        certificateIds: [String],
        deviceIds: [String]?
    ) async throws {
        var deletedProfileIds: [String] = []
        var createdProfileId: String?
        do {
            if !profile.staleProfileIds.isEmpty {
                logger.info("Deleting \(profile.staleProfileIds.count) existing profile(s) for \(profile.name)")
            }
            for id in profile.staleProfileIds {
                try await deleteIfPresent(profileId: id)
                deletedProfileIds.append(id)
            }

            let newProfile = try await profileService.createProfile(
                name: profile.name,
                type: type,
                bundleId: profile.bundleResourceId,
                certificateIds: certificateIds,
                deviceIds: deviceIds
            )
            createdProfileId = newProfile.id

            guard let content = newProfile.content else {
                throw Error.missingData("Profile created but no content returned")
            }

            try await git.writeFile(path: profile.filePath, content: content)
        } catch {
            throw Error.syncFailed(
                profileName: profile.name,
                deletedProfileIds: deletedProfileIds,
                createdProfileId: createdProfileId,
                underlying: error
            )
        }

        logger.info("Synced profile: \(profile.name)")
    }

    /// A stale profile removed since it was listed (a parallel run, a manual delete) is already gone.
    func deleteIfPresent(profileId: String) async throws {
        do {
            try await profileService.deleteProfile(id: profileId)
        } catch ProvisioningAPI.Error.notFound {
            logger.info("Profile \(profileId) is no longer on the portal")
        }
    }

    func commit(_ synced: [String], type: ProvisioningAPI.ProfileType) async throws {
        guard !synced.isEmpty else { return }
        try await git.commitAndPush(message: "Update \(typeLabel(type)) profiles", push: push)
    }

    /// The portal already holds the profiles synced so far: storage has to record them even
    /// though a later one failed. That failure stays the error the caller sees.
    func commitBeforeFailing(_ synced: [String], type: ProvisioningAPI.ProfileType) async {
        do {
            try await commit(synced, type: type)
        } catch {
            logger.error("Could not commit profiles synced before the failure (\(synced.joined(separator: ", "))): \(error.localizedDescription)")
        }
    }

    func typeLabel(_ type: ProvisioningAPI.ProfileType) -> String {
        switch type {
        case .iosAppDevelopment, .macAppDevelopment, .tvosAppDevelopment, .macCatalystAppDevelopment: "development"
        case .iosAppStore, .macAppStore, .tvosAppStore, .macCatalystAppStore: "appstore"
        case .iosAppAdhoc, .tvosAppAdhoc: "adhoc"
        case .iosAppInhouse, .tvosAppInhouse: "inhouse"
        case .macAppDirect, .macCatalystAppDirect: "direct"
        }
    }

    func resolveDeviceIds(type: ProvisioningAPI.ProfileType, platform: ProvisioningAPI.Platform) async throws -> [String]? {
        guard requiresDevices(type: type) else {
            return nil
        }

        let devices = try await deviceService.listDevices(platform: platform, status: .enabled)
        guard !devices.isEmpty else {
            throw Error.noDevices(platform: platform, type: type)
        }

        logger.info("Found \(devices.count) enabled devices")
        return devices.map(\.id)
    }

    func requiresDevices(type: ProvisioningAPI.ProfileType) -> Bool {
        switch type {
        case .iosAppDevelopment, .tvosAppDevelopment, .macAppDevelopment, .macCatalystAppDevelopment:
            return true
        case .iosAppAdhoc, .tvosAppAdhoc:
            return true
        default:
            return false
        }
    }
}
