import XCTest
@testable import BlimpKit
@testable import TestflightAPI

final class ApproachProcessingTests: XCTestCase {

    // MARK: - ProcessingState Tests

    func testProcessingStateIsTerminalError() {
        // Terminal errors should return true
        XCTAssertTrue(TestflightAPI.ProcessingState.processingException.isTerminalError)
        XCTAssertTrue(TestflightAPI.ProcessingState.missingExportCompliance.isTerminalError)
        XCTAssertTrue(TestflightAPI.ProcessingState.betaRejected.isTerminalError)
        XCTAssertTrue(TestflightAPI.ProcessingState.invalidBinary.isTerminalError)

        // Non-terminal states should return false
        XCTAssertFalse(TestflightAPI.ProcessingState.processing.isTerminalError)
        XCTAssertFalse(TestflightAPI.ProcessingState.valid.isTerminalError)
        XCTAssertFalse(TestflightAPI.ProcessingState.failed.isTerminalError)
        XCTAssertFalse(TestflightAPI.ProcessingState.invalid.isTerminalError)
    }

    func testAllBasicStatesContainsFourStates() {
        let basicStates = TestflightAPI.ProcessingState.allBasicStates
        XCTAssertEqual(basicStates.count, 4)
        XCTAssertTrue(basicStates.contains(.processing))
        XCTAssertTrue(basicStates.contains(.valid))
        XCTAssertTrue(basicStates.contains(.failed))
        XCTAssertTrue(basicStates.contains(.invalid))
    }

    // MARK: - BuildProcessingResult Tests

    func testBuildProcessingResultInitialization() {
        let result = TestflightAPI.BuildProcessingResult(
            processingState: .valid,
            buildBundleID: "bundle-123",
            buildLocalizationIDs: ["loc-1", "loc-2"]
        )

        XCTAssertEqual(result.processingState, .valid)
        XCTAssertEqual(result.buildBundleID, "bundle-123")
        XCTAssertEqual(result.buildLocalizationIDs, ["loc-1", "loc-2"])
    }

    func testBuildProcessingResultWithTerminalState() {
        let result = TestflightAPI.BuildProcessingResult(
            processingState: .invalidBinary,
            buildBundleID: "bundle-456",
            buildLocalizationIDs: []
        )

        XCTAssertTrue(result.processingState.isTerminalError)
        XCTAssertEqual(result.processingState, .invalidBinary)
    }

    // MARK: - Approach Error Tests

    func testApproachErrorDescriptions() {
        XCTAssertNotNil(Blimp.Approach.Error.noBuildId.errorDescription)
        XCTAssertNotNil(Blimp.Approach.Error.failedProcessing.errorDescription)
        XCTAssertNotNil(Blimp.Approach.Error.invalidBinary.errorDescription)
        XCTAssertNotNil(Blimp.Approach.Error.processingException.errorDescription)
        XCTAssertNotNil(Blimp.Approach.Error.missingExportCompliance.errorDescription)
        XCTAssertNotNil(Blimp.Approach.Error.betaRejected.errorDescription)
        XCTAssertNotNil(Blimp.Approach.Error.failedToGetAppSizes.errorDescription)
    }

    func testInvalidBinaryErrorContainsInfoPlistHint() {
        let error = Blimp.Approach.Error.invalidBinary
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("Info.plist"))
        XCTAssertTrue(description.contains("CFBundleShortVersionString"))
    }

    func testMissingExportComplianceErrorContainsActionableInfo() {
        let error = Blimp.Approach.Error.missingExportCompliance
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("export compliance"))
        XCTAssertTrue(description.contains("App Store Connect"))
    }

    func testBetaRejectedErrorContainsActionableInfo() {
        let error = Blimp.Approach.Error.betaRejected
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("rejected"))
        XCTAssertTrue(description.contains("App Store Connect"))
    }

    // MARK: - ProcessingState Equatable Tests

    func testProcessingStateEquality() {
        XCTAssertEqual(TestflightAPI.ProcessingState.processing, TestflightAPI.ProcessingState.processing)
        XCTAssertNotEqual(TestflightAPI.ProcessingState.processing, TestflightAPI.ProcessingState.valid)
        XCTAssertNotEqual(TestflightAPI.ProcessingState.invalidBinary, TestflightAPI.ProcessingState.invalid)
    }
}
