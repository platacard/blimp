import Foundation
import CryptoKit
import CommonCrypto
import ProvisioningAPI

/// AES-256-GCM encryption with PBKDF2 key derivation.
public struct FileEncrypter: EncryptionService, Sendable {

    public init() {}

    public func encrypt(data: Data, password: String) throws -> Data {
        let salt = try generateSalt()
        let key = try deriveKey(password: password, salt: salt)
        let sealedBox = try AES.GCM.seal(data, using: key)

        // Format: Salt (32 bytes) + Nonce (12 bytes) + Ciphertext + Tag (16 bytes)
        var combined = Data()
        combined.append(salt)
        combined.append(sealedBox.combined ?? (sealedBox.nonce + sealedBox.ciphertext + sealedBox.tag))
        return combined
    }

    public func decrypt(data: Data, password: String) throws -> Data {
        guard data.count >= 60 else { throw Error.invalidData }

        let salt = data.prefix(32)
        let boxData = data.dropFirst(32)
        let key = try deriveKey(password: password, salt: salt)

        let sealedBox = try AES.GCM.SealedBox(combined: boxData)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derivedKey = Data(count: 32)

        let status = derivedKey.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.baseAddress, passBytes.count,
                        saltBytes.baseAddress, saltBytes.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        100_000,
                        keyBytes.baseAddress, keyBytes.count
                    )
                }
            }
        }

        guard status == kCCSuccess else { throw Error.keyDerivationFailed }
        return SymmetricKey(data: derivedKey)
    }

    private func generateSalt() throws -> Data {
        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, 32, baseAddress)
        }
        guard status == errSecSuccess else { throw Error.saltGenerationFailed }
        return salt
    }

    public enum Error: Swift.Error, LocalizedError {
        case invalidData
        case keyDerivationFailed
        case saltGenerationFailed

        public var errorDescription: String? {
            switch self {
            case .invalidData: return "Invalid encrypted data format"
            case .keyDerivationFailed: return "Failed to derive key from password"
            case .saltGenerationFailed: return "Failed to generate random salt"
            }
        }
    }
}
