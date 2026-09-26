import XCTest
import ProvisioningAPI
@testable import BlimpKit

final class ProfileSyncCoordinatorTests: XCTestCase {
    var mockProfileService: MockProfileService!
    var mockDeviceService: MockDeviceService!
    var mockGit: MockGitRepo!
    var coordinator: ProfileSyncCoordinator!

    override func setUp() {
        super.setUp()
        mockProfileService = MockProfileService()
        mockDeviceService = MockDeviceService()
        mockGit = MockGitRepo()

        coordinator = ProfileSyncCoordinator(
            profileService: mockProfileService,
            deviceService: mockDeviceService,
            git: mockGit
        )
    }

    // MARK: - Basic Sync Tests

    func testSyncCreatesProfile() async throws {
        let bundleId = "com.example.app"
        let certificateId = "cert-123"
        mockProfileService.bundleIds[bundleId] = "bundle-resource-id"

        try await coordinator.sync(
            platform: .ios,
            type: .iosAppDevelopment,
            bundleIds: [(bundleId, bundleId)],
            certificateIds: [certificateId]
        )

        let cloneOrPullCalled = await mockGit.cloneOrPullCalled
        XCTAssertTrue(cloneOrPullCalled)

        XCTAssertEqual(mockProfileService.profiles.count, 1)
        let profile = mockProfileService.profiles.first
        XCTAssertEqual(profile?.name, bundleId)
        XCTAssertEqual(profile?.type, .iosAppDevelopment)

        let profilePath = "profiles/ios/IOS_APP_DEVELOPMENT/\(bundleId).mobileprovision"
        let profileExists = await mockGit.fileExists(path: profilePath)
        XCTAssertTrue(profileExists)
    }

    func testSyncSkipsExistingProfile() async throws {
        let bundleId = "com.example.app"
        let certificateId = "cert-123"
        mockProfileService.bundleIds[bundleId] = "bundle-resource-id"

        let profilePath = "profiles/ios/IOS_APP_DEVELOPMENT/\(bundleId).mobileprovision"
        try await mockGit.writeFile(path: profilePath, content: Data())

        try await coordinator.sync(
            platform: .ios,
            type: .iosAppDevelopment,
            bundleIds: [(bundleId, bundleId)],
            certificateIds: [certificateId]
        )

        XCTAssertEqual(mockProfileService.profiles.count, 0, "Should not create profile when it already exists")
    }

    func testSyncForceRegeneratesProfile() async throws {
        let bundleId = "com.example.app"
        let certificateId = "cert-123"
        mockProfileService.bundleIds[bundleId] = "bundle-resource-id"

        let existingProfile = try await mockProfileService.createProfile(
            name: bundleId,
            type: .iosAppDevelopment,
            bundleId: "bundle-resource-id",
            certificateIds: [certificateId],
            deviceIds: nil
        )

        let profilePath = "profiles/ios/IOS_APP_DEVELOPMENT/\(bundleId).mobileprovision"
        try await mockGit.writeFile(path: profilePath, content: Data())

        try await coordinator.sync(
            platform: .ios,
            type: .iosAppDevelopment,
            bundleIds: [(bundleId, bundleId)],
            certificateIds: [certificateId],
            force: true
        )

        XCTAssertTrue(mockProfileService.deletedProfileIds.contains(existingProfile.id))
        XCTAssertEqual(mockProfileService.profiles.count, 1)
        XCTAssertNotEqual(mockProfileService.profiles.first?.id, existingProfile.id)
    }

