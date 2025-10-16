import Foundation
import Cronista
import ASCCredentials

public protocol JWTProviding: ASCCredentialsTrait, Sendable {
    /// Get token from implemented token provider
    /// - Parameters:
    ///   - keyFolderURL: folder to store the private AuthKey
    ///   - keyId: id of the private key
    ///   - keyIssuer: key issuer from app store connect
    ///   - lifetimeSec: token lifetime in seconds
    /// - Returns: `Token` instance
    func token(
        keyFolderURL: URL,
        keyId: String,
        keyIssuer: String,
        lifetimeSec: TimeInterval
    ) throws -> String
}

public extension JWTProviding {
    /// Default implementation with 2 minutes token lifetime
    func token(lifetime: TimeInterval = 120) throws -> String {
        guard let apiKeyId, let apiIssuerId else {
            throw JWTProviderError.credentialsNotFound
        }
        
        return try token(
            keyFolderURL: keyFolderURL,
            keyId: apiKeyId,
            keyIssuer: apiIssuerId,
            lifetimeSec: lifetime
        )
    }
}

public struct DefaultJWTProvider: JWTProviding {
    
    public init() {}
    
    public func token(keyFolderURL: URL, keyId: String, keyIssuer: String, lifetimeSec: TimeInterval) throws -> String {
        let keyURL = keyFolderURL.appending(path: "AuthKey_\(keyId).p8")
        
        guard FileManager.default.fileExists(atPath: keyURL.path()) else {
            throw JWTProviderError.privateKeyNotFound
        }
        
        let pemKeyRepresentation = try String(contentsOf: keyURL)
        let jwt = JWT(keyIdentifier: keyId, issuerIdentifier: keyIssuer, expireDuration: lifetimeSec)
        
        let signedJWT = try jwt.signedToken(using: .init(pemRepresentation: pemKeyRepresentation), dateProvider: { .now })
        
        return signedJWT
    }
}

enum JWTProviderError: Error {
    case credentialsNotFound
    case privateKeyNotFound
    case signingFailed
}
