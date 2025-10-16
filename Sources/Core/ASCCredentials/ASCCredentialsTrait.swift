import Foundation

/// Credentials for App Store Connect (ASC)
public protocol ASCCredentialsTrait {
    var env: [String: String] { get }
    var apiKeyId: String? { get }
    var apiIssuerId: String? { get }
    var keyFolderURL: URL { get }
}

/// Default implementation aka `trait`
public extension ASCCredentialsTrait {
    var env: [String: String] { ProcessInfo.processInfo.environment }
    var apiKeyId: String? { env[C.apiKeyId] }
    var apiIssuerId: String? { env[C.apiIssuerId] }
    var keyFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".appstoreconnect/private_keys")
    }
}

// MARK: - Constants

private enum C {
    static let apiKeyId = "APPSTORE_CONNECT_API_KEY_ID"
    static let apiIssuerId = "APPSTORE_CONNECT_API_ISSUER_ID"
}
