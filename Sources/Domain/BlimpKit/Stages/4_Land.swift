import Foundation
import TestflightAPI
import AppsAPI
import JWTProvider
import Cronista

public extension Blimp {
    /// Approach stage:
    /// - TestFlight / App Store delivery operations
    struct Land: FlightStage {
        package var type: FlightStage.Type { Self.self }
        private var logger: Cronista { Cronista(module: "Blimp", category: "Land") }
        private let testflightAPI: TestflightAPI
        private let appsAPI: AppsAPI
        
        public init(jwtProvider: JWTProviding = DefaultJWTProvider()) {
            self.testflightAPI = TestflightAPI(jwtProvider: jwtProvider)
            self.appsAPI = AppsAPI(jwtProvider: jwtProvider)
        }
    }
}

extension Blimp.Land {
    /// Assign beta groups for the build. Either internal or external
    ///
    /// Beta groups are queried by name and filtered by the app's bundle id
    public func engage(bundleId: String, buildId: String, betaGroups: [String]) async throws {
        let appId = try await appsAPI.getAppId(bundleId: bundleId)
        try await testflightAPI.setBetaGroups(appId: appId, buildId: buildId, betaGroups: betaGroups)
    }
    
    /// Create a "What's New" section for the TestFlight build
    /// - Parameters:
    ///   - buildId: Identifier of the build resource
    ///   - changelog: Changes description
    public func report(localizationIds: [String], changelog: String) async throws {
        try await testflightAPI.setChangelog(localizationIds: localizationIds, changelog: changelog)
    }
    
    /// Send a build to a testflight external review
    /// - Parameter buildId: processed build id
    public func confirm(buildId: String) async throws {
        try await testflightAPI.sendToTestflightReview(buildId: buildId)
    }
}
