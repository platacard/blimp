import XCTest
import TestflightAPI
import AppsAPI
@testable import BlimpKit

final class LandStageTests: XCTestCase {

    // MARK: - engage() Tests

    func testEngageSingleBetaGroup() async throws {
        let mockBeta = MockBetaManagementService()
        let mockAppQuery = MockAppQueryService()
        mockAppQuery.appIds = ["com.example.app": "app-123"]

        let land = Blimp.Land(
            betaManagementService: mockBeta,
            appQueryService: mockAppQuery
        )

        try await land.engage(bundleId: "com.example.app", buildId: "build-456", betaGroups: ["Beta Testers"])

        XCTAssertEqual(mockBeta.setBetaGroupsCalls.count, 1)
        XCTAssertEqual(mockBeta.setBetaGroupsCalls.first?.appId, "app-123")
        XCTAssertEqual(mockBeta.setBetaGroupsCalls.first?.buildId, "build-456")
        XCTAssertEqual(mockBeta.setBetaGroupsCalls.first?.betaGroups, ["Beta Testers"])
    }

    func testEngageMultipleBetaGroups() async throws {
        let mockBeta = MockBetaManagementService()
        let mockAppQuery = MockAppQueryService()
        mockAppQuery.appIds = ["com.example.app": "app-123"]

        let land = Blimp.Land(
            betaManagementService: mockBeta,
            appQueryService: mockAppQuery
        )

        try await land.engage(
            bundleId: "com.example.app",
            buildId: "build-456",
            betaGroups: ["Internal Testers", "External Testers", "QA Team"]
        )

        XCTAssertEqual(mockBeta.setBetaGroupsCalls.count, 1)
        XCTAssertEqual(mockBeta.setBetaGroupsCalls.first?.betaGroups.count, 3)
        XCTAssertTrue(mockBeta.setBetaGroupsCalls.first?.betaGroups.contains("QA Team") ?? false)
    }

    func testEngageInvalidBundleId() async throws {
        let mockBeta = MockBetaManagementService()
        let mockAppQuery = MockAppQueryService()
        // No app IDs configured - will throw

        let land = Blimp.Land(
            betaManagementService: mockBeta,
            appQueryService: mockAppQuery
        )

        do {
            try await land.engage(bundleId: "com.invalid.app", buildId: "build-456", betaGroups: ["Beta Testers"])
            XCTFail("Expected error for invalid bundle ID")
        } catch {
            XCTAssertEqual(mockBeta.setBetaGroupsCalls.count, 0)
        }
    }

    // MARK: - report() Tests

    func testReportChangelog() async throws {
        let mockBeta = MockBetaManagementService()
        let mockAppQuery = MockAppQueryService()

        let land = Blimp.Land(
            betaManagementService: mockBeta,
            appQueryService: mockAppQuery
        )

        try await land.report(localizationIds: ["loc-1", "loc-2"], changelog: "- Fixed bugs\n- Added features")

        XCTAssertEqual(mockBeta.setChangelogCalls.count, 1)
        XCTAssertEqual(mockBeta.setChangelogCalls.first?.localizationIds, ["loc-1", "loc-2"])
        XCTAssertEqual(mockBeta.setChangelogCalls.first?.changelog, "- Fixed bugs\n- Added features")
    }

    // MARK: - confirm() Tests

    func testConfirmReviewSubmission() async throws {
        let mockBeta = MockBetaManagementService()
        let mockAppQuery = MockAppQueryService()

        let land = Blimp.Land(
            betaManagementService: mockBeta,
            appQueryService: mockAppQuery
        )

        try await land.confirm(buildId: "build-789")

        XCTAssertEqual(mockBeta.sendToReviewCalls.count, 1)
        XCTAssertEqual(mockBeta.sendToReviewCalls.first, "build-789")
    }

    func testConfirmReviewSubmissionPropagatesError() async throws {
        let mockBeta = MockBetaManagementService()
        mockBeta.errorToThrow = NSError(domain: "API", code: 409, userInfo: [NSLocalizedDescriptionKey: "Already submitted"])
        let mockAppQuery = MockAppQueryService()

        let land = Blimp.Land(
            betaManagementService: mockBeta,
            appQueryService: mockAppQuery
        )

        do {
            try await land.confirm(buildId: "build-789")
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual((error as NSError).code, 409)
        }
    }
}
