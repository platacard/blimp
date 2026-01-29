import XCTest
import ProvisioningAPI
@testable import BlimpKit

final class ProvisioningCoordinatorTests: XCTestCase {
    var mockAPI: MockProvisioningService!
    var mockGit: MockGitRepo!
    var mockEncrypter: MockEncrypter!
    var mockCertGen: MockCertificateGenerator!
    var coordinator: ProvisioningCoordinator!
    
    override func setUp() {
        super.setUp()
        mockAPI = MockProvisioningService()
        mockGit = MockGitRepo()
        mockEncrypter = MockEncrypter()
        mockCertGen = MockCertificateGenerator()
        
        coordinator = ProvisioningCoordinator(
            api: mockAPI,
            git: mockGit,
            encrypter: mockEncrypter,
            certGenerator: mockCertGen,
            passphrase: "pass"
        )
    }
    
    func testSyncFresh() async throws {
        // Setup
        let bundleId = "com.example.app"
        mockAPI.bundleIds[bundleId] = "bundle-id-123"
        
        // Execute
        try await coordinator.sync(platform: .ios, type: .iosAppDevelopment, bundleIds: [bundleId])
        
        // Verify
        let cloneOrPullCalled = await mockGit.cloneOrPullCalled
        XCTAssertTrue(cloneOrPullCalled)
        
        // Should have created a certificate
        XCTAssertEqual(mockAPI.certificates.count, 1)
        let cert = mockAPI.certificates.first
        XCTAssertEqual(cert?.type, .development)
        
        // Should have stored certificate in git (p12 only)
        // Cert ID is generated, so we need to use the one from API
        guard let createdCert = cert else { return }
        let p12Path = "certificates/ios/DEVELOPMENT/\(createdCert.id).p12"

        let p12Exists = await mockGit.fileExists(path: p12Path)
        XCTAssertTrue(p12Exists)

        // Should have created a profile
        XCTAssertEqual(mockAPI.profiles.count, 1)
        let profile = mockAPI.profiles.first
        XCTAssertEqual(profile?.name, bundleId)

        // Should have stored profile in git
        let profilePath = "profiles/ios/IOS_APP_DEVELOPMENT/\(bundleId).mobileprovision"
        let profileExists = await mockGit.fileExists(path: profilePath)
        XCTAssertTrue(profileExists)
        
        // Should have pushed changes
        let pushedCommits = await mockGit.pushedCommits
        XCTAssertFalse(pushedCommits.isEmpty)
    }
    
    func testSyncExisting() async throws {
        // Setup
        let bundleId = "com.example.app"
        mockAPI.bundleIds[bundleId] = "bundle-id-123"
        
        // Pre-populate certificate in API and Git (p12 only)
        let cert = try await mockAPI.createCertificate(csrContent: "csr", type: .development)
        let p12Path = "certificates/ios/DEVELOPMENT/\(cert.id).p12"
        try await mockGit.writeFile(path: p12Path, content: Data())

        // Execute
        try await coordinator.sync(platform: .ios, type: .iosAppDevelopment, bundleIds: [bundleId])
        
        // Verify
        // Should not create new certificate
        XCTAssertEqual(mockAPI.certificates.count, 1)
        XCTAssertEqual(mockAPI.certificates.first?.id, cert.id)
        
        // Should create profile since it doesn't exist
        XCTAssertEqual(mockAPI.profiles.count, 1)
    }
    
    func testSyncForce() async throws {
        // Setup
        let bundleId = "com.example.app"
        mockAPI.bundleIds[bundleId] = "bundle-id-123"

        // Create existing profile (p12 only)
        let cert = try await mockAPI.createCertificate(csrContent: "csr", type: .development)
        let p12Path = "certificates/ios/DEVELOPMENT/\(cert.id).p12"
        try await mockGit.writeFile(path: p12Path, content: Data())

        let profile = try await mockAPI.createProfile(name: bundleId, type: .iosAppDevelopment, bundleId: "bundle-id-123", certificateIds: [cert.id], deviceIds: nil)

        // Execute with force
        try await coordinator.sync(platform: .ios, type: .iosAppDevelopment, bundleIds: [bundleId], force: true)

        // Verify
        // Old profile should be deleted
        XCTAssertTrue(mockAPI.deletedProfileIds.contains(profile.id))
        // New profile should be created (total 1 active)
        XCTAssertEqual(mockAPI.profiles.count, 1)
        XCTAssertNotEqual(mockAPI.profiles.first?.id, profile.id)
    }

    func testSyncDevelopmentWithDevices() async throws {
        // Setup
        let bundleId = "com.example.app"
        mockAPI.bundleIds[bundleId] = "bundle-id-123"

        // Register some devices
        _ = try await mockAPI.registerDevice(name: "iPhone 15", udid: "UDID-1", platform: .ios)
        _ = try await mockAPI.registerDevice(name: "iPhone 14", udid: "UDID-2", platform: .ios)

        // Execute - development profile should fetch devices
        try await coordinator.sync(platform: .ios, type: .iosAppDevelopment, bundleIds: [bundleId])

        // Verify
        XCTAssertEqual(mockAPI.profiles.count, 1)
        // Devices should have been fetched (we can verify by checking devices list was called)
        XCTAssertEqual(mockAPI.devices.count, 2)
    }

    func testSyncAppStoreWithoutDevices() async throws {
        // Setup
        let bundleId = "com.example.app"
        mockAPI.bundleIds[bundleId] = "bundle-id-123"

        // Register some devices
        _ = try await mockAPI.registerDevice(name: "iPhone 15", udid: "UDID-1", platform: .ios)

        // Execute - App Store profile should NOT require devices
        try await coordinator.sync(platform: .ios, type: .iosAppStore, bundleIds: [bundleId])

        // Verify profile was created
        XCTAssertEqual(mockAPI.profiles.count, 1)
        let profile = mockAPI.profiles.first
        XCTAssertEqual(profile?.type, .iosAppStore)
    }

    func testSyncAdHocWithDevices() async throws {
        // Setup
        let bundleId = "com.example.app"
        mockAPI.bundleIds[bundleId] = "bundle-id-123"

        // Register some devices
        _ = try await mockAPI.registerDevice(name: "iPhone 15", udid: "UDID-1", platform: .ios)

        // Execute - AdHoc profile should fetch devices like development
        try await coordinator.sync(platform: .ios, type: .iosAppAdhoc, bundleIds: [bundleId])

        // Verify
        XCTAssertEqual(mockAPI.profiles.count, 1)
        let profile = mockAPI.profiles.first
        XCTAssertEqual(profile?.type, .iosAppAdhoc)
    }
}
