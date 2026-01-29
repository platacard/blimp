import XCTest
import ProvisioningAPI
@testable import BlimpKit

final class CertificateManagerTests: XCTestCase {
    var mockCertService: MockCertificateService!
    var mockGit: MockGitRepo!
    var mockEncrypter: MockEncrypter!
    var mockCertGen: MockCertificateGenerator!
    var manager: CertificateManager!

    override func setUp() {
        super.setUp()
        mockCertService = MockCertificateService()
        mockGit = MockGitRepo()
        mockEncrypter = MockEncrypter()
        mockCertGen = MockCertificateGenerator()

        manager = CertificateManager(
            certificateService: mockCertService,
            git: mockGit,
            encrypter: mockEncrypter,
            certGenerator: mockCertGen,
            passphrase: "test-pass"
        )
    }

    // MARK: - Find Certificate Tests

    func testFindValidCertificateReturnsIdWhenExists() async throws {
        let cert = try await mockCertService.createCertificate(csrContent: "csr", type: .development)
        let p12Path = "certificates/ios/DEVELOPMENT/\(cert.id).p12"
        try await mockGit.writeFile(path: p12Path, content: Data())

        let foundId = try await manager.findValidCertificate(type: .development, platform: .ios)

        XCTAssertEqual(foundId, cert.id)

        let cloneOrPullCalled = await mockGit.cloneOrPullCalled
        XCTAssertTrue(cloneOrPullCalled)
    }

    func testFindValidCertificateReturnsNilWhenNotInStorage() async throws {
        _ = try await mockCertService.createCertificate(csrContent: "csr", type: .development)

        let foundId = try await manager.findValidCertificate(type: .development, platform: .ios)

        XCTAssertNil(foundId, "Should return nil when certificate is not in git storage")
    }

    func testFindValidCertificateReturnsNilWhenNoCertificates() async throws {
        let foundId = try await manager.findValidCertificate(type: .development, platform: .ios)

        XCTAssertNil(foundId)
    }

    func testFindValidCertificateFiltersCorrectType() async throws {
        let devCert = try await mockCertService.createCertificate(csrContent: "csr", type: .development)
        let distCert = try await mockCertService.createCertificate(csrContent: "csr", type: .distribution)

        let devPath = "certificates/ios/DEVELOPMENT/\(devCert.id).p12"
        let distPath = "certificates/ios/DISTRIBUTION/\(distCert.id).p12"
        try await mockGit.writeFile(path: devPath, content: Data())
        try await mockGit.writeFile(path: distPath, content: Data())

        let foundDev = try await manager.findValidCertificate(type: .development, platform: .ios)
        XCTAssertEqual(foundDev, devCert.id)

        let foundDist = try await manager.findValidCertificate(type: .distribution, platform: .ios)
        XCTAssertEqual(foundDist, distCert.id)
    }

    // MARK: - Create Certificate Tests

    func testCreateAndStoreCertificate() async throws {
        let cert = try await manager.createAndStoreCertificate(type: .development, platform: .ios)

        XCTAssertEqual(mockCertService.certificates.count, 1)
        XCTAssertEqual(mockCertService.certificates.first?.id, cert.id)
        XCTAssertEqual(cert.type, .development)

        let p12Path = "certificates/ios/DEVELOPMENT/\(cert.id).p12"
        let p12Exists = await mockGit.fileExists(path: p12Path)
        XCTAssertTrue(p12Exists)

        let pushedCommits = await mockGit.pushedCommits
        XCTAssertFalse(pushedCommits.isEmpty)
        XCTAssertTrue(pushedCommits.first?.contains(cert.id) ?? false)
    }

    func testCreateAndStoreCertificateForDifferentPlatforms() async throws {
        let iosCert = try await manager.createAndStoreCertificate(type: .development, platform: .ios)
        let macCert = try await manager.createAndStoreCertificate(type: .macAppDevelopment, platform: .macos)

        XCTAssertEqual(mockCertService.certificates.count, 2)

        let iosPath = "certificates/ios/DEVELOPMENT/\(iosCert.id).p12"
        let macPath = "certificates/macos/MAC_APP_DEVELOPMENT/\(macCert.id).p12"

        let iosExists = await mockGit.fileExists(path: iosPath)
        let macExists = await mockGit.fileExists(path: macPath)

        XCTAssertTrue(iosExists)
        XCTAssertTrue(macExists)
    }

    // MARK: - Ensure Certificate Tests

    func testEnsureCertificateReturnsExistingId() async throws {
        let existingCert = try await mockCertService.createCertificate(csrContent: "csr", type: .development)
        let p12Path = "certificates/ios/DEVELOPMENT/\(existingCert.id).p12"
        try await mockGit.writeFile(path: p12Path, content: Data())

        let certId = try await manager.ensureCertificate(type: .development, platform: .ios)

        XCTAssertEqual(certId, existingCert.id)
        XCTAssertEqual(mockCertService.certificates.count, 1, "Should not create new certificate")
    }

    func testEnsureCertificateCreatesNewWhenNotFound() async throws {
        let certId = try await manager.ensureCertificate(type: .development, platform: .ios)

        XCTAssertEqual(mockCertService.certificates.count, 1)
        XCTAssertEqual(mockCertService.certificates.first?.id, certId)

        let p12Path = "certificates/ios/DEVELOPMENT/\(certId).p12"
        let exists = await mockGit.fileExists(path: p12Path)
        XCTAssertTrue(exists)
    }

    func testEnsureCertificateCreatesNewWhenExistsInPortalButNotStorage() async throws {
        _ = try await mockCertService.createCertificate(csrContent: "csr", type: .development)

        let certId = try await manager.ensureCertificate(type: .development, platform: .ios)

        XCTAssertEqual(mockCertService.certificates.count, 2, "Should create new cert when existing one not in storage")

        let p12Path = "certificates/ios/DEVELOPMENT/\(certId).p12"
        let exists = await mockGit.fileExists(path: p12Path)
        XCTAssertTrue(exists)
    }
}
