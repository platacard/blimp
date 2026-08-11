import XCTest
import Foundation
import ProvisioningAPI
@testable import BlimpKit

final class CertificateInstallerTests: XCTestCase {
    var mockGit: MockGitRepo!
    var mockShell: MockShellExecutor!
    var mockWWDR: MockWWDRProvider!
    var installer: CertificateInstaller!

    let passphrase = "test-passphrase"
    let keychainPath = "/tmp/test.keychain-db"

    override func setUp() async throws {
        try await super.setUp()
        mockGit = MockGitRepo()
        mockShell = MockShellExecutor()
        mockWWDR = MockWWDRProvider()

        installer = CertificateInstaller(
            git: mockGit,
            shell: mockShell,
            encrypter: FileEncrypter(),
            wwdrProvider: mockWWDR
        )
    }

    override func tearDown() async throws {
        await mockGit.cleanup()
        try await super.tearDown()
    }

    private func storeEncryptedCertificate(id: String, type: ProvisioningAPI.CertificateType, content: String = "P12_BYTES") async throws {
        let encrypted = try FileEncrypter().encrypt(data: Data(content.utf8), password: passphrase)
        try await mockGit.writeFile(path: "certificates/\(type.rawValue)/\(id).p12", content: encrypted)
    }

    // MARK: - Import

    func testImportsDecryptedCertificateWithCodesignAccess() async throws {
        try await storeEncryptedCertificate(id: "CERT123", type: .development)

        let installed = try await installer.installCertificates(
            platform: .ios,
            type: .development,
            passphrase: passphrase,
            keychain: .path(keychainPath),
            installWWDR: false
        )

        XCTAssertEqual(installed.count, 1)
        XCTAssertEqual(installed.first?.certificateId, "CERT123")
        XCTAssertEqual(installed.first?.keychainPath, keychainPath)

        let importCommand = mockShell.executedCommands.first { $0.contains("security import") }
        XCTAssertNotNil(importCommand)
        XCTAssertTrue(importCommand!.contains("-k \(keychainPath)"))
        XCTAssertTrue(importCommand!.contains("-P \(passphrase)"))
        XCTAssertTrue(importCommand!.contains("-T /usr/bin/codesign"))
    }

    func testDecryptedTempFileContentMatchesOriginal() async throws {
        try await storeEncryptedCertificate(id: "CERT123", type: .development, content: "ORIGINAL_P12_CONTENT")

        var capturedContent: String?
        mockShell.outputForCommand = { command in
            if command.contains("security import"), let path = command.split(separator: " ").dropFirst(2).first {
                capturedContent = try? String(contentsOfFile: String(path), encoding: .utf8)
            }
            return ""
        }

        _ = try await installer.installCertificates(
            platform: .ios,
            type: .development,
            passphrase: passphrase,
            keychain: .path(keychainPath),
            installWWDR: false
        )

        XCTAssertEqual(capturedContent, "ORIGINAL_P12_CONTENT")
    }

    func testImportsAllStoredCertificates() async throws {
        try await storeEncryptedCertificate(id: "CERT1", type: .distribution)
        try await storeEncryptedCertificate(id: "CERT2", type: .distribution)

        let installed = try await installer.installCertificates(
            platform: .ios,
            type: .distribution,
            passphrase: passphrase,
            keychain: .path(keychainPath),
            installWWDR: false
        )

        XCTAssertEqual(installed.map(\.certificateId).sorted(), ["CERT1", "CERT2"])
    }

    func testThrowsWhenNoCertificatesInStorage() async {
        do {
            _ = try await installer.installCertificates(
                platform: .ios,
                type: .development,
                passphrase: passphrase,
                keychain: .path(keychainPath),
                installWWDR: false
            )
            XCTFail("Should throw when storage has no certificates")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No .p12 files"))
        }
    }

    func testDecryptionFailureAbortsWithoutImporting() async throws {
        try await storeEncryptedCertificate(id: "CERT123", type: .development)

        let failingInstaller = CertificateInstaller(
            git: mockGit,
            shell: mockShell,
            encrypter: FailingEncrypter(),
            wwdrProvider: mockWWDR
        )

        do {
            _ = try await failingInstaller.installCertificates(
                platform: .ios,
                type: .development,
                passphrase: passphrase,
                keychain: .path(keychainPath),
                installWWDR: false
            )
            XCTFail("Should throw on decryption failure")
        } catch {
            XCTAssertFalse(mockShell.executedCommands.contains { $0.contains("security import") })
        }
    }