    func testSyncMultipleBundleIds() async throws {
        let bundleIds = ["com.example.app", "com.example.app.widget", "com.example.app.extension"]
        let certificateId = "cert-123"

        for bundleId in bundleIds {
            mockProfileService.bundleIds[bundleId] = "resource-\(bundleId)"
        }

        try await coordinator.sync(
            platform: .ios,
            type: .iosAppStore,
            bundleIds: bundleIds.map { ($0, $0) },
            certificateIds: [certificateId]
        )

        XCTAssertEqual(mockProfileService.profiles.count, 3)

        for bundleId in bundleIds {
            let profilePath = "profiles/ios/IOS_APP_STORE/\(bundleId).mobileprovision"
            let exists = await mockGit.fileExists(path: profilePath)
            XCTAssertTrue(exists, "Profile for \(bundleId) should exist")
        }

        let commits = await mockGit.pushedCommits
        XCTAssertEqual(commits, ["Update appstore profiles"], "All synced profiles should land in one commit")
    }

    func testSyncDoesNotCommitWhenNothingChanged() async throws {
        let bundleId = "com.example.app"
        mockProfileService.bundleIds[bundleId] = "bundle-resource-id"

        let profilePath = "profiles/ios/IOS_APP_DEVELOPMENT/\(bundleId).mobileprovision"
        try await mockGit.writeFile(path: profilePath, content: Data())

        try await coordinator.sync(
            platform: .ios,
            type: .iosAppDevelopment,
            bundleIds: [(bundleId, bundleId)],
            certificateIds: ["cert-123"]
        )

        let commits = await mockGit.pushedCommits
        XCTAssertTrue(commits.isEmpty, "Skipped profiles should not produce a commit")
    }

    func testSyncWithCustomProfileName() async throws {
        let bundleId = "com.example.app"
        let profileName = "com.example.app.ah"
        let certificateId = "cert-123"
        mockProfileService.bundleIds[bundleId] = "bundle-resource-id"

        try await coordinator.sync(
            platform: .ios,
            type: .iosAppAdhoc,
            bundleIds: [(bundleId, profileName)],
            certificateIds: [certificateId]
        )

        XCTAssertEqual(mockProfileService.profiles.count, 1)
        let profile = mockProfileService.profiles.first
        XCTAssertEqual(profile?.name, profileName, "Profile should be created with custom name")

        let profilePath = "profiles/ios/IOS_APP_ADHOC/\(profileName).mobileprovision"
        let profileExists = await mockGit.fileExists(path: profilePath)
        XCTAssertTrue(profileExists, "Profile file should use custom name")

        let wrongPath = "profiles/ios/IOS_APP_ADHOC/\(bundleId).mobileprovision"
        let wrongExists = await mockGit.fileExists(path: wrongPath)
        XCTAssertFalse(wrongExists, "Profile file should NOT use bundle ID as name")
    }

    // MARK: - Device Handling Tests

    func testSyncDevelopmentIncludesDevices() async throws {
        let bundleId = "com.example.app"
        let certificateId = "cert-123"
        mockProfileService.bundleIds[bundleId] = "bundle-resource-id"

        _ = try await mockDeviceService.registerDevice(name: "iPhone 15", udid: "UDID-1", platform: .ios)
        _ = try await mockDeviceService.registerDevice(name: "iPhone 14", udid: "UDID-2", platform: .ios)

        try await coordinator.sync(
            platform: .ios,
            type: .iosAppDevelopment,
            bundleIds: [(bundleId, bundleId)],
            certificateIds: [certificateId]
        )

        XCTAssertEqual(mockProfileService.profiles.count, 1)
        XCTAssertEqual(mockDeviceService.devices.count, 2)
    }

    func testSyncAdHocIncludesDevices() async throws {
        let bundleId = "com.example.app"
        let certificateId = "cert-123"
        mockProfileService.bundleIds[bundleId] = "bundle-resource-id"

        _ = try await mockDeviceService.registerDevice(name: "iPhone 15", udid: "UDID-1", platform: .ios)

        try await coordinator.sync(
            platform: .ios,
            type: .iosAppAdhoc,
            bundleIds: [(bundleId, bundleId)],
            certificateIds: [certificateId]
        )

        XCTAssertEqual(mockProfileService.profiles.count, 1)
        let profile = mockProfileService.profiles.first
        XCTAssertEqual(profile?.type, .iosAppAdhoc)
    }

