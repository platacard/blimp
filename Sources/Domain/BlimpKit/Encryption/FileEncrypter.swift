import Foundation
import CommonCrypto
import ProvisioningAPI

/// AES-256-CBC encryption with PBKDF2 key derivation.
///
/// Produces files compatible with OpenSSL CLI:
/// ```
/// # Encrypt
/// openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -in file -out file.enc -pass pass:PASSWORD
/// # Decrypt
/// openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -in file.enc -out file -pass pass:PASSWORD
/// ```
public struct FileEncrypter: EncryptionService, Sendable {

    private static let magic = Data("Salted__".utf8)
    private static let saltSize = 8
    private static let keySize = kCCKeySizeAES256 // 32
    private static let ivSize = kCCBlockSizeAES128 // 16
    private static let iterations: UInt32 = 600_000

    public init() {}

    public func encrypt(data: Data, password: String) throws -> Data {
        let salt = try generateSalt()
        let (key, iv) = try deriveKeyAndIV(password: password, salt: salt)

        let bufferSize = data.count + kCCBlockSizeAES128
        var ciphertext = Data(count: bufferSize)
        var bytesEncrypted = 0

        let status = ciphertext.withUnsafeMutableBytes { cipherBuf in
            data.withUnsafeBytes { dataBuf in
                key.withUnsafeBytes { keyBuf in
                    iv.withUnsafeBytes { ivBuf in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuf.baseAddress, Self.keySize,
                            ivBuf.baseAddress,
                            dataBuf.baseAddress, data.count,
                            cipherBuf.baseAddress, bufferSize,
                            &bytesEncrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { throw Error.encryptionFailed }
        ciphertext.removeSubrange(bytesEncrypted...)

        // OpenSSL format: "Salted__" + salt (8 bytes) + ciphertext
        var result = Data()
        result.append(Self.magic)
        result.append(salt)
        result.append(ciphertext)
        return result
    }

    public func decrypt(data: Data, password: String) throws -> Data {
        let headerSize = Self.magic.count + Self.saltSize // 16
        guard data.count >= headerSize,
              data.prefix(Self.magic.count) == Self.magic
        else { throw Error.invalidData }

        let salt = data[Self.magic.count ..< headerSize]
        let ciphertext = data[headerSize...]
        let (key, iv) = try deriveKeyAndIV(password: password, salt: salt)

        let bufferSize = ciphertext.count + kCCBlockSizeAES128
        var plaintext = Data(count: bufferSize)
        var bytesDecrypted = 0

        let status = plaintext.withUnsafeMutableBytes { plainBuf in
            ciphertext.withUnsafeBytes { cipherBuf in
                key.withUnsafeBytes { keyBuf in
                    iv.withUnsafeBytes { ivBuf in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuf.baseAddress, Self.keySize,
                            ivBuf.baseAddress,
                            cipherBuf.baseAddress, ciphertext.count,
                            plainBuf.baseAddress, bufferSize,
                            &bytesDecrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { throw Error.decryptionFailed }
        plaintext.removeSubrange(bytesDecrypted...)
        return plaintext
    }

    /// Derives 48 bytes (32 key + 16 IV) via PBKDF2-HMAC-SHA256, matching OpenSSL behavior.
    private func deriveKeyAndIV(password: String, salt: Data) throws -> (key: Data, iv: Data) {
        let passwordData = Data(password.utf8)
        let derivedLength = Self.keySize + Self.ivSize // 48
        var derived = Data(count: derivedLength)

        let status = derived.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.baseAddress, passBytes.count,
                        saltBytes.baseAddress, saltBytes.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        Self.iterations,
                        keyBytes.baseAddress, keyBytes.count
                    )
                }
            }
        }

        guard status == kCCSuccess else { throw Error.keyDerivationFailed }

        let key = derived.prefix(Self.keySize)
        let iv = derived.suffix(Self.ivSize)
        return (key, iv)
    }

    private func generateSalt() throws -> Data {
        var salt = Data(count: Self.saltSize)
        let status = salt.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, Self.saltSize, baseAddress)
        }
        guard status == errSecSuccess else { throw Error.saltGenerationFailed }
        return salt
    }

    public enum Error: Swift.Error, LocalizedError {
        case invalidData
        case keyDerivationFailed
        case saltGenerationFailed
        case encryptionFailed
        case decryptionFailed

        public var errorDescription: String? {
            switch self {
            case .invalidData: return "Invalid encrypted data format"
            case .keyDerivationFailed: return "Failed to derive key from password"
            case .saltGenerationFailed: return "Failed to generate random salt"
            case .encryptionFailed: return "Encryption failed"
            case .decryptionFailed: return "Decryption failed"
            }
        }
    }
}
