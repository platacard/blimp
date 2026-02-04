import Foundation

/// Service for querying app information from App Store Connect.
public protocol AppQueryService: Sendable {
    func getAppId(bundleId: String) async throws -> String
}

// MARK: - AppsAPI Conformance

extension AppsAPI: AppQueryService {}