    func testSyncAppStoreDoesNotRequireDevices() async throws {
        let bundleId = "com.example.app"
        let certificateId = "cert-123"
        mockProfileService.bundleIds[bundleId] = "bundle-resource-id"

        try await coordinator.sync(
            platform: .ios,
            type: .iosAppStore,
            bundleIds: [(bundleId, bundleId)],
            certificateIds: [certificateId]
        )

        XCTAssertEqual(mockProfileService.profiles.count, 1)
        let profile = mockProfileService.profiles.first
        XCTAssertEqual(profile?.type, .iosAppStore)
    }

    // MARK: - Device Status Filtering Tests

    func testSyncExcludesDisabledDevices() async throws {
        let bundleId = "com.example.app"
        let certificateId = "cert-123"
        mockProfileService.bundleIds[bundleId] = "bundle-resource-id"

        _ = try await mockDeviceService.registerDevice(name: "iPhone 15", udid: "UDID-1", platform: .ios)
        mockDeviceService.addDevice(name: "Old iPhone", udid: "UDID-2", platform: .ios, status: .disabled)

        try await coordinator.sync(
            platform: .ios,
            type: .iosAppDevelopment,
            bundleIds: [(bundleId, bundleId)],
            certificateIds: [certificateId]
        )

        XCTAssertEqual(mockProfileService.profiles.count, 1)
        XCTAssertEqual(mockDeviceService.devices.count, 2)

        let enabledDevices = try await mockDeviceService.listDevices(platform: .ios, status: .enabled)
        XCTAssertEqual(enabledDevices.count, 1)
    }

    func testSyncOnlyUsesEnabledDevices() async throws {
        let bundleId = "com.example.app"
        let certificateId = "cert-123"
        mockProfileService.bundleIds[bundleId] = "bundle-resource-id"

        mockDeviceService.addDevice(name: "Disabled Device 1", udid: "UDID-1", platform: .ios, status: .disabled)
        mockDeviceService.addDevice(name: "Disabled Device 2", udid: "UDID-2", platform: .ios, status: .disabled)

        try await coordinator.sync(
            platform: .ios,
            type: .iosAppDevelopment,
            bundleIds: [(bundleId, bundleId)],
            certificateIds: [certificateId]
        )

        XCTAssertEqual(mockProfileService.profiles.count, 1)

        let enabledDevices = try await mockDeviceService.listDevices(platform: .ios, status: .enabled)
        XCTAssertEqual(enabledDevices.count, 0, "No enabled devices should be found")
    }

    func testListDevicesFiltersByStatus() async throws {
        mockDeviceService.addDevice(name: "Enabled 1", udid: "UDID-1", platform: .ios, status: .enabled)
        mockDeviceService.addDevice(name: "Enabled 2", udid: "UDID-2", platform: .ios, status: .enabled)
        mockDeviceService.addDevice(name: "Disabled 1", udid: "UDID-3", platform: .ios, status: .disabled)

        let all = try await mockDeviceService.listDevices(platform: nil, status: nil)
        XCTAssertEqual(all.count, 3)

        let enabled = try await mockDeviceService.listDevices(platform: nil, status: .enabled)
        XCTAssertEqual(enabled.count, 2)

        let disabled = try await mockDeviceService.listDevices(platform: nil, status: .disabled)
        XCTAssertEqual(disabled.count, 1)
    }

    // MARK: - Error Handling Tests

    func testSyncFailsForMissingBundleId() async {
        let bundleId = "com.nonexistent.app"
        let certificateId = "cert-123"

        do {
            try await coordinator.sync(
                platform: .ios,
                type: .iosAppDevelopment,
                bundleIds: [(bundleId, bundleId)],
                certificateIds: [certificateId]
            )
            XCTFail("Should throw error for missing bundle ID")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Could not find Bundle ID"))
        }
    }

    // MARK: - Force Safety Tests

