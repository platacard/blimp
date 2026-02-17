import XCTest
import ProvisioningAPI
@testable import BlimpKit

final class CertificateManagerTests: XCTestCase {
    var mockCertService: MockCertificateService!
    var mockGit: MockGitRepo!
    var mockCertGen: MockCertificateGenerator!
    var manager: CertificateManager!

    override func setUp() {
        super.setUp()
        mockCertService = MockCertificateService()
        mockGit = MockGitRepo()
        mockCertGen = MockCertificateGenerator()

        manager = CertificateManager(
            certificateService: mockCertService,
            git: mockGit,
            certGenerator: mockCertGen,
            passphrase: "test-pass"
        )
    }

    // MARK: - Find Certificate Tests

    func testFindValidCertificateReturnsIdWhenExists() async throws {
        let cert = try await mockCertService.createCertificate(csrContent: "csr", type: .development)
        let p12Path = "certificates/DEVELOPMENT/\(cert.id).p12"
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

        let devPath = "certificates/DEVELOPMENT/\(devCert.id).p12"
        let distPath = "certificates/DISTRIBUTION/\(distCert.id).p12"
        try await mockGit.writeFile(path: devPath, content: Data())
        try await mockGit.writeFile(path: distPath, content: Data())

        let foundDev = try await manager.findValidCertificate(type: .development, platform: .ios)
        XCTAssertEqual(foundDev, devCert.id)

        let foundDist = try await manager.findValidCertificate(type: .distribution, platform: .ios)
        XCTAssertEqual(foundDist, distCert.id)
    }

    // MARK: - Universal Certificate Tests

    func testUniversalCertFoundFromAnyPlatform() async throws {
        let cert = try await mockCertService.createCertificate(csrContent: "csr", type: .distribution)
        let p12Path = "certificates/DISTRIBUTION/\(cert.id).p12"
        try await mockGit.writeFile(path: p12Path, content: Data())

        let foundFromMacos = try await manager.findValidCertificate(type: .distribution, platform: .macos)
        XCTAssertEqual(foundFromMacos, cert.id)

        let foundFromIos = try await manager.findValidCertificate(type: .distribution, platform: .ios)
        XCTAssertEqual(foundFromIos, cert.id)

        let foundFromTvos = try await manager.findValidCertificate(type: .distribution, platform: .tvos)
        XCTAssertEqual(foundFromTvos, cert.id)
    }

    func testUniversalDevCertFoundFromAnyPlatform() async throws {
        let cert = try await mockCertService.createCertificate(csrContent: "csr", type: .development)
        let p12Path = "certificates/DEVELOPMENT/\(cert.id).p12"
        try await mockGit.writeFile(path: p12Path, content: Data())

        let foundFromMacos = try await manager.findValidCertificate(type: .development, platform: .macos)
        XCTAssertEqual(foundFromMacos, cert.id)

        let foundFromIos = try await manager.findValidCertificate(type: .development, platform: .ios)
        XCTAssertEqual(foundFromIos, cert.id)
    }

    func testPlatformSpecificCertNotFoundAcrossPlatforms() async throws {
        let cert = try await mockCertService.createCertificate(csrContent: "csr", type: .iosDevelopment)
        let p12Path = "certificates/ios/IOS_DEVELOPMENT/\(cert.id).p12"
        try await mockGit.writeFile(path: p12Path, content: Data())

        let foundFromIos = try await manager.findValidCertificate(type: .iosDevelopment, platform: .ios)
        XCTAssertEqual(foundFromIos, cert.id, "Should find platform-specific cert in its own platform dir")

        let foundFromMacos = try await manager.findValidCertificate(type: .iosDevelopment, platform: .macos)
        XCTAssertNil(foundFromMacos, "Platform-specific cert should NOT be found from another platform")
    }

    func testEnsureCertificateReusesUniversalCertAcrossPlatforms() async throws {
        let existingCert = try await mockCertService.createCertificate(csrContent: "csr", type: .distribution)
        let p12Path = "certificates/DISTRIBUTION/\(existingCert.id).p12"
        try await mockGit.writeFile(path: p12Path, content: Data())

        let certId = try await manager.ensureCertificate(type: .distribution, platform: .macos)

        XCTAssertEqual(certId, existingCert.id)
        XCTAssertEqual(mockCertService.certificates.count, 1, "Should reuse existing universal cert, not create new")
    }

