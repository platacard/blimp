import Foundation
import ProvisioningAPI
import Gito
@testable import BlimpKit

// MARK: - Git Mock

actor MockGitRepo: GitManaging {
    var fileStore: [String: Data] = [:]
    var pushedCommits: [String] = []
    var cloneOrPullCalled = false
    private var remoteURL: String? = nil

    nonisolated var localURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mock_git")
    }

    func cloneOrPull() throws {
        cloneOrPullCalled = true
    }

    func setRemote(url: String) throws {
        remoteURL = url
    }

    func hasRemote() -> Bool {
        return remoteURL != nil
    }

    func commitAndPush(message: String, push: Bool) throws {
        pushedCommits.append(message)
    }

    func fileExists(path: String) -> Bool {
        return fileStore[path] != nil
    }

    func readFile(path: String) throws -> Data {
        guard let data = fileStore[path] else {
            throw NSError(domain: "GitMock", code: 404, userInfo: nil)
        }
        return data
    }

    func writeFile(path: String, content: Data) throws {
        fileStore[path] = content
    }
}

// MARK: - Encryption Mock

class MockEncrypter: EncryptionService, @unchecked Sendable {
    func encrypt(data: Data, password: String) throws -> Data {
        return data
    }

    func decrypt(data: Data, password: String) throws -> Data {
        return data
    }
}

// MARK: - Certificate Generator Mock

class MockCertificateGenerator: CertificateGenerating, @unchecked Sendable {
    func generateCSR() throws -> (String, Data) {
        return ("CSR_CONTENT", "PRIVATE_KEY".data(using: .utf8)!)
    }

    func generateP12(certContent: Data, privateKey: Data, passphrase: String) throws -> Data {
        return "P12_CONTENT".data(using: .utf8)!
    }
}

// MARK: - Certificate Service Mock

class MockCertificateService: CertificateService, @unchecked Sendable {
    var certificates: [ProvisioningAPI.Certificate] = []
    var deletedCertificateIds: [String] = []

    func listCertificates(filterType: ProvisioningAPI.CertificateType?) async throws -> [ProvisioningAPI.Certificate] {
        if let filter = filterType {
            return certificates.filter { $0.type == filter }
        }
        return certificates
    }

    func createCertificate(csrContent: String, type: ProvisioningAPI.CertificateType) async throws -> ProvisioningAPI.Certificate {
        let cert = ProvisioningAPI.Certificate(
            id: UUID().uuidString,
            name: "Mock Cert",
            type: type,
            content: "CERT_CONTENT".data(using: .utf8),
            serialNumber: "123456"
        )
        certificates.append(cert)
        return cert
    }

    func deleteCertificate(id: String) async throws {
        deletedCertificateIds.append(id)
        certificates.removeAll { $0.id == id }
    }
}

// MARK: - Profile Service Mock

class MockProfileService: ProfileService, @unchecked Sendable {
    var bundleIds: [String: String] = [:]
    var profiles: [ProvisioningAPI.Profile] = []
    var deletedProfileIds: [String] = []

    func getBundleId(identifier: String) async throws -> String? {
        return bundleIds[identifier]
    }

    func createProfile(name: String, type: ProvisioningAPI.ProfileType, bundleId: String, certificateIds: [String], deviceIds: [String]?) async throws -> ProvisioningAPI.Profile {
        let profile = ProvisioningAPI.Profile(
            id: UUID().uuidString,
            name: name,
            type: type,
            content: "PROFILE_CONTENT".data(using: .utf8),
            expirationDate: Date().addingTimeInterval(3600)
        )
        profiles.append(profile)
        return profile
    }

    func listProfiles(name: String?) async throws -> [ProvisioningAPI.Profile] {
        if let name = name {
            return profiles.filter { $0.name == name }
        }
        return profiles
    }

    func deleteProfile(id: String) async throws {
        deletedProfileIds.append(id)
        profiles.removeAll { $0.id == id }
    }
}

// MARK: - Device Service Mock

class MockDeviceService: DeviceService, @unchecked Sendable {
    var devices: [ProvisioningAPI.Device] = []

    func registerDevice(name: String, udid: String, platform: ProvisioningAPI.Platform) async throws -> ProvisioningAPI.Device {
        let device = ProvisioningAPI.Device(id: UUID().uuidString, name: name, udid: udid, platform: platform, status: .enabled)
        devices.append(device)
        return device
    }

    func listDevices(platform: ProvisioningAPI.Platform?) async throws -> [ProvisioningAPI.Device] {
        if let platform = platform {
            return devices.filter { $0.platform == platform }
        }
        return devices
    }
}

// MARK: - Combined Mock (for backward compatibility)

class MockProvisioningService: ProvisioningService, @unchecked Sendable {
    var bundleIds: [String: String] = [:]
    var devices: [ProvisioningAPI.Device] = []
    var certificates: [ProvisioningAPI.Certificate] = []
    var profiles: [ProvisioningAPI.Profile] = []
    var deletedProfileIds: [String] = []
    var deletedCertificateIds: [String] = []

    func getBundleId(identifier: String) async throws -> String? {
        return bundleIds[identifier]
    }

    func registerDevice(name: String, udid: String, platform: ProvisioningAPI.Platform) async throws -> ProvisioningAPI.Device {
        let device = ProvisioningAPI.Device(id: UUID().uuidString, name: name, udid: udid, platform: platform, status: .enabled)
        devices.append(device)
        return device
    }

    func listDevices(platform: ProvisioningAPI.Platform?) async throws -> [ProvisioningAPI.Device] {
        if let platform = platform {
            return devices.filter { $0.platform == platform }
        }
        return devices
    }

    func listCertificates(filterType: ProvisioningAPI.CertificateType?) async throws -> [ProvisioningAPI.Certificate] {
        if let filter = filterType {
            return certificates.filter { $0.type == filter }
        }
        return certificates
    }

    func createCertificate(csrContent: String, type: ProvisioningAPI.CertificateType) async throws -> ProvisioningAPI.Certificate {
        let cert = ProvisioningAPI.Certificate(
            id: UUID().uuidString,
            name: "Mock Cert",
            type: type,
            content: "CERT_CONTENT".data(using: .utf8),
            serialNumber: "123456"
        )
        certificates.append(cert)
        return cert
    }

    func deleteCertificate(id: String) async throws {
        deletedCertificateIds.append(id)
        certificates.removeAll { $0.id == id }
    }

    func createProfile(name: String, type: ProvisioningAPI.ProfileType, bundleId: String, certificateIds: [String], deviceIds: [String]?) async throws -> ProvisioningAPI.Profile {
        let profile = ProvisioningAPI.Profile(
            id: UUID().uuidString,
            name: name,
            type: type,
            content: "PROFILE_CONTENT".data(using: .utf8),
            expirationDate: Date().addingTimeInterval(3600)
        )
        profiles.append(profile)
        return profile
    }

    func listProfiles(name: String?) async throws -> [ProvisioningAPI.Profile] {
        if let name = name {
            return profiles.filter { $0.name == name }
        }
        return profiles
    }

    func deleteProfile(id: String) async throws {
        deletedProfileIds.append(id)
        profiles.removeAll { $0.id == id }
    }
}