    func testForceDeletesNothingWhenTheBundleIdLookupFails() async throws {
        let bundleId = "com.example.app"
        let existing = try await givenStoredProfile(named: bundleId, type: .iosAppStore)
        mockProfileService.bundleIdError = ProvisioningAPI.Error.badResponse("Failed to list bundle IDs")

        do {
            try await coordinator.sync(
                platform: .ios,
                type: .iosAppStore,
                bundleIds: [(bundleId, bundleId)],
                certificateIds: ["cert-123"],
                force: true
            )
            XCTFail("Expected the bundle ID lookup to fail")
        } catch ProvisioningAPI.Error.badResponse {}

        XCTAssertTrue(mockProfileService.deletedProfileIds.isEmpty)
        XCTAssertEqual(mockProfileService.profiles.map(\.id), [existing.id])
    }

    func testForceDeletesNothingWhenALaterBundleIdIsMissing() async throws {
        let app = "com.example.app"
        let widget = "com.example.app.widget"
        mockProfileService.bundleIds[app] = "resource-app"
        let existingApp = try await givenStoredProfile(named: app, type: .iosAppStore)
        let existingWidget = try await givenStoredProfile(named: widget, type: .iosAppStore)

        do {
            try await coordinator.sync(
                platform: .ios,
                type: .iosAppStore,
                bundleIds: [(app, app), (widget, widget)],
                certificateIds: ["cert-123"],
                force: true
            )
            XCTFail("Expected the missing bundle ID to fail the sync")
        } catch ProfileSyncCoordinator.Error.missingData(let message) {
            XCTAssertEqual(message, "Could not find Bundle ID resource for \(widget)")
        }

        XCTAssertTrue(mockProfileService.deletedProfileIds.isEmpty)
        XCTAssertEqual(mockProfileService.profiles.map(\.id), [existingApp.id, existingWidget.id])
        let commits = await mockGit.pushedCommits
        XCTAssertTrue(commits.isEmpty)
    }

    func testForceDeletesNothingWhenTheDeviceLookupFails() async throws {
        let bundleId = "com.example.app"
        mockProfileService.bundleIds[bundleId] = "bundle-resource-id"
        let existing = try await givenStoredProfile(named: bundleId, type: .iosAppDevelopment)
        mockDeviceService.listError = ProvisioningAPI.Error.badResponse("Forbidden")

        do {
            try await coordinator.sync(
                platform: .ios,
                type: .iosAppDevelopment,
                bundleIds: [(bundleId, bundleId)],
                certificateIds: ["cert-123"],
                force: true
            )
            XCTFail("Expected the device lookup to fail")
        } catch ProvisioningAPI.Error.badResponse {}

        XCTAssertTrue(mockProfileService.deletedProfileIds.isEmpty)
        XCTAssertEqual(mockProfileService.profiles.map(\.id), [existing.id])
    }

    func testDuplicateProfileNamesAreRejectedBeforeAnythingChanges() async throws {
        let shared = "com.example.shared"
        mockProfileService.bundleIds["com.example.app"] = "resource-app"
        mockProfileService.bundleIds["com.example.widget"] = "resource-widget"
        let existing = try await givenStoredProfile(named: shared, type: .iosAppStore)

        do {
            try await coordinator.sync(
                platform: .ios,
                type: .iosAppStore,
                bundleIds: [("com.example.app", shared), ("com.example.widget", shared)],
                certificateIds: ["cert-123"],
                force: true
            )
            XCTFail("Expected the duplicate profile name to be rejected")
        } catch let error as ProfileSyncCoordinator.Error {
            guard case .duplicateProfileName(let name) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(name, shared)
            XCTAssertEqual(error.errorDescription, "Profile name com.example.shared is listed more than once")
        }

        XCTAssertTrue(mockProfileService.deletedProfileIds.isEmpty)
        XCTAssertEqual(mockProfileService.profiles.map(\.id), [existing.id])
        let cloneOrPullCalled = await mockGit.cloneOrPullCalled
        XCTAssertFalse(cloneOrPullCalled)
    }

