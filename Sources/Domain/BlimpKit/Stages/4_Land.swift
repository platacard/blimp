import Foundation
import TestflightAPI
import AppsAPI
import JWTProvider
import Cronista

public extension Blimp {
    /// Land stage:
    /// - TestFlight / App Store delivery operations
    struct Land: FlightStage, Sendable {
        package var type: FlightStage.Type { Self.self }
        private let betaManagementService: BetaManagementService
        private let appQueryService: AppQueryService

        nonisolated(unsafe) private let logger: Cronista

        /// Initialize with protocol dependencies for testability
        public init(
            betaManagementService: BetaManagementService,
            appQueryService: AppQueryService
        ) {
            self.logger = Cronista(module: "blimp", category: "Land")
            self.betaManagementService = betaManagementService
            self.appQueryService = appQueryService
        }

        /// Convenience initializer for production use
        public init(jwtProvider: JWTProviding = DefaultJWTProvider()) {
            self.init(
                betaManagementService: TestflightAPI(jwtProvider: jwtProvider),
                appQueryService: AppsAPI(jwtProvider: jwtProvider)
            )
        }
    }
}

extension Blimp.Land {
    /// Assign beta groups for the build. Either internal or external
    ///
    /// Beta groups are queried by name and filtered by the app's bundle id
    public func engage(bundleId: String, buildId: String, betaGroups: [String]) async throws {
        let appId = try await appQueryService.getAppId(bundleId: bundleId)
        try await betaManagementService.setBetaGroups(appId: appId, buildId: buildId, betaGroups: betaGroups)
    }

    /// Create a "What's New" section for the TestFlight build
    /// - Parameters:
    ///   - buildId: Identifier of the build resource
    ///   - changelog: Changes description
    public func report(localizationIds: [String], changelog: String) async throws {
        try await betaManagementService.setChangelog(localizationIds: localizationIds, changelog: changelog)
    }

    /// Send a build to a testflight external review
    /// - Parameter buildId: processed build id
    public func confirm(buildId: String) async throws {
        try await betaManagementService.sendToTestflightReview(buildId: buildId)
    }
}