    // MARK: - Create Certificate Tests

    func testCreateAndStoreUniversalCertOmitsPlatformDir() async throws {
        let cert = try await manager.createAndStoreCertificate(type: .development, platform: .ios)

        let p12Path = "certificates/DEVELOPMENT/\(cert.id).p12"
        let p12Exists = await mockGit.fileExists(path: p12Path)
        XCTAssertTrue(p12Exists, "Universal cert should be stored without platform directory")

        let wrongPath = "certificates/ios/DEVELOPMENT/\(cert.id).p12"
        let wrongExists = await mockGit.fileExists(path: wrongPath)
        XCTAssertFalse(wrongExists, "Universal cert should NOT be stored under platform directory")
    }

    func testCreateAndStorePlatformSpecificCertIncludesPlatformDir() async throws {
        let cert = try await manager.createAndStoreCertificate(type: .macAppDevelopment, platform: .macos)

        let p12Path = "certificates/macos/MAC_APP_DEVELOPMENT/\(cert.id).p12"
        let p12Exists = await mockGit.fileExists(path: p12Path)
        XCTAssertTrue(p12Exists, "Platform-specific cert should include platform directory")
    }

    func testCreateAndStoreCertificate() async throws {
        let cert = try await manager.createAndStoreCertificate(type: .development, platform: .ios)

        XCTAssertEqual(mockCertService.certificates.count, 1)
        XCTAssertEqual(mockCertService.certificates.first?.id, cert.id)
        XCTAssertEqual(cert.type, .development)

        let p12Path = "certificates/DEVELOPMENT/\(cert.id).p12"
        let p12Exists = await mockGit.fileExists(path: p12Path)
        XCTAssertTrue(p12Exists)

        let pushedCommits = await mockGit.pushedCommits
        XCTAssertFalse(pushedCommits.isEmpty)
        XCTAssertTrue(pushedCommits.first?.contains(cert.id) ?? false)
    }

    func testCreateAndStoreCertificateForDifferentPlatforms() async throws {
        let universalCert = try await manager.createAndStoreCertificate(type: .development, platform: .ios)
        let macCert = try await manager.createAndStoreCertificate(type: .macAppDevelopment, platform: .macos)

        XCTAssertEqual(mockCertService.certificates.count, 2)

        let universalPath = "certificates/DEVELOPMENT/\(universalCert.id).p12"
        let macPath = "certificates/macos/MAC_APP_DEVELOPMENT/\(macCert.id).p12"

        let universalExists = await mockGit.fileExists(path: universalPath)
        let macExists = await mockGit.fileExists(path: macPath)

        XCTAssertTrue(universalExists)
        XCTAssertTrue(macExists)
    }

    // MARK: - Ensure Certificate Tests

    func testEnsureCertificateReturnsExistingId() async throws {
        let existingCert = try await mockCertService.createCertificate(csrContent: "csr", type: .development)
        let p12Path = "certificates/DEVELOPMENT/\(existingCert.id).p12"
        try await mockGit.writeFile(path: p12Path, content: Data())

        let certId = try await manager.ensureCertificate(type: .development, platform: .ios)

        XCTAssertEqual(certId, existingCert.id)
        XCTAssertEqual(mockCertService.certificates.count, 1, "Should not create new certificate")
    }

    func testEnsureCertificateCreatesNewWhenNotFound() async throws {
        let certId = try await manager.ensureCertificate(type: .development, platform: .ios)

        XCTAssertEqual(mockCertService.certificates.count, 1)
        XCTAssertEqual(mockCertService.certificates.first?.id, certId)

        let p12Path = "certificates/DEVELOPMENT/\(certId).p12"
        let exists = await mockGit.fileExists(path: p12Path)
        XCTAssertTrue(exists)
    }

    func testEnsureCertificateCreatesNewWhenExistsInPortalButNotStorage() async throws {
        _ = try await mockCertService.createCertificate(csrContent: "csr", type: .development)

        let certId = try await manager.ensureCertificate(type: .development, platform: .ios)

        XCTAssertEqual(mockCertService.certificates.count, 2, "Should create new cert when existing one not in storage")

        let p12Path = "certificates/DEVELOPMENT/\(certId).p12"
        let exists = await mockGit.fileExists(path: p12Path)
        XCTAssertTrue(exists)
    }
}
