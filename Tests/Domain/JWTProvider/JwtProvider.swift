import XCTest
@testable import JWTProvider
import Crypto
import Foundation

final class JwtProviderTests: XCTestCase {
    
    // MARK: - DefaultJWTProvider Tests
    
    func testDefaultJWTProviderInit() {
        // Given/When
        let provider = DefaultJWTProvider()
        // Then
        XCTAssertNotNil(provider)
    }
    
    func testDefaultJWTProviderTokenWithInvalidBase64Key() throws {
        // Given
        let provider = DefaultJWTProvider()
        let keyId = "TEST_KEY_ID"
        let keyIssuer = "TEST_ISSUER"
        let invalidBase64Key = "not-valid-base64"
        let lifetime: TimeInterval = 120
        
        // When/Then
        XCTAssertThrowsError(try provider.token(
            keyId: keyId,
            keyIssuer: keyIssuer,
            privateKey: invalidBase64Key,
            lifetimeSec: lifetime
        ), "Should throw error for invalid base64 key")
    }
    
    func testDefaultJWTProviderTokenWithValidKey() throws {
        // Given
        let provider = DefaultJWTProvider()
        let keyId = "TEST_KEY_ID"
        let keyIssuer = "TEST_ISSUER"
        let privateKey = try generateTestPrivateKey()
        let lifetime: TimeInterval = 120
        
        // When
        let token = try provider.token(
            keyId: keyId,
            keyIssuer: keyIssuer,
            privateKey: privateKey,
            lifetimeSec: lifetime
        )
        
        // Then
        XCTAssertFalse(token.isEmpty)
        let parts = token.components(separatedBy: ".")
        XCTAssertEqual(parts.count, 3, "JWT should have 3 parts: header.payload.signature")
    }
    
    // MARK: - JWT Tests
    
    func testJWTCreationWithIssuer() {
        // Given
        let keyId = "TEST_KEY_ID"
        let issuer = "TEST_ISSUER"
        let expireDuration: TimeInterval = 120
        
        // When
        let jwt = JWT(keyIdentifier: keyId, issuerIdentifier: issuer, expireDuration: expireDuration)
        
        // Then
        XCTAssertNotNil(jwt)
    }
    
    func testJWTCreationWithoutIssuer() {
        // Given
        let keyId = "TEST_KEY_ID"
        let expireDuration: TimeInterval = 120
        
        // When
        let jwt = JWT(keyIdentifier: keyId, issuerIdentifier: nil, expireDuration: expireDuration)
        
        // Then
        XCTAssertNotNil(jwt)
    }
    
    func testJWTSigningWithValidKey() throws {
        // Given
        let keyId = "TEST_KEY_ID"
        let issuer = "TEST_ISSUER"
        let expireDuration: TimeInterval = 120
        let jwt = JWT(keyIdentifier: keyId, issuerIdentifier: issuer, expireDuration: expireDuration)
        let privateKey = try generateP256PrivateKey()
        
        // When
        let token = try jwt.signedToken(using: privateKey)
        
        // Then
        XCTAssertFalse(token.isEmpty)
        let parts = token.components(separatedBy: ".")
        XCTAssertEqual(parts.count, 3)
    }
    
    func testJWTSigningWithCustomDateProvider() throws {
        // Given
        let keyId = "TEST_KEY_ID"
        let issuer = "TEST_ISSUER"
        let expireDuration: TimeInterval = 120
        let jwt = JWT(keyIdentifier: keyId, issuerIdentifier: issuer, expireDuration: expireDuration)
        let privateKey = try generateP256PrivateKey()
        let fixedDate = Date(timeIntervalSince1970: 1000000)
        let dateProvider: JWT.DateProvider = { fixedDate }
        
        // When
        let token = try jwt.signedToken(using: privateKey, dateProvider: dateProvider)
        
        // Then
        XCTAssertFalse(token.isEmpty)
        let parts = token.components(separatedBy: ".")
        XCTAssertEqual(parts.count, 3)
    }
    