    func testCreateFailureAfterDeleteNamesTheProfileAndTheDeletion() async throws {
        let bundleId = "com.example.app"
        mockProfileService.bundleIds[bundleId] = "bundle-resource-id"
        let existing = try await givenStoredProfile(named: bundleId, type: .iosAppStore)
        mockProfileService.createErrors[bundleId] = ProvisioningAPI.Error.badResponse("Failed to create profile")

        do {
            try await coordinator.sync(
                platform: .ios,
                type: .iosAppStore,
                bundleIds: [(bundleId, bundleId)],
                certificateIds: ["cert-123"],
                force: true
            )
            XCTFail("Expected the create to fail")
        } catch let error as ProfileSyncCoordinator.Error {
            guard case .syncFailed(let profileName, let deletedProfileIds, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(profileName, bundleId)
            XCTAssertEqual(deletedProfileIds, [existing.id])
            XCTAssertEqual(
                error.errorDescription,
                "Could not sync profile com.example.app: Bad response: Failed to create profile. "
                    + "Its previous portal profile was already deleted; run sync-profiles again with --force to recreate it."
            )
        }

        XCTAssertEqual(mockProfileService.deletedProfileIds, [existing.id])
    }

    func testProfilesSyncedBeforeAFailureAreCommitted() async throws {
        let app = "com.example.app"
        let widget = "com.example.app.widget"
        mockProfileService.bundleIds[app] = "resource-app"
        mockProfileService.bundleIds[widget] = "resource-widget"
        mockProfileService.createErrors[widget] = ProvisioningAPI.Error.badResponse("Failed to create profile")

        do {
            try await coordinator.sync(
                platform: .ios,
                type: .iosAppStore,
                bundleIds: [(app, app), (widget, widget)],
                certificateIds: ["cert-123"]
            )
            XCTFail("Expected the widget profile to fail")
        } catch ProfileSyncCoordinator.Error.syncFailed(let profileName, let deletedProfileIds, _) {
            XCTAssertEqual(profileName, widget)
            XCTAssertTrue(deletedProfileIds.isEmpty)
        }

        let appStored = await mockGit.fileExists(path: "profiles/ios/IOS_APP_STORE/\(app).mobileprovision")
        XCTAssertTrue(appStored)
        let commits = await mockGit.pushedCommits
        XCTAssertEqual(commits, ["Update appstore profiles"])
    }

    func testCommitFailureAfterASyncFailureKeepsTheSyncFailure() async throws {
        let app = "com.example.app"
        let widget = "com.example.app.widget"
        mockProfileService.bundleIds[app] = "resource-app"
        mockProfileService.bundleIds[widget] = "resource-widget"
        mockProfileService.createErrors[widget] = ProvisioningAPI.Error.badResponse("Failed to create profile")
        await mockGit.failCommits(with: NSError(domain: "git", code: 1, userInfo: [NSLocalizedDescriptionKey: "push rejected"]))

        do {
            try await coordinator.sync(
                platform: .ios,
                type: .iosAppStore,
                bundleIds: [(app, app), (widget, widget)],
                certificateIds: ["cert-123"]
            )
            XCTFail("Expected the widget profile to fail")
        } catch ProfileSyncCoordinator.Error.syncFailed(let profileName, _, _) {
            XCTAssertEqual(profileName, widget)
        }

        let commits = await mockGit.pushedCommits
        XCTAssertTrue(commits.isEmpty)
    }
}

private extension ProfileSyncCoordinatorTests {
    func givenStoredProfile(named name: String, type: ProvisioningAPI.ProfileType) async throws -> ProvisioningAPI.Profile {
        let profile = try await mockProfileService.createProfile(
            name: name,
            type: type,
            bundleId: "resource-\(name)",
            certificateIds: ["cert-123"],
            deviceIds: nil
        )
        try await mockGit.writeFile(path: "profiles/ios/\(type.rawValue)/\(name).mobileprovision", content: Data())
        return profile
    }
}
