import Foundation

/// Credentials for App Store Connect (ASC)
public protocol ASCCredentialsTrait: Sendable {
    var env: [String: String] { get }
    var apiKeyId: String? { get }
    var apiIssuerId: String? { get }
    var apiPrivateKey: String? { get }
}

/// Default implementation aka `trait`
public extension ASCCredentialsTrait {
    var env: [String: String] { ProcessInfo.processInfo.environment }
    
    var apiKeyId: String? { env[C.apiKeyId] }
    var apiIssuerId: String? { env[C.apiIssuerId] }
    var apiPrivateKey: String? { env[C.apiPrivateKey] }
}

// Concrete type for usage
public actor ASCCredentials: ASCCredentialsTrait {
    public init(from _: Source) {}
    public enum Source { case environment }
}

// MARK: - Constants

private enum C {
    static let apiKeyId = "APPSTORE_CONNECT_API_KEY_ID"
    static let apiIssuerId = "APPSTORE_CONNECT_API_ISSUER_ID"
    static let apiPrivateKey = "APPSTORE_CONNECT_API_PRIVATE_KEY"
}
