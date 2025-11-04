import Foundation
import Cronista
import ASCCredentials

public protocol JWTProviding: ASCCredentialsTrait, Sendable {
    /// Get token from implemented token provider
    /// - Parameters:
    ///   - keyId: id of the private key
    ///   - keyIssuer: key issuer from app store connect
    ///   - lifetimeSec: token lifetime in seconds
    ///   - privateKey: String
    /// - Returns: `Token` instance
    func token(
        keyId: String,
        keyIssuer: String,
        privateKey: String,
        lifetimeSec: TimeInterval
    ) throws -> String
}

public extension JWTProviding {
    /// Default implementation with 2 minutes token lifetime
    func token(lifetime: TimeInterval = 120) throws -> String {
        guard let apiKeyId, let apiIssuerId, let apiPrivateKey else {
            throw JWTProviderError.credentialsNotFound
        }
        
        return try token(
            keyId: apiKeyId,
            keyIssuer: apiIssuerId,
            privateKey: apiPrivateKey,
            lifetimeSec: lifetime
        )
    }
}

public struct DefaultJWTProvider: JWTProviding {
        
    public init() {}
    
    /// Creates a new JWT token to use for accessing ASC API
    /// - Parameters:
    ///   - keyId:  Your private key ID from App Store Connect (Ex: 2X9R4HXF34)
    ///   - keyIssuer: Your issuer ID from the API Keys page in App Store Connect (Ex: 57246542-96fe-1a63-e053-0824d011072a)
    ///   - privateKey:  Your private key from the .p8 file. Without the -----BEGIN PRIVATE KEY----- and -----END PRIVATE KEY----- lines.
    ///   - lifetimeSec: lifetime > 20 min (1200s) is not valid, set to max of 1200, 120 is the default.
    public func token(keyId: String, keyIssuer: String, privateKey: String, lifetimeSec: TimeInterval) throws -> String {
        guard let base64Key = Data(base64Encoded: privateKey) else {
            throw JWTProviderError.invalidBase64EncodedPrivateKey
        }
        
        let jwt = JWT(keyIdentifier: keyId, issuerIdentifier: keyIssuer, expireDuration: lifetimeSec)
        let signedJWT = try jwt.signedToken(using: .init(derRepresentation: base64Key), dateProvider: { .now })
        
        return signedJWT
    }
}

enum JWTProviderError: Error {
    case credentialsNotFound
    case privateKeyNotFound
    case signingFailed
    case invalidBase64EncodedPrivateKey
}
