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
            bundleIds: [bundleId],
            certificateId: certificateId
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
            bundleIds: [bundleId],
            certificateId: certificateId
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
            bundleIds: [bundleId],
            certificateId: certificateId,
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
            bundleIds: bundleIds,
            certificateId: certificateId
        )

        XCTAssertEqual(mockProfileService.profiles.count, 3)

        for bundleId in bundleIds {
            let profilePath = "profiles/ios/IOS_APP_STORE/\(bundleId).mobileprovision"
            let exists = await mockGit.fileExists(path: profilePath)
            XCTAssertTrue(exists, "Profile for \(bundleId) should exist")
        }
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
            bundleIds: [bundleId],
            certificateId: certificateId
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
            bundleIds: [bundleId],
            certificateId: certificateId
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
            bundleIds: [bundleId],
            certificateId: certificateId
        )

        XCTAssertEqual(mockProfileService.profiles.count, 1)
        let profile = mockProfileService.profiles.first
        XCTAssertEqual(profile?.type, .iosAppStore)
    }

    // MARK: - Error Handling Tests

    func testSyncFailsForMissingBundleId() async {
        let bundleId = "com.nonexistent.app"
        let certificateId = "cert-123"

        do {
            try await coordinator.sync(
                platform: .ios,
                type: .iosAppDevelopment,
                bundleIds: [bundleId],
                certificateId: certificateId
            )
            XCTFail("Should throw error for missing bundle ID")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Could not find Bundle ID"))
        }
    }
}
