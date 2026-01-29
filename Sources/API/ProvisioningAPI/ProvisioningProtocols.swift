import Foundation

/// Service for encrypting and decrypting data with a password.
public protocol EncryptionService: Sendable {
    func encrypt(data: Data, password: String) throws -> Data
    func decrypt(data: Data, password: String) throws -> Data
}

/// Service for generating certificates and related cryptographic artifacts.
public protocol CertificateGenerating: Sendable {
    func generateCSR() throws -> (String, Data)
    func generateP12(certContent: Data, privateKey: Data, passphrase: String) throws -> Data
}

// MARK: - Separated Services

/// Service for managing certificates in Apple Developer Portal.
public protocol CertificateService: Sendable {
    func listCertificates(filterType: ProvisioningAPI.CertificateType?) async throws -> [ProvisioningAPI.Certificate]
    func createCertificate(csrContent: String, type: ProvisioningAPI.CertificateType) async throws -> ProvisioningAPI.Certificate
    func deleteCertificate(id: String) async throws
}

/// Service for managing provisioning profiles in Apple Developer Portal.
public protocol ProfileService: Sendable {
    func getBundleId(identifier: String) async throws -> String?
    func createProfile(name: String, type: ProvisioningAPI.ProfileType, bundleId: String, certificateIds: [String], deviceIds: [String]?) async throws -> ProvisioningAPI.Profile
    func listProfiles(name: String?) async throws -> [ProvisioningAPI.Profile]
    func deleteProfile(id: String) async throws
}

/// Service for managing devices in Apple Developer Portal.
public protocol DeviceService: Sendable {
    func registerDevice(name: String, udid: String, platform: ProvisioningAPI.Platform) async throws -> ProvisioningAPI.Device
    func listDevices(platform: ProvisioningAPI.Platform?, status: ProvisioningAPI.Device.Status?) async throws -> [ProvisioningAPI.Device]
}

// MARK: - Combined Protocol (for backward compatibility during transition)

/// Combined service for interacting with Apple Developer Portal provisioning APIs.
/// @available(*, deprecated, message: "Use CertificateService, ProfileService, or DeviceService instead")
public protocol ProvisioningService: CertificateService, ProfileService, DeviceService {}
