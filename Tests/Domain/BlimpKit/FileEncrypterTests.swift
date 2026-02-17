import XCTest
@testable import BlimpKit

final class FileEncrypterTests: XCTestCase {
    func testEncryptDecrypt() throws {
        let encrypter = FileEncrypter()
        let originalData = "Hello World".data(using: .utf8)!
        let password = "secret_password"

        // Encrypt
        let encryptedData = try encrypter.encrypt(data: originalData, password: password)
        XCTAssertNotEqual(encryptedData, originalData)

        // Verify OpenSSL header
        XCTAssertEqual(String(data: encryptedData.prefix(8), encoding: .utf8), "Salted__")

        // Decrypt
        let decryptedData = try encrypter.decrypt(data: encryptedData, password: password)
        XCTAssertEqual(decryptedData, originalData)
    }

    func testDecryptInvalidPassword() throws {
        let encrypter = FileEncrypter()
        let originalData = "Hello World".data(using: .utf8)!
        let password = "secret_password"
        let wrongPassword = "wrong_password"

        let encryptedData = try encrypter.encrypt(data: originalData, password: password)

        // CBC mode doesn't authenticate — wrong password either throws (bad padding)
        // or produces garbage. Either way, it must not return the original data.
        if let result = try? encrypter.decrypt(data: encryptedData, password: wrongPassword) {
            XCTAssertNotEqual(result, originalData)
        }
    }

    func testDecryptInvalidData() {
        let encrypter = FileEncrypter()
        let invalidData = "Not encrypted".data(using: .utf8)!

        XCTAssertThrowsError(try encrypter.decrypt(data: invalidData, password: "pass"))
    }

    func testOpenSSLCompatibility() throws {
        let encrypter = FileEncrypter()
        let originalString = "OpenSSL compatibility test data"
        let originalData = originalString.data(using: .utf8)!
        let password = "test_password_123"

        let encryptedData = try encrypter.encrypt(data: originalData, password: password)

        // Write encrypted data to temp file
        let encryptedFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_encrypted.bin")
        let decryptedFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_decrypted.bin")
        defer {
            try? FileManager.default.removeItem(at: encryptedFile)
            try? FileManager.default.removeItem(at: decryptedFile)
        }

        try encryptedData.write(to: encryptedFile)

        // Decrypt with openssl CLI
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = [
            "enc", "-d", "-aes-256-cbc",
            "-pbkdf2", "-iter", "600000", "-md", "sha256",
            "-in", encryptedFile.path,
            "-out", decryptedFile.path,
            "-pass", "pass:\(password)"
        ]

        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "openssl decryption failed")

        let decryptedData = try Data(contentsOf: decryptedFile)
        XCTAssertEqual(String(data: decryptedData, encoding: .utf8), originalString)
    }
}
