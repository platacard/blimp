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
        
        XCTAssertThrowsError(try encrypter.decrypt(data: encryptedData, password: wrongPassword))
    }
    
    func testDecryptInvalidData() {
        let encrypter = FileEncrypter()
        let invalidData = "Not encrypted".data(using: .utf8)!
        
        XCTAssertThrowsError(try encrypter.decrypt(data: invalidData, password: "pass"))
    }
}