    // MARK: - JWT Token Expiration Tests
    
    func testTokenIsNotExpired() throws {
        // Given
        let provider = DefaultJWTProvider()
        let keyId = "TEST_KEY_ID"
        let keyIssuer = "TEST_ISSUER"
        let privateKey = try generateTestPrivateKey()
        let lifetime: TimeInterval = 120
        
        // When
        let token = try provider.token(
            keyId: keyId,
            keyIssuer: keyIssuer,
            privateKey: privateKey,
            lifetimeSec: lifetime
        )
        
        // Then
        XCTAssertFalse(token.isExpired, "Token should not be expired immediately after creation")
    }
    
    func testTokenIsExpired() throws {
        // Given
        let provider = DefaultJWTProvider()
        let keyId = "TEST_KEY_ID"
        let keyIssuer = "TEST_ISSUER"
        let privateKey = try generateTestPrivateKey()
        let lifetime: TimeInterval = -100 // Negative lifetime means already expired
        
        // When
        let token = try provider.token(
            keyId: keyId,
            keyIssuer: keyIssuer,
            privateKey: privateKey,
            lifetimeSec: lifetime
        )
        
        // Then
        XCTAssertTrue(token.isExpired, "Token should be expired with negative lifetime")
    }
    
    func testTokenDecodingWithValidToken() throws {
        // Given
        let provider = DefaultJWTProvider()
        let keyId = "TEST_KEY_ID"
        let keyIssuer = "TEST_ISSUER"
        let privateKey = try generateTestPrivateKey()
        let lifetime: TimeInterval = 120
        
        // When
        let token = try provider.token(
            keyId: keyId,
            keyIssuer: keyIssuer,
            privateKey: privateKey,
            lifetimeSec: lifetime
        )
        
        // Then
        let parts = token.components(separatedBy: ".")
        XCTAssertEqual(parts.count, 3)
        
        // Verify the token structure
        let header = parts[0]
        let payload = parts[1]
        let signature = parts[2]
        
        XCTAssertFalse(header.isEmpty)
        XCTAssertFalse(payload.isEmpty)
        XCTAssertFalse(signature.isEmpty)
    }
    
    func testTokenDecodingWithInvalidToken() {
        // Given
        let invalidToken = "invalid.token"
        
        // When
        let isExpired = invalidToken.isExpired
        
        // Then
        XCTAssertTrue(isExpired, "Invalid token should be considered expired")
    }
    
    func testTokenDecodingWithTooFewParts() {
        // Given
        let invalidToken = "only.twoparts"
        
        // When
        let isExpired = invalidToken.isExpired
        
        // Then
        XCTAssertTrue(isExpired, "Token with wrong part count should be considered expired")
    }
    
    // MARK: - JWTProviderError Tests
    
    func testJWTProviderThrowsErrorForInvalidBase64() throws {
        // Given
        let provider = DefaultJWTProvider()
        let invalidBase64Key = "not-valid-base64"
        
        // When/Then
        do {
            _ = try provider.token(
                keyId: "TEST",
                keyIssuer: "TEST",
                privateKey: invalidBase64Key,
                lifetimeSec: 120
            )
            XCTFail("Should have thrown an error")
        } catch {
            // Expected to throw an error
            XCTAssertNotNil(error)
        }
    }
}

// MARK: - Helpers

extension JwtProviderTests {
    
    /// Generates a valid P256 private key in base64 format for testing
    func generateTestPrivateKey() throws -> String {
        let privateKey = try generateP256PrivateKey()
        let derRepresentation = privateKey.derRepresentation
        return derRepresentation.base64EncodedString()
    }
    
    /// Generates a P256 private key for testing
    func generateP256PrivateKey() throws -> P256.Signing.PrivateKey {
        return P256.Signing.PrivateKey()
    }
}