    // MARK: - Keychain partition list

    func testSetsPartitionListOnlyWhenKeychainPasswordProvided() async throws {
        try await storeEncryptedCertificate(id: "CERT123", type: .development)

        _ = try await installer.installCertificates(
            platform: .ios,
            type: .development,
            passphrase: passphrase,
            keychain: .path(keychainPath),
            keychainPassword: nil,
            installWWDR: false
        )

        XCTAssertFalse(mockShell.executedCommands.contains { $0.contains("set-key-partition-list") })

        _ = try await installer.installCertificates(
            platform: .ios,
            type: .development,
            passphrase: passphrase,
            keychain: .path(keychainPath),
            keychainPassword: "keychain-pw",
            installWWDR: false
        )

        let partitionCommand = mockShell.executedCommands.first { $0.contains("set-key-partition-list") }
        XCTAssertNotNil(partitionCommand)
        XCTAssertTrue(partitionCommand!.contains("-S apple-tool:,apple:,codesign:"))
        XCTAssertTrue(partitionCommand!.contains("-k keychain-pw"))
    }

    // MARK: - WWDR

    func testSkipsWWDRWhenAlreadyPresent() async throws {
        try await storeEncryptedCertificate(id: "CERT123", type: .development)

        mockShell.outputForCommand = { command in
            if command.contains("find-certificate") { return "found" }
            return ""
        }

        _ = try await installer.installCertificates(
            platform: .ios,
            type: .development,
            passphrase: passphrase,
            keychain: .path(keychainPath)
        )

        XCTAssertFalse(mockWWDR.fetchCalled)
    }

    func testFetchesAndImportsWWDRWhenMissing() async throws {
        try await storeEncryptedCertificate(id: "CERT123", type: .development)

        mockShell.errorForCommand = { command in
            command.contains("find-certificate") ? MockShellError.commandFailed : nil
        }

        _ = try await installer.installCertificates(
            platform: .ios,
            type: .development,
            passphrase: passphrase,
            keychain: .path(keychainPath)
        )

        XCTAssertTrue(mockWWDR.fetchCalled)
        let wwdrImport = mockShell.executedCommands.first { $0.contains("security import") && $0.contains(".cer") }
        XCTAssertNotNil(wwdrImport)
    }

    func testSkipsWWDRWhenDisabled() async throws {
        try await storeEncryptedCertificate(id: "CERT123", type: .development)

        _ = try await installer.installCertificates(
            platform: .ios,
            type: .development,
            passphrase: passphrase,
            keychain: .path(keychainPath),
            installWWDR: false
        )

        XCTAssertFalse(mockWWDR.fetchCalled)
        XCTAssertFalse(mockShell.executedCommands.contains { $0.contains("find-certificate") })
    }

    func testThrowsWhenWWDRFetchFailsAndMissing() async throws {
        try await storeEncryptedCertificate(id: "CERT123", type: .development)

        mockShell.errorForCommand = { command in
            command.contains("find-certificate") ? MockShellError.commandFailed : nil
        }
        mockWWDR.error = MockShellError.commandFailed

        do {
            _ = try await installer.installCertificates(
                platform: .ios,
                type: .development,
                passphrase: passphrase,
                keychain: .path(keychainPath)
            )
            XCTFail("Should throw when WWDR cannot be fetched")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("WWDR"))
        }
    }
}

// MARK: - Mocks

final class MockWWDRProvider: WWDRCertificateProviding, @unchecked Sendable {
    var fetchCalled = false
    var error: Error?

    func fetch() async throws -> Data {
        fetchCalled = true
        if let error { throw error }
        return Data("WWDR_CERT".utf8)
    }
}

enum MockShellError: Error {
    case commandFailed
}

struct FailingEncrypter: EncryptionService {
    func encrypt(data: Data, password: String) throws -> Data { data }
    func decrypt(data: Data, password: String) throws -> Data { throw FileEncrypter.Error.decryptionFailed }
}
