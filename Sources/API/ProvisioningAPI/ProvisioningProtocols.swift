import Foundation

/// Service for encrypting and decrypting data with a password.
public protocol EncryptionService: Sendable {
    /// Encrypts data using password-based encryption.
    /// - Returns: Encrypted data including any necessary metadata (salt, nonce, etc.)
    func encrypt(data: Data, password: String) throws -> Data

    /// Decrypts data that was encrypted with `encrypt`.
    /// - Returns: Original decrypted data
    func decrypt(data: Data, password: String) throws -> Data
}

/// Service for generating certificates and related cryptographic artifacts.
public protocol CertificateGenerating: Sendable {
    /// Generates a Certificate Signing Request (CSR) and corresponding private key.
    /// - Returns: Tuple of (CSR as PEM string, private key as DER data)
    func generateCSR() throws -> (String, Data)

    /// Creates a PKCS#12 (.p12) file from a certificate and private key.
    /// - Parameters:
    ///   - certContent: The certificate data
    ///   - privateKey: The private key data
    ///   - passphrase: Password to protect the P12 file
    /// - Returns: P12 data that can be imported into Keychain
    func generateP12(certContent: Data, privateKey: Data, passphrase: String) throws -> Data
}

/// Service for interacting with Apple Developer Portal provisioning APIs.
public protocol ProvisioningService: Sendable {
    /// Gets the resource ID for a bundle identifier.
    func getBundleId(identifier: String) async throws -> String?

    /// Registers a new device in the Developer Portal.
    func registerDevice(name: String, udid: String, platform: ProvisioningAPI.Platform) async throws -> ProvisioningAPI.Device

    /// Lists all devices, optionally filtered by platform.
    func listDevices(platform: ProvisioningAPI.Platform?) async throws -> [ProvisioningAPI.Device]

    /// Lists all certificates, optionally filtered by type.
    func listCertificates(filterType: ProvisioningAPI.CertificateType?) async throws -> [ProvisioningAPI.Certificate]

    /// Creates a new certificate from a CSR.
    func createCertificate(csrContent: String, type: ProvisioningAPI.CertificateType) async throws -> ProvisioningAPI.Certificate

    /// Deletes a certificate by ID.
    func deleteCertificate(id: String) async throws

    /// Creates a new provisioning profile.
    func createProfile(name: String, type: ProvisioningAPI.ProfileType, bundleId: String, certificateIds: [String], deviceIds: [String]?) async throws -> ProvisioningAPI.Profile

    /// Lists profiles, optionally filtered by name.
    func listProfiles(name: String?) async throws -> [ProvisioningAPI.Profile]

    /// Deletes a profile by ID.
    func deleteProfile(id: String) async throws
}
