import Foundation

/// Service for querying build information from App Store Connect.
public protocol BuildQueryService: Sendable {
    func getBuildID(
        appId: String,
        appVersion: String,
        buildNumber: String,
        states: [TestflightAPI.BetaProcessingState],
        limit: Int,
        sorted: [TestflightAPI.BetaBuildSort]
    ) async throws -> String?
    func getBuildProcessingResult(id: String) async throws -> TestflightAPI.BuildProcessingResult
    func getBundleBuildSizes(buildBundleID: String, devices: [String]) async throws -> [BundleBuildFileSize]
}

extension BuildQueryService {
    /// Convenience method with default parameters
    public func getBuildID(appId: String, appVersion: String, buildNumber: String) async throws -> String? {
        try await getBuildID(
            appId: appId,
            appVersion: appVersion,
            buildNumber: buildNumber,
            states: TestflightAPI.BetaProcessingState.allCases,
            limit: 10,
            sorted: [.uploadDateDesc]
        )
    }
}

/// Service for managing TestFlight beta groups and reviews.
public protocol BetaManagementService: Sendable {
    func setBetaGroups(appId: String, buildId: String, betaGroups: [String], isInternal: Bool) async throws
    func setChangelog(localizationIds: [String], changelog: String) async throws
    func sendToTestflightReview(buildId: String) async throws
}

extension BetaManagementService {
    /// Convenience method with default isInternal = false
    public func setBetaGroups(appId: String, buildId: String, betaGroups: [String]) async throws {
        try await setBetaGroups(appId: appId, buildId: buildId, betaGroups: betaGroups, isInternal: false)
    }
}

// MARK: - TestflightAPI Conformance

extension TestflightAPI: BuildQueryService {}
extension TestflightAPI: BetaManagementService {}
